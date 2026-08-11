#!/bin/bash
set -euo pipefail

# ============================================================================
# subagent-loop: 可复用的多 agent 并发轮询脚本
# ----------------------------------------------------------------------------
# 命令:
#   init <group> <name> <timeout-s> [pi-opts...]
#       stdin:  子 agent 的指令 prompt
#       stdout: method: <tmux|psmux|screen|naive>
#               id:     <tmux/psmux/screen 会话名 | naive 的 pi pid>
#   poll <group>
#       stdout: <name>: <status>   (组内全部 agent, 按启动时间排序)
#               status = running | finished | stuck | timeout | dead
#       或:     poll later         (距上次 poll/init 不足 POLL_MIN 秒)
#   get <group> <name>
#       stdout: <name>.report.md 的完整内容 (不存在则 stderr 报错, exit 1)
#   clean <group> [<name>]
#       清理指定 agent 的会话/进程并删除其全部文件 (无 <name> 则清理整个 group 并删除组目录)
#       stdout: 'cleaned: <name>' (整组清理最后输出 'cleaned group: <group>')
#
# 状态存储 (目录下的文件只有 clean 会删除; poll/init 的自动清理只动会话/进程):
#   ${TMPDIR:-${TEMP:-${TMP:-/tmp}}}/subagent-loop-<group>/
#       <name>.state      agent 状态, 固定七行:
#                         1. <starttime>   启动时刻 (epoch 秒)
#                         2. <id>          tmux/psmux/screen 会话名 或 naive 的 pi pid
#                         3. <launchmethod> tmux | psmux | screen | naive
#                         4. <timeout-s>   超时秒数 (init 传入)
#                         5. <status>      running | finished | stuck | timeout | dead
#                         6. <stallcnt>    jsonl 最后一行连续未变化的轮数
#                         7. <lastline>    上次记录的 jsonl 最后一行 (stall 检测用)
#       <name>.jsonl      pi 的会话记录 (--session 指定), stall 检测的数据源
#       <name>.report.md  子 agent 被要求写入的最终报告
#       lastpoll.time     组级最近一次 init/poll 的时间戳 (epoch 秒)
#
# poll 状态机 (每次按此顺序判定, 报告优先避免误杀刚写完报告的 agent):
#   1. 报告已写出       -> finished (顺手清理会话/进程)
#   2. 墙钟超过 timeout -> timeout  (kill 会话/进程)
#   3. 进程消失且无报告 -> dead     (崩溃/被外部杀掉)
#   4. jsonl 最后一行连续 STALL_LIMIT 轮不变 -> stuck (有进展则回退 running)
#   5. 否则             -> running
# 注意: finished/timeout/dead 是终态, 后续 poll 不再改写 state、不再重复清理;
#       poll 自动清理只动会话/进程, 绝不动目录里的文件; clean 是删除文件的唯一入口。
#       init 允许同组同名重新创建 agent, 前提是旧 agent 处于终态 (状态损坏视为 dead);
#       重新 init 会先清掉旧 agent 的残留会话/进程和旧 report/jsonl。
#       已知限制: init 的检查-写入非原子, 并发 init 同名 agent 存在竞态, 假定单调用方。
# ============================================================================

# 轮询最小间隔 (秒): init 和每次成功 poll 都会刷新 lastpoll.time,
# 距上次不足 POLL_MIN 秒时 poll 直接输出 "poll later" (exit 0)
POLL_MIN=30

# 连续 STALL_LIMIT 轮 jsonl 最后一行未变化, 判定为 stuck
STALL_LIMIT=5

usage() {
    cat >&2 <<EOF
usage: $0 <cmd>
  init <group> <name> <timeout-s> [pi-opts...]  stdin: PROMPT | stdout: 'method: X' 'id: Y'
  poll <group>                                  stdout: '<name>: <status>' for all agents | 'poll later (${POLL_MIN}s)'
  get <group> <name>                            stdout: report content
  clean <group> [<name>]                        stdout: 'cleaned: <name>' (无 <name> 清整个 group 并删组目录)
EOF
    exit 1
}

