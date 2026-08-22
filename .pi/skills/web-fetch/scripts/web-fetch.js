#!/usr/bin/env node

/**
 * web-fetch.js — CLI tool to fetch and convert web pages to text/markdown/html.
 * Proxy: automatically inherits HTTP_PROXY / HTTPS_PROXY / ALL_PROXY / NO_PROXY
 * env vars (curl-style) via undici's ProxyAgent.
 *
 * Reference implementation from OpenCode:
 *   https://github.com/anomalyco/opencode/blob/0a601cf334b9a83cc2854108a2b860f25e6e7e8e/packages/opencode/src/tool/webfetch.ts
 *
 * OpenCode license: MIT
 *   https://github.com/anomalyco/opencode/blob/dev/LICENSE
 */

// ---------------------------------------------------------------------------
// Built-in imports
// ---------------------------------------------------------------------------

const fs = require("node:fs");
const path = require("node:path");
const { execSync } = require("node:child_process");

// ---------------------------------------------------------------------------
// Constants (mirrors OpenCode reference)
// ---------------------------------------------------------------------------

const MAX_RESPONSE_SIZE = 2 * 1024 * 1024; // 2 MiB
const DEFAULT_TIMEOUT = 30; // seconds
const MAX_TIMEOUT = 120; // seconds

const VALID_FORMATS = ["markdown", "text", "html"];

const CHROME_UA =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36";

// ---------------------------------------------------------------------------
// Bootstrap runtime dependencies (one-time, into script's own node_modules)
// ---------------------------------------------------------------------------

const SCRIPT_DIR = __dirname;
const NODE_MODULES = path.join(SCRIPT_DIR, "node_modules");

function ensureDeps() {
  // NOTE: installs the FULL set in one command. npm treats `--no-save`
  // packages as extraneous and prunes them on later partial installs, so
  // installing only what's missing would make dependencies thrash across runs.
  const deps = ["turndown", "htmlparser2", "@mozilla/readability", "jsdom"];
  if (hasProxyConfig()) deps.push("undici@7"); // see the "Proxy support" section below

  const missing = deps.filter((dep) => !isInstalled(dep));
  if (missing.length === 0) return;

  console.error(`[web-fetch] Installing dependencies: ${missing.join(", ")}...`);
  execSync(`npm install ${deps.join(" ")} --no-save --silent`, {
    cwd: SCRIPT_DIR,
    stdio: "pipe",
  });
  console.error("[web-fetch] Done.");
}

ensureDeps();

/**
 * Check whether a dependency is actually present and loadable.
 * Handles version specs ("undici@7" → undici) and guards against empty
 * scope dirs left behind by interrupted installs.
 */
function isInstalled(dep) {
  const name = dep.startsWith("@") ? dep : dep.replace(/@.*$/, "");
  try {
    const { version } = require(path.join(NODE_MODULES, name, "package.json"));
    // undici is pinned to major 7: newer majors broke the dispatcher contract
    // with the fetch built into Node (see the "Proxy support" section below).
    return dep.startsWith("undici@") ? Number(String(version).split(".")[0]) === 7 : true;
  } catch {
    return false;
  }
}

const TurndownService = require("turndown");
const { Parser } = require("htmlparser2");
const { JSDOM } = require("jsdom");
const { Readability } = require("@mozilla/readability");

// ---------------------------------------------------------------------------
// Help
// ---------------------------------------------------------------------------

function showHelp() {
  console.log(`web-fetch.js — Fetch a URL and return content as JSON, content is pruned to remove redundancy by default (unless --gross is used).

Usage:
  node web-fetch.js <url> [options]

Arguments:
  url                  URL to fetch (must start with http:// or https://)

Options:
  -f, --format <fmt>   Output format: markdown (default), text, or html
  -g, --gross          Skip content pruning; return the raw, noisy full-page output
  -t, --timeout <sec>  Request timeout in seconds (default: ${DEFAULT_TIMEOUT}, max: ${MAX_TIMEOUT})
  -h, --help           Show this help message and exit

Examples:
  node web-fetch.js https://example.com
  node web-fetch.js https://example.com --format text --timeout 10

Proxy:
  Proxy settings are inherited from the environment automatically (as curl does):
    HTTP_PROXY / http_proxy, HTTPS_PROXY / https_proxy, ALL_PROXY / all_proxy
  Bypass hosts with NO_PROXY / no_proxy (comma-separated list). When no proxy
  env vars are set, requests go direct. Uses undici (auto-installed on demand).

Output is JSON to stdout:
  { "ok": true, "url": "...", "format": "markdown", "output": "...", ... }

Reference:
  https://github.com/anomalyco/opencode/blob/0a601cf334b9a83cc2854108a2b860f25e6e7e8e/packages/opencode/src/tool/webfetch.ts

License: MIT
  https://github.com/anomalyco/opencode/blob/dev/LICENSE`);
}

