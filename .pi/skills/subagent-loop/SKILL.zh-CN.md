---
name: subagent-loop
description: Reusable subagent loop. Use only when explicitly requested by the user.  
---

# Subagent Loop

启动一个 Subagent 并轮询等待其输出，直到 Subagent 完成或超时。

* `{SD}` is the directory containing this SKILL.md.

## 主流程（由主 Agent 执行）

1. 从 **STEP-0** 开始。
2. 必须在 STEP 和 STEP 之间流转，**只允许执行** `loop.sh` 脚本且**不允许读取该脚本**内容。
3. 当**用户明确说明要终止或者尝试执行其他任务时**，直接跳到 **STEP-2**。

### STEP-0 INIT

```bash
# <name> 为 sub-agent 名
# <timeout-s> 为 sub-agent 执行超时时间 (秒)
# [pi-opts...] 为 pi 选项，仅需要时或用户指定时使用:  
#   --model <pattern> 指定模型，可用 pi --list-models 查看可用模型
#   --thinking <off|minimal|low|medium|high|xhigh|max> 指定思考级别
bash {SD}/scripts/loop.sh init <name> <timeout-s> [pi-opts...] <<'EOF'
<sub-agent 指示提示词>
EOF
# 输出 session, tmp, poll
```

* poll=true -> 进入 **STEP-1**
* poll=false -> 进入 **STEP-2**

### STEP-1 POLL

```bash
# <sleep-s> 为轮询间隔时间（秒），15-60
# <session>, <tmp> 填入 STEP-0 中获得的值
bash {SD}/scripts/loop.sh poll <sleep-s> <session> <tmp>
# 输出 running | finished | timeout
```

* running -> 再执行一次 **STEP-1**
* finished -> 进入 **STEP-2**
* timeout -> sub-agent 超时，进入 **STEP-2**

### STEP-2 END

```bash
# <session>, <tmp> 填入 STEP-0 中获得的值
bash {SD}/scripts/loop.sh end <session> <tmp> 
# 输出报告（如果有）和 sub-agent 会话文件路径
```

本步会清理后台会话和文件，生命周期**最后必须执行这一步**。

如果是超时终止（通常没有报告），需要告知用户。