# --- 校验 group 和 name ---
valid_name() {
    [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]
}

# --- 获取可写临时目录: TMPDIR > TEMP > TMP > /tmp ---
group_base() {
    echo "${TMPDIR:-${TEMP:-${TMP:-/tmp}}}"
}

# --- 创建并验证组目录 (仅 init 用); 不可写时提示用户设置 $TMPDIR ---
group_dir() {
    local dir="$1"
    if ! mkdir -p "$dir" 2>/dev/null; then
        echo "error: cannot create $dir; set \$TMPDIR to a writable directory and retry" >&2
        exit 1
    fi
    if ! touch "$dir/.writeprobe" 2>/dev/null; then
        echo "error: cannot write to $dir; set \$TMPDIR to a writable directory and retry" >&2
        exit 1
    fi
    rm -f "$dir/.writeprobe" || true
    echo "$dir"
}

# --- 清理 agent 的会话/进程: 只清进程, 绝不碰目录里的任何文件 ---
cleanup_agent() {
    local method="$1" id="$2"
    case $method in
        tmux)   tmux kill-session -t "$id" 2>/dev/null || true ;;
        psmux)  psmux kill-session -t "$id" 2>/dev/null || true ;;
        screen) screen -S "$id" -X quit 2>/dev/null || true ;;
        naive)  kill "$id" 2>/dev/null || true ;;
    esac
}

# --- 判断 agent 的进程是否还活着 (存活则返回 0) ---
agent_alive() {
    local method="$1" id="$2" stat
    case $method in
        tmux)   tmux has-session -t "$id" 2>/dev/null ;;
        psmux)  psmux has-session -t "$id" 2>/dev/null ;;
        screen) screen -ls 2>/dev/null | grep -Fq "$id" ;;
        naive)
            if ps -p "$$" -o stat= >/dev/null 2>&1; then
                # Linux / 支持 procps 风格 ps 的环境
                stat=$(ps -p "$id" -o stat= 2>/dev/null || true)
                # 空 = 进程已消失; Z = 僵尸进程, 都算 dead
                [[ -n $stat && $stat != *Z* ]]
            else
                # Git Bash / 精简版 ps
                kill -0 "$id" 2>/dev/null
            fi
            ;;
    esac
}

# --- 用 awk 重写 state 文件后三行 (status/stallcnt/lastline), 临时文件 + mv 原子写 ---
rewrite_state() {
    local state="$1" status="$2" stallcnt="$3" lastline="$4"
    local tmp="$state.tmp.$$"
    awk -v s="$status" -v c="$stallcnt" -v l="$lastline" '
        NR <= 4 { print; next }
        NR == 5 { print s; next }
        NR == 6 { print c; next }
        NR == 7 { print l }
    ' "$state" > "$tmp"
    mv "$tmp" "$state"
}

# --- clean 单个 agent: 清理会话/进程 (无论状态) 并删除其全部文件 ---
clean_agent() {
    local dir="$1" name="$2"
    local state_file="$dir/$name.state"
    local id method
    id=$(sed -n '2p' "$state_file")
    method=$(sed -n '3p' "$state_file")
    cleanup_agent "$method" "$id"
    # 通配删除 state 及其 rewrite_state 中断残留的 tmp 文件, 连同 jsonl/report 一并清除
    rm -f "$state_file"* "$dir/$name.jsonl" "$dir/$name.report.md"
    echo "cleaned: $name"
}

