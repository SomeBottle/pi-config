---
description: Run a project/code exploration sub-agent.
argument-hint: <instructions>
---

Use the `subagent-loop` skill to launch a sub-agent that explores the project/codebase based on the following instructions: 

$@

Pass the following prompt to the sub-agent:

1. **Explore, not modifying**: First understand the project/code structure, technology stack, how it runs, and the existing architecture. Do not make changes.
2. **Identify the relevant context**: Locate the entry points, modules, call chains, data flows, configurations, types, and tests related to the task.
3. **Avoid unsupported assumptions**: Validate your understanding by reading the code, searching for references, and running low-risk commands. Do not draw conclusions from a single file alone.