// ---------------------------------------------------------------------------
// CLI argument parsing
// ---------------------------------------------------------------------------

function parseArgs() {
  const args = process.argv.slice(2);
  const result = { url: "", format: "markdown", timeout: DEFAULT_TIMEOUT, help: false, gross: false };

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "-h" || arg === "--help") {
      result.help = true;
    } else if (arg === "-f" || arg === "--format") {
      result.format = args[++i] || "markdown";
    } else if (arg.startsWith("--format=")) {
      result.format = arg.slice("--format=".length);
    } else if (arg === "-g" || arg === "--gross") {
      result.gross = true;
    } else if (arg === "-t" || arg === "--timeout") {
      result.timeout = parseFloat(args[++i]) || DEFAULT_TIMEOUT;
    } else if (arg.startsWith("--timeout=")) {
      result.timeout = parseFloat(arg.slice("--timeout=".length)) || DEFAULT_TIMEOUT;
    } else if (!arg.startsWith("-") && !result.url) {
      result.url = arg;
    }
  }

  return result;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function getAcceptHeader(format) {
  switch (format) {
    case "markdown":
      return "text/markdown;q=1.0, text/x-markdown;q=0.9, text/plain;q=0.8, text/html;q=0.7, */*;q=0.1";
    case "text":
      return "text/plain;q=1.0, text/markdown;q=0.9, text/html;q=0.8, */*;q=0.1";
    case "html":
      return "text/html;q=1.0, application/xhtml+xml;q=0.9, text/plain;q=0.8, text/markdown;q=0.7, */*;q=0.1";
    default:
      return "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8";
  }
}

function isImageMime(mime) {
  return /^image\/(png|jpe?g|gif|webp|bmp|svg\+xml|avif|ico)/i.test(mime);
}

// ---------------------------------------------------------------------------
// Content extraction via Mozilla Readability (removes boilerplate)
// ---------------------------------------------------------------------------

/**
 * Extract main article content from an HTML page.
 * Returns { title, content, textContent } or null if extraction fails.
 */
