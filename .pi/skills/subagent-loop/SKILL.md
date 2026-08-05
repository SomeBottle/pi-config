---
name: subagent-loop
description: Reusable subagent loop. Use only when explicitly requested by the user.
---

# Subagent Loop

Start a subagent and poll for its output until it completes or times out.

* `{SD}` is the directory containing this SKILL.md.

## Main Flow (run by the main agent)

1. Start from **STEP-0**.
2. You must transition from one STEP to another. **Only the `loop.sh` script may be executed, and reading its contents is not allowed**.
3. When the **user explicitly asks to stop or attempts to start other tasks**, go directly to **STEP-2**.

### STEP-0 INIT

```bash
# <name> - subagent name
# <timeout-s> - subagent execution timeout (seconds)
# [pi-opts...] - pi options, use only when needed or explicitly specified:
#   --model <pattern> selects a model; use pi --list-models to view available models
#   --thinking <off|minimal|low|medium|high|xhigh|max> sets the reasoning level
bash {SD}/scripts/loop.sh init <name> <timeout-s> [pi-opts...] <<'EOF'
<subagent instructions prompt>
EOF
# Output: session, tmp, poll
```

* poll=true -> go **STEP-1**
* poll=false -> go **STEP-2**

### STEP-1 POLL

```bash
# <sleep-s> - polling interval (seconds), 15-60
# <session>, <tmp> - the values obtained in STEP-0
bash {SD}/scripts/loop.sh poll <sleep-s> <session> <tmp>
# Output: running | finished | timeout
```

* running -> run **STEP-1** again
* finished -> go **STEP-2**
* timeout -> subagent timed out, go **STEP-2**

### STEP-2 END

```bash
# <session>, <tmp> - the values obtained in STEP-0
bash {SD}/scripts/loop.sh end <session> <tmp>
# Output: the report (if exists) and the sub-agent session file path
```

This step cleans up the background session and its files; **this step must be executed at the end of the lifecycle**.

If the flow ended due to a timeout (usually no report), inform the user.
