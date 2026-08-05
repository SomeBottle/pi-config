#!/bin/bash
set -euo pipefail

# Sub-agent 最后一行连续未变化 STALL_LIMIT 轮判定为卡住
STALL_LIMIT=5

usage() {
    echo "usage: $0 <cmd> ... < stdin" >&2
    echo "  init <name> <timeout-s> [pi-opts...]  stdin: PROMPT | stdout: 'session: X' 'tmp: Y' 'poll: true|false'" >&2
    echo "  poll <sleep-s:[15,60]> <session> <tmp> stdout: running | finished | timeout" >&2
    echo "  end <session> <tmp>           stdout: report | stderr: report not found" >&2
    exit 1
}

# --- init: 初始化 sub-agent 会话 ---
if [[ ${1:-} == init ]]; then
    name=${2:-}
    timeout_s=${3:-}
    if [[ -z $name || -z $timeout_s ]]; then
        usage
    fi
    if [[ ! $timeout_s =~ ^[0-9]+$ ]]; then
        echo "error: <timeout-s> must be a number" >&2
        exit 1
    fi

    # 只允许从管道或重定向读取 STDIN
    if [[ -t 0 ]]; then
        echo "error: STDIN must be a pipe or redirection, not a TTY" >&2
        exit 1
    fi

    # TMP_DIR 来源: 环境变量 TMP_DIR > mktemp -d
    # mktemp 不可用时提示设置 TMP_DIR
    if [[ -z ${TMP_DIR:-} ]]; then
        if ! TMP_DIR=$(mktemp -d); then
            echo "error: mktemp -d failed, use TMP_DIR env var instead" >&2
            exit 1
        fi
    fi
    if [[ ! -d $TMP_DIR ]]; then
        mkdir -p "$TMP_DIR" || { echo "error: cannot create TMP_DIR: $TMP_DIR" >&2; exit 1; }
    fi

    # 从 STDIN 读取 PROMPT
    prompt=$(cat)
    session="subagent-$name-$(date +%s)"

    # 启动 Pi 实例 (tmux/screen 后台运行，或 --print 阻塞)
    # $4 及之后的所有剩余参数原样传递给 pi options
    pi_opts="--session '$TMP_DIR/$session.jsonl' --approve --no-extensions --append-system-prompt 'You must write final report to $TMP_DIR/$session.o.md.' ${*:4}"
    pi_cmd="pi $pi_opts '$prompt'"
    if command -v tmux >/dev/null 2>&1 || command -v psmux >/dev/null 2>&1; then
        tmux new-session -d -s "$session" "$pi_cmd"
        poll=true
    elif command -v screen >/dev/null 2>&1; then
        screen -dmS "$session" "$pi_cmd"
        poll=true
    else
        # 没有 tmux/screen 时，直接阻塞运行 Pi
        eval "pi $pi_opts --print '$prompt'"
        poll=false
    fi
    date +%s > "$TMP_DIR/$session.start"
    echo "$timeout_s" > "$TMP_DIR/$session.timeout"

    echo "session: $session"
    echo "tmp: $TMP_DIR"
    echo "poll: $poll"

# --- poll: 主 Agent 调用以轮询子 Agent 执行情况 ---
elif [[ ${1:-} == poll ]]; then
    sleep_s=${2:-}
    session=${3:-}
    tmp_dir=${4:-}
    if [[ -z $sleep_s || -z $session || -z $tmp_dir ]]; then
        usage
    fi
    if [[ ! $sleep_s =~ ^[0-9]+$ ]]; then
        echo "error: <sleep-s> must be a number" >&2
        exit 1
    fi
    if (( sleep_s < 15 || sleep_s > 60 )); then
        echo "error: <sleep-s> must be in [15, 60]" >&2
        exit 1
    fi
    if [[ ! -f $tmp_dir/$session.start || ! -f $tmp_dir/$session.timeout ]]; then
        echo "error: session files not found in $tmp_dir" >&2
        exit 1
    fi

    # 等待几秒
    sleep "$sleep_s"

    # 先检查是否超时，再检查是否完成
    timeout_s=$(cat "$tmp_dir/$session.timeout")
    if (( $(date +%s) - $(cat "$tmp_dir/$session.start") > timeout_s )); then
        echo "timeout"
    elif [[ -f $tmp_dir/$session.o.md ]]; then
        echo "finished"
    else
        echo "running"

        # 阻塞检测: session 文件最后一行连续 STALL_LIMIT 轮未变化则提醒 (状态存 .lastline / .stallcnt)
        last_file=$tmp_dir/$session.lastline
        cnt_file=$tmp_dir/$session.stallcnt
        cnt=$(cat "$cnt_file" 2>/dev/null || echo 0)
        if [[ -f $tmp_dir/$session.jsonl ]]; then
            last=$(tail -n 1 "$tmp_dir/$session.jsonl")
            if [[ -f $last_file ]] && [[ $(cat "$last_file") == "$last" ]]; then
                cnt=$((cnt + 1))
                if (( cnt >= STALL_LIMIT )); then
                    echo "warning: sub-agent may be stuck (last session line unchanged for $STALL_LIMIT consecutive polls), user intervention needed"
                fi
            else
                cnt=0
            fi
            printf '%s' "$last" > "$last_file"
        fi
        echo "$cnt" > "$cnt_file"
    fi

# --- end: 主 Agent 调用以结束子 Agent 会话，获取结果并清理文件 ---
elif [[ ${1:-} == 'end' ]]; then
    session=${2:-}
    tmp_dir=${3:-}
    if [[ -z $session || -z $tmp_dir ]]; then
        usage
    fi

    # 输出结果
    if [[ -f $tmp_dir/$session.o.md ]]; then
        echo -e "report file: $tmp_dir/$session.o.md\n"
        cat "$tmp_dir/$session.o.md"
    else
        echo "error: report not found" >&2
    fi

    # 清理: 结束 tmux/screen 会话
    if command -v tmux >/dev/null 2>&1 || command -v psmux >/dev/null 2>&1; then
        tmux kill-session -t "$session" 2>/dev/null || true
    elif command -v screen >/dev/null 2>&1; then
        screen -S "$session" -X quit 2>/dev/null || true
    fi

    # 清理文件，但是临时保留会话文件以及报告文件
    rm -f "$tmp_dir/$session.start" "$tmp_dir/$session.timeout" "$tmp_dir/$session.lastline" "$tmp_dir/$session.stallcnt"

    echo "--- session $session cleaned up ---"
    echo "sub-agent session file: $tmp_dir/$session.jsonl"
else
    usage
fi
