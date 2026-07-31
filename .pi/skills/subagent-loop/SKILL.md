---
name: subagent-loop
description: Reusable subagent loop. Use only when explicitly requested by the user.
---

# Subagent Loop

Start a subagent and poll for its output until it completes or timeout is reached.

## Placeholders

* `{TMP_DIR}` - Available temporary directory
* `{NAME}` - Subagent name
* `{MESSAGE}` - Initial message for the subagent
* `{TIMEOUT_S}` - Subagent execution timeout, in seconds

Choose appropriate values if the user does not provide them.

## Main Flow (run by the main agent)

1. The Shell commands below may require escaping or other handling when expanding placeholders. The IF/ELSE branches in comments **must be selected and executed based on the situation**, not converted into Shell conditionals.  
2. Start from **STEP-0**.
3. When the **user explicitly asks to stop or attempts to start other tasks**, go directly to STEP-4.  

## STEP-0

```bash
# Define placeholders
{SESSION_NAME}=subagent-{NAME}-$(date +%s)
{SESSION_PATH}="{TMP_DIR}/{SESSION_NAME}.jsonl"
{OUTPUT_PATH}="{TMP_DIR}/{SESSION_NAME}.o.md"
{START_TIME_PATH}="{TMP_DIR}/{SESSION_NAME}.start"

# Example Pi launch command
{PI_COMMAND}="pi --session {SESSION_PATH} --append-system-prompt 'You must write final report to {OUTPUT_PATH}.' '{MESSAGE}'"
# Common options before {MESSAGE}, only use if needed or explicitly specified:
# --model <pattern> selects a model; use pi --list-models to view available models
# --thinking <off|minimal|low|medium|high|xhigh|max> sets the reasoning level
# --print prints the result and exits; see the STEP-1 below

(Go to STEP-1)
```

### STEP-1

```bash
# IF [ tmux or psmux is available ]:
tmux new-session -d -s {SESSION_NAME} {PI_COMMAND}
(Go to STEP-2)
# ELIF [ GNU Screen is available ]:
screen -dmS {SESSION_NAME} {PI_COMMAND}
(Go to STEP-2)
# ELSE:
(Add --print to {PI_COMMAND} and run it; this blocks until the subagent completes)
(Go to STEP-4)
# FI
date +%s > {START_TIME_PATH}
```

### STEP-2

Set the wait time based on subagent efficiency, within [5, 60] seconds.

```bash
sleep 5s
(Go to STEP-3)
```

### STEP-3

```bash
(( $(date +%s) - $(cat {START_TIME_PATH}) > {TIMEOUT_S} )) && echo "timeout"
# IF [ output is timeout ]:
(Go to STEP-4 due to timeout)
# FI

test -f {OUTPUT_PATH} && echo "ok"
# IF [ output is ok ]:
echo 'Subagent report path: {OUTPUT_PATH}'
(Go to STEP-4)
# ELSE:
tail -n 5 {SESSION_PATH}
(Go to STEP-2)
# FI
```

If the last few log lines are insufficient, run `tail` again with a larger `-n` value.

### STEP-4

Reach this step when `{OUTPUT_PATH}` exists or **the user explicitly stops the process** or **a timeout occurs**.

```bash
cat {OUTPUT_PATH} 2>/dev/null
# IF [ tmux or psmux is available ]:
tmux kill-session -t {SESSION_NAME}
# ELIF [ GNU Screen is available ]:
screen -S {SESSION_NAME} -X quit
# FI
```

Inform the user if the flow ends due to a timeout.
