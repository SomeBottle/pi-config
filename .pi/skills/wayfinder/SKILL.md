---
name: wayfinder
description: Plan a huge chunk of work — more than one agent session can hold — as a shared map of decision tickets in local markdown files, and resolve them one at a time until the way to the destination is clear.
disable-model-invocation: true
---

A loose idea has arrived — too big for one agent session, and wrapped in fog: the way from here to the **destination** isn't visible yet. Wayfinding is about finding that way, not charging at the destination. This skill charts the way as a **shared map** of local markdown files, then works its **decision tickets** — questions whose resolution is a decision, not slices of a build to execute — one at a time until the route is clear.

The destination varies per effort, and naming it is the first act of charting — it shapes every ticket. It might be a spec to hand off and iterate on, a decision to lock before planning starts, or a change made in place like a data-structure migration. The map is domain-agnostic — engineering work, course content, whatever fits the shape.

## Plan, don't do

Wayfinder is **planning** by default: each ticket resolves a decision, and the map is done when the way is clear — nothing left to decide before someone goes and does the thing. The pull to just do the work is usually the signal you've reached the edge of the map and it's time to hand off — when the destination is a spec, that handoff runs through `to-spec` → `to-tickets` → `implement`. An effort can override this in its **Notes** — carrying execution into the map itself — but absent that, produce decisions, not deliverables.

## Refer by name

Every map and ticket has a **name** — its title. In everything the human reads — narration, the map's Decisions-so-far — refer to it by that name, never by a bare number or slug. A wall of `01-…, 02-…` is illegible; names read at a glance. The `NN` number and repo-root-relative path don't vanish — a name wraps its link — but they ride _inside_ the name, never stand in for it.

## The Map

The map is a single markdown file — `docs/mattpocock/features/<feature-slug>/map.md` — the canonical artifact. Its tickets live beside it in `docs/mattpocock/features/<feature-slug>/wayfinding/`, one file per ticket, numbered from `01` in dependency order: `<NN>-<name>.md`. Paths are identities — no labels, no tracker. These are deliberate siblings of the build convention (`spec.md` + `tickets/`): `wayfinding/` holds decisions, `tickets/` holds build slices, and the two never mix.

The map is an **index**, not a store. It lists the decisions made and points at the tickets that hold their detail; a decision lives in exactly one place — its ticket — so the map never restates it, only gists it and links.

