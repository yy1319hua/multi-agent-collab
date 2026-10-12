#!/usr/bin/env bash
# 工作台签到 —— 记录「谁在场、何时签的」，供下一位接手时判断。
#
# 设计要点：
#   * 非阻塞。只记录信息，不拦任何人。
#     曾照搬过「硬锁 + 抢占拒绝」的租约方案（源自无人值守的自动协作场景），
#     在人工调度的场景下反而挡路：上一位卡住不放，用户钦点的下一位就进不来。
#     本工具服务的是「用户手动点将串行」，所以只给信息、不做互斥。
#   * 路径从 git 仓库根推导（工作区 = 仓库的父目录），不写死任何绝对路径。
#   * 签到文件落在工作区、**git 工作树之外**，不会被 git add -A 抓走。
set -uo pipefail

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "不在 git 仓库内，无法确定工作区" >&2; exit 2
}
WS="${WORKSPACE:-$(dirname "$repo_root")}"
SIGNIN="$WS/CURRENT_AI"
STATE="$WS/LEASE_STATE"

now() { date +%s; }

fmt_ago() {
    local s=$1 d h m
    d=$(( s / 86400 )); h=$(( (s % 86400) / 3600 )); m=$(( (s % 3600) / 60 ))
    if   [ "$d" -gt 0 ]; then echo "${d}天${h}小时"
    elif [ "$h" -gt 0 ]; then echo "${h}小时${m}分"
    else                      echo "${m}分钟"; fi
}

cmd_status() {
    if [ ! -f "$STATE" ]; then
        echo "签到：无人记录（工作台空闲）"
        return 0
    fi
    local agent at_epoch purpose ago
    agent=$(sed -n 's/^AGENT=//p' "$STATE")
    at_epoch=$(sed -n 's/^AT_EPOCH=//p' "$STATE")
    purpose=$(sed -n 's/^PURPOSE=//p' "$STATE")
    ago=$(( $(now) - at_epoch ))
    echo "签到：${agent:-未知}"
    echo "  时间：$(date -d "@${at_epoch:-0}" '+%m-%d %H:%M')（距今 $(fmt_ago "$ago")）"
    echo "  用途：${purpose:-（未填）}"
    [ "$ago" -gt 14400 ] && echo "  ⚠️  超过 4 小时无更新，对方大概率已停工"
    return 0
}

cmd_acquire() {
    local agent="${1:-}" purpose="${2:-}"
    [ -z "$agent" ] && { echo "用法：lease.sh acquire <署名> [用途]" >&2; exit 2; }

    if [ -f "$STATE" ]; then
        local prev prev_epoch ago
        prev=$(sed -n 's/^AGENT=//p' "$STATE")
        prev_epoch=$(sed -n 's/^AT_EPOCH=//p' "$STATE")
        ago=$(( $(now) - prev_epoch ))
        if [ -n "$prev" ] && [ "$prev" != "$agent" ] && [ "$ago" -lt 14400 ]; then
            echo "ℹ️  上一位是 ${prev}（$(fmt_ago "$ago")前签到）。" >&2
            echo "   本工具不做拦截——串行由用户调度，确认对方已停即可接管。" >&2
        fi
    fi

    {
        echo "AGENT=$agent"
        echo "AT=$(date '+%Y-%m-%dT%H:%M:%S%:z')"
        echo "AT_EPOCH=$(now)"
        echo "PURPOSE=${purpose:-（未填）}"
    } > "$STATE"
    chmod 600 "$STATE"

    # 同步到 CURRENT_AI（接手流程第 1 步要求）
    printf '%s\n' "${agent%-agent}" > "$SIGNIN"

    echo "✅ 已签到：$agent"
    cmd_status | sed 's/^/   /'
}

cmd_release() {
    if [ -f "$STATE" ]; then
        local who; who=$(sed -n 's/^AGENT=//p' "$STATE")
        rm -f "$STATE"
        echo "✅ 已交出工作台（原：${who:-未知}）"
    else
        echo "本就空闲，无需操作"
    fi
}

case "${1:-status}" in
    status)  cmd_status ;;
    acquire) shift; cmd_acquire "$@" ;;
    release) cmd_release ;;
    *) echo "用法：lease.sh {status|acquire <署名> [用途]|release}" >&2; exit 2 ;;
esac