# ============================================================================
# init <group> <name> <timeout-s> [pi-opts...]
#   在 <group> 组中启动一个名为 <name> 的子 agent
#   同组同名的旧 agent 处于终态 (finished/timeout/dead) 时允许重新 init
# ============================================================================
if [[ ${1:-} == init ]]; then
    group=${2:-}
    name=${3:-}
    timeout_s=${4:-}
    if [[ -z $group || -z $name || -z $timeout_s ]]; then
        usage
    fi
    if ! valid_name "$group" || ! valid_name "$name"; then
        echo "error: <group> and <name> must match ^[A-Za-z0-9][A-Za-z0-9_-]*$" >&2
        exit 1
    fi
    if [[ ! $timeout_s =~ ^[0-9]+$ ]]; then
        echo "error: <timeout-s> must be a number" >&2
        exit 1
    fi
    # prompt 只允许从管道/重定向读取, 拒绝 TTY, 防止交互式误用
    if [[ -t 0 ]]; then
        echo "error: STDIN must be a pipe or redirection, not a TTY" >&2
        exit 1
    fi

    dir=$(group_dir "$(group_base)/subagent-loop-$group")
    state_file="$dir/$name.state"

    # 同名 agent 已存在时, 仅当其处于终态 (finished/timeout/dead) 才允许重新 init;
    # 状态行损坏/未知按 poll 的口径视为 dead 放行。重新 init 前先清掉旧 agent 的
    # 残留会话/进程和旧文件 (report/jsonl), 全新开始。
    # 已知限制: 检查-写入非原子, 并发 init 同名 agent 存在竞态, 脚本假定单调用方。
    old_status=
    if [[ -f $state_file ]]; then
        old_status=$(sed -n '5p' "$state_file")
        old_id=$(sed -n '2p' "$state_file")
        old_method=$(sed -n '3p' "$state_file")
        case $old_status in
            running|stuck)
                echo "error: agent $name already exists and is running (status: $old_status)" >&2
                exit 1
                ;;
            finished|timeout|dead) ;;
            *) old_status=dead ;;   # 状态损坏 -> 视为 dead, 放行
        esac
        cleanup_agent "$old_method" "$old_id"
        rm -f "$dir/$name.report.md" "$dir/$name.jsonl"
    fi

    # 从 STDIN 读取 prompt
    prompt=$(cat)
    starttime=$(date +%s)
    # tmux/screen 会话 id: 组+名+启动时刻; tmux 会话名是全局命名空间
    sid="subagent-$group-$name-$starttime"

    # 固定 pi 选项: 会话记录写入 <name>.jsonl; 要求子 agent 把最终报告写到 <name>.report.md
    fixed_opts=(--session "$dir/$name.jsonl" --approve --no-extensions
                --append-system-prompt "You must write final report to $dir/$name.report.md.")

    # 启动方式优先级: tmux/psmux > screen > naive
    method=
    if command -v tmux >/dev/null 2>&1; then
        method=tmux
    elif command -v psmux >/dev/null 2>&1; then
        method=psmux
    elif command -v screen >/dev/null 2>&1; then
        method=screen
    else
        method=naive
    fi

    case $method in
        tmux)
            tmux new-session -d -s "$sid" \
                pi "${fixed_opts[@]}" "${@:5}" "$prompt" \
                || launch_failed=1
            ;;
        psmux)
            psmux new-session -d -s "$sid" \
                pi "${fixed_opts[@]}" "${@:5}" "$prompt" \
                || launch_failed=1
            ;;
        screen)
            screen -dmS "$sid" \
                pi "${fixed_opts[@]}" "${@:5}" "$prompt" \
                || launch_failed=1
            ;;
        naive)
            pi "${fixed_opts[@]}" --print "${@:5}" "$prompt" \
                >/dev/null 2>&1 &
            sid=$!
            ;;
    esac

    # 写入 state 七行; 初始 status=running, stallcnt=0, lastline 空
    {
        echo "$starttime"
        echo "$sid"
        echo "$method"
        echo "$timeout_s"
        echo "running"
        echo "0"
        echo ""
    } > "$state_file"

    # 启动验证, 失败则删掉刚写的 state 文件, 不留半成品:
    # tmux/screen 看启动命令返回值; naive 看进程是否真的起来了
    if [[ ${launch_failed:-0} == 1 ]]; then
        rm -f "$state_file"
        echo "error: failed to launch $method session $sid" >&2
        exit 1
    fi
    # 如果是朴素方式，检查是否成功启动
    if [[ $method == naive ]] && ! kill -0 "$sid" 2>/dev/null; then
        sleep 0.5  # 给后台 job 一点时间完成 fork/exec, 避免误判
        if ! kill -0 "$sid" 2>/dev/null; then
            rm -f "$state_file"
            echo "error: failed to launch pi in background (check that 'pi' is on PATH)" >&2
            exit 1
        fi
    fi

    # 重新 init 场景: 告知旧 agent 已被替换 (stdout 协议不变, 提示走 stderr)
    if [[ -n $old_status ]]; then
        echo "note: replaced previous agent $name (status: $old_status)" >&2
    fi

    # init 也算一次"轮询事件", 刷新组级时间戳, 防止连续 init 后立即 poll
    date +%s > "$dir/lastpoll.time"

    echo "method: $method"
    echo "id: $sid"

