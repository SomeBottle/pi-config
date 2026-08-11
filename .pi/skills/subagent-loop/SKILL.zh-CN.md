---
name: subagent-loop
description: Reusable subagent loop. Use only when explicitly requested by the user.
---

# Subagent Loop

启动一个或多个 Subagent 并轮询等待其输出，直到 Subagent 完成或超时。

* `{SD}` is the directory containing this SKILL.md.

## 主流程（由主 Agent 执行）

1. 同一 group 内，name **不能与 running / stuck 状态的 agent 重名**，从 **STEP-0** 开始。
2. 必须在 STEP 和 STEP 之间流转，**只允许执行** `loop.sh` 脚本且**不允许读取该脚本**内容。
3. 当**用户明确说明要终止或者尝试启动另一个 group 的 sub-agents 时**，直接跳到 **STEP-2**。

### STEP-0 INIT

```bash
# <group> 为组名 (kebab-case)
# <name> 为 sub-agent 名 (kebab-case)
# <timeout-s> 为 sub-agent 执行超时时间 (秒)
# [pi-opts...] 为 pi 选项，仅需要时或用户指定时使用:  
#   --model <pattern> 指定模型，可用 pi --list-models 查看可用模型
#   --thinking <off|minimal|low|medium|high|xhigh|max> 指定思考级别
bash {SD}/scripts/loop.sh init <group> <name> <timeout-s> [pi-opts...] <<'EOF'
<sub-agent 指示提示词>
EOF
```
要在一组中启动多个 sub-agents, 可以保持 <group> 不变，用不同 <name> 重复执行该命令 。  
然后进入 **STEP-1**。

### STEP-1 POLL

```bash
# <group> 为要查询的组
bash {SD}/scripts/loop.sh poll <group>
# 如果输出 poll later, 就稍后再轮询
# 否则会每行输出一个 agent 状态，格式为 <name>: <status>
#     status = running | finished | stuck | timeout | dead
```
#### sub-agent 状态
* timeout | dead -> 可使用相同的 <group>,<name> 重新 init
* stuck -> 告知用户可能阻塞，让用户介入
* finished -> 通过下方命令获取 sub-agent 报告:
    ```bash
    bash {SD}/scripts/loop.sh get <group> <name>
    ```

#### 下一步
* 存在 (running | stuck) -> 再执行一次 **STEP-1**。
  * **主 Agent** 可以继续执行**不依赖 sub-agents 结果的任务**（即不需要其 report 或状态即可推进的任务），但执行期间需在工具调用中**穿插执行 STEP-1** 轮询。
* 全部都是终态 (finished | timeout | dead) 且 **timeout | dead 已经重试过** -> **STEP-2**。
  * 如果存在 timeout 的 sub-agent，请通知用户。

### STEP-2 CLEAN

**重要**: 清理后 sub-agents 报告将无法再次 get。

```bash
# 清理 sub-agent，包括在运行的。如果不带 <name> 会直接清理整个组
bash {SD}/scripts/loop.sh clean <group> [<name>]
```
本步会清理后台会话和文件，生命周期**最后必须执行这一步**。
