---
description: Make plan artifacts according to the context.
argument-hint: <instructions>
---

Make a plan for the task based on the instructions, incorporating all important information from the context.

Instructions: $@

## Output

Write a `<task-name>.plan.md` file (kebab-case task name) containing exactly these sections:

- **## Goal** — One or two sentences stating what we're trying to achieve.
- **## Decisions & Necessary Context** — Already-decided points and facts needed to proceed (stack, conventions, constraints, relevant links). Do not invent missing decisions or facts.
- **## Todos** — Actionable checklist in execution order, every item written as `- [ ]`.
- **## CurrentStep** — What to work on right now (the next unchecked todo). 

Keep it concise and concrete. Ask clarifying questions only if an ambiguity materially affects the plan or prevents a reliable plan from being made.

Also include this line at the end of the plan file, so the executor sees it:

> When executing this plan, keep **Todos** and **CurrentStep** up to date: check off completed items, move **CurrentStep** to the next unfinished todo, and set it to `Done` when the plan is complete.