function extractContent(html, url) {
  try {
    const doc = new JSDOM(html, { url });
    const reader = new Readability(doc.window.document);
    const article = reader.parse();
    if (!article) return null;
    return {
      title: article.title || null,
      content: article.content,       // cleaned HTML
      textContent: article.textContent, // plain text
    };
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// HTML-to-text extraction (htmlparser2, mirrors OpenCode)
// ---------------------------------------------------------------------------

function extractTextFromHTML(html) {
  let text = "";
  let skipDepth = 0;

  const parser = new Parser({
    onopentag(name) {
      if (skipDepth > 0 || ["script", "style", "noscript", "iframe", "object", "embed"].includes(name)) {
        skipDepth++;
      }
    },
    ontext(input) {
      if (skipDepth === 0) text += input;
    },
    onclosetag() {
      if (skipDepth > 0) skipDepth--;
    },
  });

  parser.write(html);
  parser.end();

  return text.trim();
}

// ---------------------------------------------------------------------------
// HTML-to-Markdown conversion (turndown, mirrors OpenCode)
// ---------------------------------------------------------------------------

function convertHTMLToMarkdown(html) {
  const turndownService = new TurndownService({
    headingStyle: "atx",
    hr: "---",
    bulletListMarker: "-",
    codeBlockStyle: "fenced",
    emDelimiter: "*",
  });
  turndownService.remove(["script", "style", "meta", "link"]);
  return turndownService.turndown(html);
}

// ---------------------------------------------------------------------------
// Proxy support — inherit HTTP(S)_PROXY / ALL_PROXY / NO_PROXY env vars
// ---------------------------------------------------------------------------

// Node's built-in fetch ignores proxy environment variables, so when a proxy
// is configured we route requests through undici's ProxyAgent via the
// `dispatcher` option instead.

const proxyAgentCache = new Map(); // proxy URI -> ProxyAgent instance (or null)

/**
 * Read proxy settings from the environment, curl-style:
 *   HTTP_PROXY / http_proxy     proxy for http:// URLs
 *   HTTPS_PROXY / https_proxy   proxy for https:// URLs
 *   ALL_PROXY / all_proxy       fallback for either scheme
 *   NO_PROXY / no_proxy         comma-separated hosts to bypass the proxy
 */
function getProxyConfig() {
  const env = process.env;
  const allProxy = env.ALL_PROXY || env.all_proxy || "";
  const normalize = (value) => {
    const s = String(value || "").trim();
    if (!s) return "";
    return /^[a-z][a-z0-9+.-]*:\/\//i.test(s) ? s : `http://${s}`;
  };
  return {
    httpProxy: normalize(env.HTTP_PROXY || env.http_proxy || allProxy),
    httpsProxy: normalize(env.HTTPS_PROXY || env.https_proxy || allProxy),
    noProxy: String(env.NO_PROXY || env.no_proxy || "").trim(),
  };
}

function hasProxyConfig() {
  const { httpProxy, httpsProxy } = getProxyConfig();
  return Boolean(httpProxy || httpsProxy);
}

/**
 * Match a hostname against a NO_PROXY list. Entries are comma-separated and
 * may be "example.com", ".example.com" (also matches the bare domain),
 * "example.com:8080" (port ignored), or "*".
 */
function matchesNoProxy(hostname, noProxyList) {
  if (!noProxyList) return false;
  const host = hostname.toLowerCase();
  for (const raw of noProxyList.split(",")) {
    let entry = raw.trim().toLowerCase();
    if (!entry) continue;
    if (entry === "*") return true;
    entry = entry.replace(/^[a-z][a-z0-9+.-]*:\/\//, "").split(":")[0];
    if (!entry) continue;
    if (entry.startsWith(".")) {
      if (host === entry.slice(1) || host.endsWith(entry)) return true;
    } else if (host === entry || host.endsWith(`.${entry}`)) {
      return true;
    }
  }
  return false;
}

/**
 * Return an undici ProxyAgent for the given URL, or null when no proxy applies
 * (no proxy env vars, NO_PROXY match, unsupported scheme, or undici missing).
 */
function getProxyDispatcher(urlString) {
  const { httpProxy, httpsProxy, noProxy } = getProxyConfig();
  if (!httpProxy && !httpsProxy) return null;

  let targetUrl;
  try {
    targetUrl = new URL(urlString);
  } catch {
    return null;
  }
  if (matchesNoProxy(targetUrl.hostname, noProxy)) return null;

  const proxyUri =
    targetUrl.protocol === "https:" ? httpsProxy || httpProxy : httpProxy || httpsProxy;
  if (!proxyUri) return null;

  if (/^socks/i.test(proxyUri)) {
    console.error("[web-fetch] Warning: SOCKS proxies are not supported; fetching directly.");
    return null;
  }

  if (!proxyAgentCache.has(proxyUri)) {
    try {
      const { ProxyAgent } = require("undici");
      proxyAgentCache.set(proxyUri, new ProxyAgent(proxyUri));
    } catch (e) {
      console.error(
        `[web-fetch] Warning: cannot use proxy \"${proxyUri}\" (${e.message}); fetching directly.`,
      );
      proxyAgentCache.set(proxyUri, null);
    }
  }
  return proxyAgentCache.get(proxyUri);
}

// ---------------------------------------------------------------------------
// Core fetch logic
// ---------------------------------------------------------------------------

/**
 * Fetch a URL and return a structured result.
 *
 * @param {string}  url        Target URL
 * @param {string}  format     One of "markdown", "text", "html"
 * @param {number}  timeoutSec Request timeout in seconds
 * @returns {Promise<object>}  JSON-serialisable result { ok, url, format, ... }
 */
async function fetchUrl(url, format, timeoutSec, gross) {
  const timeoutMs = Math.min(timeoutSec * 1000, MAX_TIMEOUT * 1000);
  const signal = AbortSignal.timeout(timeoutMs);

  const headers = {
    "User-Agent": CHROME_UA,
    Accept: getAcceptHeader(format),
    "Accept-Language": "en-US,en;q=0.9",
  };

  // --- Perform request (with Cloudflare bot-detection retry) ---
  const dispatcher = getProxyDispatcher(url);
  const makeOptions = (extraHeaders) => {
    const options = { headers: extraHeaders, signal, redirect: "follow" };
    if (dispatcher) options.dispatcher = dispatcher; // route through proxy when configured
    return options;
  };

  let response;
  try {
    response = await fetch(url, makeOptions(headers));
  } catch (e) {
    if (e.name === "TimeoutError" || e.name === "AbortError") {
      throw new Error(`Request timed out after ${timeoutSec}s`);
    }
    throw e;
  }

  // Cloudflare challenge → retry once with honest UA
  if (response.status === 403 && response.headers.get("cf-mitigated") === "challenge") {
    try {
      response = await fetch(url, makeOptions({ ...headers, "User-Agent": "opencode" }));
    } catch (e) {
      if (e.name === "TimeoutError" || e.name === "AbortError") {
        throw new Error(`Request timed out after ${timeoutSec}s`);
      }
      throw e;
    }
  }

  const httpStatus = response.status;
  const httpOk = response.ok;

  // --- Size checks ---
  const contentLengthHeader = response.headers.get("content-length");
  if (contentLengthHeader && parseInt(contentLengthHeader, 10) > MAX_RESPONSE_SIZE) {
    throw new Error(`Response too large (exceeds ${MAX_RESPONSE_SIZE / (1024 * 1024)} MiB limit)`);
  }

  const arrayBuffer = await response.arrayBuffer();
  if (arrayBuffer.byteLength > MAX_RESPONSE_SIZE) {
    throw new Error(`Response too large (exceeds ${MAX_RESPONSE_SIZE / (1024 * 1024)} MiB limit)`);
  }

  const contentType = response.headers.get("content-type") || "";
  const mime = contentType.split(";")[0]?.trim().toLowerCase() || "";

  // --- Image → base64 data-URI attachment ---
  if (isImageMime(mime)) {
    const base64 = Buffer.from(arrayBuffer).toString("base64");
    return {
      ok: httpOk,
      httpStatus,
      url,
      format,
      title: url,
      contentType,
      contentLength: arrayBuffer.byteLength,
      output: "Image fetched successfully",
      attachments: [{ mime, dataUri: `data:${mime};base64,${base64}` }],
    };
  }

  // --- Text processing ---
  const rawContent = new TextDecoder().decode(arrayBuffer);
  const isHtml = contentType.includes("text/html");

  // Content extraction (unless --gross)
  let extracted = null;
  let workingHtml = rawContent;
  let outputLength = arrayBuffer.byteLength;

  if (!gross && isHtml) {
    extracted = extractContent(rawContent, url);
    if (extracted) {
      workingHtml = extracted.content;
      outputLength = Buffer.byteLength(workingHtml, "utf-8");
    }
  }

  const title = extracted?.title || url;

  let output;
  switch (format) {
    case "html":
      output = isHtml ? workingHtml : rawContent;
      break;
    case "markdown":
      output = isHtml ? convertHTMLToMarkdown(workingHtml) : rawContent;
      break;
    case "text":
    default:
      if (extracted?.textContent) {
        output = extracted.textContent;
      } else {
        output = isHtml ? extractTextFromHTML(workingHtml) : rawContent;
      }
      break;
  }

  return {
    ok: httpOk,
    httpStatus,
    url,
    format,
    title,
    contentType,
    contentLength: outputLength,
    output,
  };
}

// ---------------------------------------------------------------------------
// Main entry point
// ---------------------------------------------------------------------------

async function main() {
  const args = parseArgs();

  if (args.help) {
    showHelp();
    process.exit(0);
  }

  const { url, format, timeout } = args;

  if (!url) {
    console.log(JSON.stringify({ ok: false, url: "", error: "URL is required. Use -h for help." }));
    process.exit(1);
  }

  if (!url.startsWith("http://") && !url.startsWith("https://")) {
    console.log(JSON.stringify({ ok: false, url, error: "URL must start with http:// or https://" }));
    process.exit(1);
  }

  if (!VALID_FORMATS.includes(format)) {
    console.log(
      JSON.stringify({
        ok: false,
        url,
        error: `Invalid format: "${format}". Must be one of: ${VALID_FORMATS.join(", ")}`,
      }),
    );
    process.exit(1);
  }

  if (isNaN(timeout) || timeout <= 0 || timeout > MAX_TIMEOUT) {
    console.log(
      JSON.stringify({
        ok: false,
        url,
        error: `Invalid timeout: ${timeout}. Must be between 1 and ${MAX_TIMEOUT} seconds.`,
      }),
    );
    process.exit(1);
  }

  try {
    const result = await fetchUrl(url, format, timeout, args.gross);
    console.log(JSON.stringify(result));
  } catch (e) {
    console.log(JSON.stringify({ ok: false, url, error: e.message }));
    process.exit(1);
  }
}

main();
