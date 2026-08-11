---
name: subagent-loop
description: Reusable subagent loop. Use only when explicitly requested by the user.
---

# Subagent Loop

Start one or more subagents and poll for their output until they complete or time out.

* `{SD}` is the directory containing this SKILL.md.

## Main Flow (run by the main agent)

1. Within the same group, a name **must not collide with an agent in the `running` / `stuck` state**; start from **STEP-0**.
2. You must transition from one STEP to another. **Only the `loop.sh` script may be executed, and reading its contents is not allowed**.
3. When the **user explicitly asks to stop, or attempts to start sub-agents in another group**, go directly to **STEP-2**.

### STEP-0 INIT

```bash
# <group> - group name (kebab-case)
# <name> - subagent name (kebab-case)
# <timeout-s> - subagent execution timeout (seconds)
# [pi-opts...] - pi options, use only when needed or explicitly specified:
#   --model <pattern> selects a model; use pi --list-models to view available models
#   --thinking <off|minimal|low|medium|high|xhigh|max> sets the reasoning level
bash {SD}/scripts/loop.sh init <group> <name> <timeout-s> [pi-opts...] <<'EOF'
<subagent instructions prompt>
EOF
```
To launch multiple subagents in one group, keep `<group>` unchanged and repeat this command with different `<name>`s.  
Then go to **STEP-1**.

### STEP-1 POLL

```bash
# <group> - the group to query
bash {SD}/scripts/loop.sh poll <group>
# If the output is "poll later", poll again after a while
# Otherwise it prints one agent status per line, in the form <name>: <status>
#     status = running | finished | stuck | timeout | dead
```
#### Subagent states
* timeout | dead -> may re-init with the same <group>,<name>
* stuck -> inform the user it may be blocked, let the user intervene
* finished -> fetch the subagent report with:
    ```bash
    bash {SD}/scripts/loop.sh get <group> <name>
    ```

#### Next
* ANY (running | stuck) -> run **STEP-1** again.
  * The **main agent** may continue tasks that **do not depend on the subagents' results** (i.e., tasks that can proceed without their report or status), but must **interleave STEP-1 polls** among its tool calls.
* ALL (finished | timeout | dead) and **timeout | dead have already been retried** -> **STEP-2**.
  * If any subagent timed out, inform the user.

### STEP-2 CLEAN

**IMPORTANT**: after cleaning, subagent reports can no longer be fetched with `get`.

```bash
# Clean up subagents, including running ones. Without <name>, the whole group is cleaned
bash {SD}/scripts/loop.sh clean <group> [<name>]
```
This step cleans up the background sessions and files; **it must be executed at the end of the lifecycle**.