# ============================================================================
# poll <group>
#   轮询组内全部 agent, 输出 "<name>: <status>" (按启动时间排序)
# ============================================================================
elif [[ ${1:-} == poll ]]; then
    group=${2:-}
    if [[ -z $group ]]; then
        usage
    fi
    if ! valid_name "$group"; then
        echo "error: <group> must match ^[A-Za-z0-9][A-Za-z0-9_-]*$" >&2
        exit 1
    fi
    dir="$(group_base)/subagent-loop-$group"
    if [[ ! -d $dir ]]; then
        echo "error: group $group not found: $dir" >&2
        exit 1
    fi

    # 节流: 距上次 init/poll 不足 POLL_MIN 秒 -> "poll later" (不算一次 poll, 不刷新时间戳)
    if [[ -f "$dir/lastpoll.time" ]]; then
        lastpoll=$(cat "$dir/lastpoll.time")
        if [[ $lastpoll =~ ^[0-9]+$ ]] && (( $(date +%s) - lastpoll < POLL_MIN )); then
            echo " poll later (${POLL_MIN}s)"
            exit 0
        fi
    fi

    # 遍历组内全部 agent 的 state 文件, 逐个判定状态
    results=()
    for f in "$dir"/*.state; do
        [[ -e $f ]] || continue
        name=${f##*/}
        name=${name%.state}

        # 读取 state 七行
        starttime=$(sed -n '1p' "$f")
        id=$(sed -n '2p' "$f")
        method=$(sed -n '3p' "$f")
        timeout_s=$(sed -n '4p' "$f")
        status=$(sed -n '5p' "$f")
        stallcnt=$(sed -n '6p' "$f")
        stored_last=$(sed -n '7p' "$f")
        # stallcnt 可能是空或非数字 (corrupt state), 统一归零
        [[ $stallcnt =~ ^[0-9]+$ ]] || stallcnt=0

        # state 损坏 (时间字段非数字) -> 无法判定, 直接标 dead 并提示
        if [[ ! $starttime =~ ^[0-9]+$ || ! $timeout_s =~ ^[0-9]+$ ]]; then
            echo "error: corrupt state file: $f" >&2
            status=dead
        fi

        # 终态 (finished/timeout/dead) 不再改写 state、不再重复清理
        if [[ $status != finished && $status != timeout && $status != dead ]]; then
            report="$dir/$name.report.md"
            now=$(date +%s)

            # 判定顺序: 报告优先, 不误杀刚写完报告的 agent
            # 1) 报告已写出 -> finished, 顺手清理会话/进程
            if [[ -f $report ]]; then
                status=finished
                cleanup_agent "$method" "$id"
            # 2) 墙钟超过 timeout -> timeout, kill 会话/进程
            elif (( now - starttime > timeout_s )); then
                status=timeout
                cleanup_agent "$method" "$id"
            # 3) 进程消失且无报告 -> dead (崩溃/被外部杀掉)
            elif ! agent_alive "$method" "$id"; then
                status=dead
                cleanup_agent "$method" "$id"
            else
            # 4) 阻塞检测 — jsonl 最后一行连续 STALL_LIMIT 轮不变 -> stuck
                if [[ -s "$dir/$name.jsonl" ]]; then
                    last=$(tail -n 1 "$dir/$name.jsonl")
                    if [[ $stored_last == "$last" ]]; then
                        stallcnt=$((stallcnt + 1))
                        if (( stallcnt >= STALL_LIMIT )); then
                            status=stuck
                        fi
                    else
                        # 有进展 -> 计数清零, stuck 回退 running
                        stallcnt=0
                        status=running
                    fi
                    stored_last=$last
                else
                    # jsonl 还没有内容 (pi 刚启动) -> 不算 stall
                    status=running
                fi
            fi

            # 原子改写 state 后三行 (status/stallcnt/lastline)
            rewrite_state "$f" "$status" "$stallcnt" "$stored_last"
        fi

        results+=("$starttime|$name|$status")
    done

    # 输出全部 agent 状态, 按启动时间排序
    if (( ${#results[@]} > 0 )); then
        printf '%s\n' "${results[@]}" | sort -t'|' -k1,1n | while IFS='|' read -r _t _n _s; do
            echo "$_n: $_s"
        done
    fi

    # 本次 poll 完成, 刷新组级时间戳
    date +%s > "$dir/lastpoll.time"

# ============================================================================
# get <group> <name>
#   读取指定 agent 的报告 (只读, 不做状态校验, 不清理任何东西)
# ============================================================================
elif [[ ${1:-} == get ]]; then
    group=${2:-}
    name=${3:-}
    if [[ -z $group || -z $name ]]; then
        usage
    fi
    if ! valid_name "$group" || ! valid_name "$name"; then
        echo "error: <group> and <name> must match ^[A-Za-z0-9][A-Za-z0-9_-]*$" >&2
        exit 1
    fi
    dir="$(group_base)/subagent-loop-$group"
    if [[ ! -d $dir ]]; then
        echo "error: group $group not found: $dir" >&2
        exit 1
    fi

    # 报告存在即输出全文, 不存在即报错 (running 中的 agent get 自然也是这个错误)
    report="$dir/$name.report.md"
    if [[ -f $report ]]; then
        cat "$report"
    else
        echo "error: report not found for agent $name in group $group" >&2
        exit 1
    fi

# ============================================================================
# clean <group> [<name>]
#   清理指定 agent 的会话/进程 (无论状态) 并删除其全部文件;
#   无 <name> 时清理整个 group, 最后删除组目录 (含 lastpoll.time)
# ============================================================================
elif [[ ${1:-} == clean ]]; then
    group=${2:-}
    name=${3:-}
    if [[ -z $group ]]; then
        usage
    fi
    if ! valid_name "$group"; then
        echo "error: <group> must match ^[A-Za-z0-9][A-Za-z0-9_-]*$" >&2
        exit 1
    fi
    dir="$(group_base)/subagent-loop-$group"
    if [[ ! -d $dir ]]; then
        echo "error: group $group not found: $dir" >&2
        exit 1
    fi

    if [[ -n $name ]]; then
        # 指定单个 agent
        if ! valid_name "$name"; then
            echo "error: <name> must match ^[A-Za-z0-9][A-Za-z0-9_-]*$" >&2
            exit 1
        fi
        if [[ ! -f "$dir/$name.state" ]]; then
            echo "error: agent $name not found in group $group" >&2
            exit 1
        fi
        clean_agent "$dir" "$name"
    else
        # 无 <name>: 逐个清理组内全部 agent, 最后删除整个组目录
        for f in "$dir"/*.state; do
            [[ -e $f ]] || continue
            n=${f##*/}
            n=${n%.state}
            clean_agent "$dir" "$n"
        done
        rm -rf "$dir"
        echo "cleaned group: $group"
    fi

else
    usage
fi
