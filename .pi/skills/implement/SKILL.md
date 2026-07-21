---
name: implement
description: "Implement a piece of work based on a spec or set of tickets."
disable-model-invocation: true
---

Implement the work described by the user in the spec or tickets.

## Locate the work

Specs and tickets live under `docs/mattpocock/features/<feature-slug>/`.

To find the next ticket to implement, scan `docs/mattpocock/features/<feature-slug>/tickets/` for the first ticket whose `status` is `todo` and whose `blocked_by` entries all resolve to tickets with `status: done`. If the user names a specific ticket, use that one directly.

## Implementation loop

Use /tdd where possible, at pre-agreed seams.

Run typechecking regularly, single test files regularly, and the full test suite once at the end.

## On completion

1. Update the ticket's frontmatter `status` to `done`.
2. Check off all completed acceptance criteria: `- [ ]` → `- [x]`.
3. If all tickets in the feature are `done`, update the spec's frontmatter `status` to `done`.
4. Use /code-review to review the work.
5. Commit your work to the current branch.