The **frontier** — the open, unblocked, unclaimed tickets — is found by scanning `wayfinding/`, never by reading the map: a ticket is takeable when its `status` is `todo` and every path in its `blocked_by` points at a ticket whose `status` is `done` (see [Tickets](#tickets)). Open tickets are deliberately **not** listed on the map; the scan is the query.

### The map body

The whole map at low resolution, loaded once per session. Open tickets are **not** listed — they are found by the frontier scan.

```markdown
---
status: in-progress
---

## Destination

<what reaching the end of this map looks like — the spec, decision, or change this effort is finding its way to. One or two lines; every session orients to it before choosing a ticket.>

## Notes

<domain; skills every session should consult; standing preferences for this effort>

## Decisions so far

<!-- the index — one line per resolved ticket: enough to judge relevance, then zoom the link for the detail the ticket holds -->

- [<ticket title>](docs/mattpocock/features/<feature-slug>/wayfinding/<NN>-<name>.md) — <one-line gist of the answer>

## Not yet specified

<!-- see "Fog of war": in-scope fog you can't ticket yet; graduates as the frontier advances -->

## Out of scope

<!-- see "Out of scope": work ruled beyond the destination; closed, never graduates -->
```

The map's `status` starts `in-progress` and flips to `done` when the frontier is empty and nothing is left to graduate from **Not yet specified** — the way is charted and the effort is ready to hand off.

### Tickets

Each ticket is a file in `wayfinding/`; its path is its identity. Its body is the question, sized to one 100K token agent session:

```markdown
---
status: todo
type: grilling
blocked_by:
  - docs/mattpocock/features/<feature-slug>/wayfinding/<NN>-<name>.md
---

# <NN> — <Ticket title>

## Question

<the decision or investigation this ticket resolves>
```

`type` is one of `research`, `prototype`, `grilling`, `task` — see [Ticket Types](#ticket-types). `blocked_by` lists repo-root-relative paths to blocking tickets; if there are none, use `blocked_by: ["None — can start immediately"]`.

A session **claims** a ticket by flipping its `status` to `in-progress` **first**, before any work, so concurrent sessions skip it. That flip _is_ the claim: a `todo` ticket is unclaimed.

A ticket is **unblocked** when every ticket in its `blocked_by` is `status: done`; the **frontier** is the open (`todo`), unblocked, unclaimed tickets — the edge of the known.

The answer isn't part of the body — it's recorded on resolution (see [Work through the map](#work-through-the-map)). Assets created while resolving a ticket are linked from the ticket, not pasted in.

## Ticket Types

Every ticket is either **HITL** — human in the loop, worked _with_ a human who speaks for themselves — or **AFK**, driven by the agent alone. A HITL ticket only resolves through that live exchange; the agent never stands in for the human's side of it (a grilling agent that answers its own questions has broken this).

- **Research** (AFK): Reading documentation, third-party APIs, or local resources like knowledge bases to surface a fact a decision waits on. Resolved by a `/research` **subagent**. Use when knowledge outside the current working directory is required.
- **Prototype** (HITL): Raise the fidelity of the discussion by making a cheap, rough, concrete artifact to react to — an outline, a rough take, a stub, or UI/logic code via the /prototype skill. Links the prototype as an asset. Use when "how should it look" or "how should it behave" is the key question.
- **Grilling** (HITL): Conversation. The default case. Always invoke the /grilling and /domain-modeling skills.
- **Task** (HITL or AFK): Manual work that must happen before a _decision_ can be made — nothing to decide, prototype, or research, but the discussion is blocked until it's done. Signing up for a service so its API can be judged, provisioning access, moving data so its shape can be seen. This is the one type that _does_ rather than decides — and it earns its place by unblocking a decision, not by delivering the destination. The agent drives it alone where it can (AFK); otherwise it hands the human a precise checklist (HITL). Resolved when the work is done; the answer records what was done and any resulting facts (credentials location, new URLs, row counts) later tickets depend on.

## Fog of war

The map is _deliberately_ incomplete: don't chart what you can't yet see. Beyond the live tickets lies the **fog of war** — the dim view of decisions and investigations you can tell are coming but can't yet pin down, because they hang on questions still open. Resolving a ticket clears the fog ahead of it, graduating whatever's now specifiable into fresh tickets — one at a time, until the way to the destination is clear and no tickets remain.

The map's **Not yet specified** section is where that dim view is written down: the suspected question, the area to revisit later. It's the undiscovered frontier _toward_ the destination — everything here is in scope, just not sharp enough to ticket. Write as loosely or as fully as the view allows; it doubles as a signpost for collaborators reading where the effort is headed.

**Fog or ticket?** The test is whether you can state the question precisely now — _not_ whether you can answer it now.

- **Ticket when** the question is already sharp — even if it's blocked and you can't act on it yet.
- **Not yet specified when** you can't yet phrase it that sharply. Don't pre-slice the fog into ticket-sized pieces: it's coarser than a ticket, and one patch may graduate into several tickets, or none, once the frontier reaches it.

**Not yet specified** excludes what's already decided (Decisions so far), what's already a live ticket, and what's out of scope (the next section).

## Out of scope

Fog only ever gathers _toward_ the destination. The destination fixes the scope, so work beyond it is **out of scope** — it isn't fog, and it doesn't belong in **Not yet specified**. It gets its own **Out of scope** section on the map: work you've consciously ruled out of _this_ effort. Scope, not sharpness, lands it here.

Out-of-scope work never graduates — the frontier stops at the destination — so it returns only if the destination is redrawn, and then as a fresh effort, not a resumption.

Ruling something out of scope is a scoping act, not a step on the route. When a ticket that already exists turns out to sit past the destination — mis-scoped in while charting, or exposed by a resolution — **close it**: flip its `status` to `out-of-scope` (anything but `todo` is unambiguously off the frontier) and leave one line in the **Out of scope** section: the gist plus why it's out of scope, linking the closed ticket. It stays out of **Decisions so far**, which records the route actually walked — a scope boundary isn't a step on it.

## Invocation

Two modes. Either way, **never resolve more than one ticket per session** — with the exception of research tickets.

### Chart the map

User invokes with a loose idea.

1. **Name the destination.** Run a `/grilling` and `/domain-modeling` session to pin down what this map is finding its way to — the spec, decision, or change. The destination fixes the scope, so it's settled first.
2. **Map the frontier.** Grill again, **breadth-first** this time: fan out across the whole space rather than deep on any one thread, surfacing the open decisions and the first steps takeable now. **If this surfaces no fog** — the way to the destination is already clear, the whole journey small enough for one session — you don't need a map. Stop and ask the user how they'd like to proceed.
3. **Create the map** at `docs/mattpocock/features/<feature-slug>/map.md` (`status: in-progress`): Destination and Notes filled in, Decisions-so-far empty, the fog sketched into **Not yet specified**.
4. **Create the tickets you can specify now** as files under `wayfinding/` — numbered from `01` in dependency order, `blocked_by` written in the **same pass** (paths are known at creation, unlike tracker ids). Everything you can't yet specify stays in the fog — the **Not yet specified** section.
5. **Fire the research subagents.** For each `research` ticket you just created, spin up a `/research` subagent to resolve it in parallel, capturing its findings on a throwaway `research/<name>` branch (local git, no need to push) with a context pointer from the ticket; the findings become the ticket's `## Resolution`, and the ticket flips to `status: done`.
6. Stop — charting is one session's work; it hand-resolves nothing (research tickets excepted).

### Work through the map

User invokes with a map (path or slug). A ticket is **optional** — without one, you pick the next decision, not the user.

1. Load the **map** — the low-res view, not every ticket body. Re-read it and re-scan `wayfinding/` fresh: other sessions may be editing the same files.
2. Choose the ticket. If the user named one, use it. Otherwise take the first frontier ticket in order. **Claim it**: flip its `status` to `in-progress` before any work.
3. Resolve it — **zoom as needed**: fetch the full body of any related or resolved ticket on demand; invoke the skills the `## Notes` block names. If in doubt, use `/grilling` and `/domain-modeling`.
4. Record the resolution: append a `## Resolution` section to the ticket — the answer, with links to any assets — flip `status` to `done`, and **append a context pointer** to the map's Decisions-so-far: one line, title and path, one-line gist.
5. Add newly-surfaced tickets (numbering and `blocked_by` in the same pass); graduate any fog the answer has made specifiable, clearing each graduated patch from **Not yet specified** so it lives only as its new ticket. If the answer reveals a ticket — this one or another — sits beyond the destination, **rule it out of scope** (`status: out-of-scope`) rather than resolving it on the route. If the decision invalidates other parts of the map, update or delete those tickets.
6. When the frontier is empty and nothing is left to graduate from **Not yet specified**, flip the map's `status` to `done` — the way is charted; hand off (to-spec first if the destination is a spec).

The user may run unblocked tickets in parallel, so expect other sessions to be editing the same files concurrently — re-read before you write, and let `status: in-progress` be the claim.
