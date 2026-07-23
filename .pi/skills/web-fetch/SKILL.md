---
name: web-fetch
description: Supports fetching web content by sending requests directly from the local environment. Given a URL, it can return the page content as Markdown, plain text, or HTML. Prefer this skill when content needs to be retrieved directly from a URL, it is not suitable for pages that require JavaScript rendering.
---

# Web Fetch Skill

{SD} is the directory containing this SKILL.md.

## Fetch simplified URL page content

```bash
# The following commands return simplified page content with boilerplate removed
node {SD}/scripts/web-fetch.js <URL>                         # default Markdown output
node {SD}/scripts/web-fetch.js --format text <URL>            # plain text output
node {SD}/scripts/web-fetch.js --format html <URL>            # raw HTML output
node {SD}/scripts/web-fetch.js --format markdown --timeout 10 <URL>  # configurable timeout in seconds
```

## Fetch raw URL page content

```bash
node {SD}/scripts/web-fetch.js --gross <URL>  # use --gross to get the raw, unprocessed page
```

## Help

Run with `-h` to see all options:

```bash
node {SD}/scripts/web-fetch.js -h
```

## Limitations

Some pages rely on JavaScript rendering and web-fetch may not be able to fetch them correctly. For such pages, use other skills to retrieve the content.