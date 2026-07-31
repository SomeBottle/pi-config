---
description: Make plan artifacts according to the context.
argument-hint: <instructions>
---

Make a plan for the following task:

$@

## Output

Write a `<task-name>.plan.md` file (kebab-case task name) containing exactly these sections:

- **## Goal** — One or two sentences stating what we're trying to achieve.
- **## Consensus & Necessary Contexts** — Already-decided points and facts needed to proceed (stack, conventions, constraints, relevant links).
- **## Todos** — Actionable checklist, every item written as `- [ ]`.
- **## CurrentStep** — What to work on right now (the next unchecked todo).

Keep it concise and concrete. Ask clarifying questions if the task is genuinely ambiguous.

Also include this line at the end of the plan file, so the executor sees it:

> When execution begins from this plan, keep updating **Todos** and **CurrentStep** as you go (check off finished items, move the pointer forward).
