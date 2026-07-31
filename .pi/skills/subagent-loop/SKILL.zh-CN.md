---
name: subagent-loop
description: Reusable subagent loop. Use only when explicitly requested by the user.  
---

# Subagent Loop

启动一个 Subagent 并轮询等待其输出，直到 Subagent 完成或超时。

## 占位符

* `{TMP_DIR}` - 可用的临时文件目录
* `{NAME}` - Subagent 名
* `{MESSAGE}` - Subagent 初始消息
* `{TIMEOUT_S}` - Subagent 执行超时时间 (秒)

如用户未定义，你自行决定。

## 主流程（由主 Agent 执行）

1. 下方所有 Shell 命令在展开占位符的时候可能需要进行转义等处理来确保顺利执行。注释写的 IF ELSE 条件分支**需要你自己根据情况选择命令执行**，而不是转换为 Shell 的条件分支语句。
2. 从 **STEP-0** 开始。  
3. 当**用户明确说明要终止或者尝试执行其他任务时**，直接跳到 STEP-4。  

## STEP-0

```bash
# 定义占位符
{SESSION_NAME}=subagent-{NAME}-$(date +%s)
{SESSION_PATH}="{TMP_DIR}/{SESSION_NAME}.jsonl"
{OUTPUT_PATH}="{TMP_DIR}/{SESSION_NAME}.o.md"
{START_TIME_PATH}="{TMP_DIR}/{SESSION_NAME}.start"

# 示例 Pi 实例启动命令
{PI_COMMAND}="pi --session {SESSION_PATH} --append-system-prompt 'You must write final report to {OUTPUT_PATH}.' '{MESSAGE}'"
# {MESSAGE} 之前还有这些常用参数，仅在必要或者显式指定时使用: 
# --model <pattern> 指定模型，可用 pi --list-models 查看可用模型
# --thinking <off|minimal|low|medium|high|xhigh|max> 指定思考级别
# --print 打印结果然后退出，见下方 STEP-1

(进入 STEP-1)
```

### STEP-1

```bash
# IF [ 有 tmux 或者 psmux ]: 
tmux new-session -d -s {SESSION_NAME} {PI_COMMAND}
(进入 STEP-2)
# ELIF [ 有 GNU Screen ]: 
screen -dmS {SESSION_NAME} {PI_COMMAND}
(进入 STEP-2)
# ELSE:
(在 {PI_COMMAND} 的基础上加上 --print 参数后执行，会阻塞直至 subagent 完成)
(进入 STEP-4)
# FI
date +%s > {START_TIME_PATH}
```

### STEP-2

根据 subagent 执行速度自行设定等待时间，时间范围 [5, 60] 秒。  

```bash
sleep 5s
(进入 STEP-3)
```

### STEP-3

```bash
(( $(date +%s) - $(cat {START_TIME_PATH}) > {TIMEOUT_S} )) && echo "timeout"
# IF [ 输出 timeout ]:
(进入 STEP-4, 因超时)
# FI

test -f {OUTPUT_PATH} && echo "ok"
# IF [ 输出 OK ]: 
echo 'Subagent report path: {OUTPUT_PATH}'
(进入 STEP-4)
# ELSE:
tail -n 5 {SESSION_PATH}
(进入 STEP-2)
# FI
```

查看 subagent 末几行日志时如果信息不够，可以多调用几次 tail，调整 -n 查看更多行。  

### STEP-4

当文件 `{OUTPUT_PATH}` 存在或者**用户显式终止时**或者超时时到达这一步。  

```bash
cat {OUTPUT_PATH} 2>/dev/null
# IF [ 有 tmux 或者 psmux ]:
tmux kill-session -t {SESSION_NAME}
# ELIF [ 有 GNU Screen ]:
screen -S {SESSION_NAME} -X quit
# FI
```

如果是超时终止，需要告知用户。