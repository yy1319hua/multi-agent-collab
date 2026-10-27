#!/usr/bin/env bash
# 工作台签到（非阻塞）：只记录谁在、何时签的、做什么。不互斥、不拦人。
#
# 设计取舍（见 references/PITFALLS.md #1、CONFORMANCE.md）：
#   串行由「用户调度」而非「系统调度」，硬锁在「上一位卡住」时会挡住用户钦点的下一位。
#   所以本脚本只给信息、不拦人——谁在场、干到哪，一眼可见即可。
#
# 状态落在「工作区」（git 工作树之外，绝不入库）：
#   <工作区>/CURRENT_AI    当前署名（单行，无换行）
#   <工作区>/LEASE_STATE   签到详情
set -uo pipefail

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "错误：不在 git 仓库内" >&2; exit 2
}
WS="${WORKSPACE:-$(dirname "$repo_root")}"
CA="$WS/CURRENT_AI"
LS="$WS/LEASE_STATE"

usage() {
    cat >&2 <<'EOF'
用法：
  lease.sh status                      查看谁在场、何时签的、多久没动静
  lease.sh acquire <署名> "本轮用途"    签到（非阻塞，只记录不拦人）
  lease.sh release                     交出工作台

署名 = 产品名小写 + "-agent"（例：qoder-agent / glm-agent）。
不知道自己叫什么 → 拒绝开工，问用户。
EOF
}

humanize() {  # 入参：秒数；输出：人类可读时长
    local s=$1
    if [ "${s:-0}" -lt 60 ]; then echo "${s} 秒"; return; fi
    local d=$((s/86400)) h=$((s%86400/3600)) m=$((s%3600/60))
    if [ "$d" -gt 0 ]; then echo "${d} 天 ${h} 小时"; elif [ "$h" -gt 0 ]; then echo "${h} 小时 ${m} 分"; else echo "${m} 分"; fi
}

cmd="${1:-status}"
shift || true

case "$cmd" in
    status)
        if [ -f "$CA" ]; then
            sig=$(tr -d '[:space:]' < "$CA")
            echo "当前在场：$sig"
            if [ -f "$LS" ]; then
                purpose=$(sed -n 's/^PURPOSE=//p' "$LS")
                at=$(sed -n 's/^ACQUIRED_AT=//p' "$LS")
                echo "用途    ：${purpose:-（未说明）}"
                echo "签到于  ：${at:-（未知）}"
                es=$(sed -n 's/^ACQUIRED_EPOCH=//p' "$LS")
                if [ -n "${es:-}" ]; then
                    idle=$(( $(date +%s) - es ))
                    echo "已静默  ：$(humanize "$idle")（若很久没动静，先问用户上一位是否还在）"
                fi
            fi
        else
            echo "当前无人签到（未找到 $CA）"
            echo "  → 开工前先：lease.sh acquire <署名> \"用途\""
        fi
        ;;
    acquire)
        [ $# -ge 1 ] || { echo "错误：acquire 需要署名" >&2; usage; exit 2; }
        sig="$1"; purpose="${2:-（未说明）}"
        if [[ ! "$sig" =~ ^[a-z][a-z0-9-]*-agent$ ]]; then
            echo "错误：署名需匹配 ^[a-z][a-z0-9-]*-agent$ （例：qoder-agent）" >&2
            exit 2
        fi
        printf '%s' "$sig" > "$CA"
        now=$(date +%s)
        {
            echo "SIGNATURE=$sig"
            echo "PURPOSE=$purpose"
            echo "ACQUIRED_AT=$(date '+%Y-%m-%dT%H:%M:%S%:z')"
            echo "ACQUIRED_EPOCH=$now"
            echo "WORKSPACE=$WS"
            echo "REPO=$repo_root"
        } > "$LS"
        chmod 600 "$CA" "$LS"
        echo "✅ 已签到为 $sig（非阻塞，不拦人）"
        echo "   用途：$purpose"
        echo "   请接着执行："
        echo "     git config --local user.name \"$sig\" && git config --local user.email \"$sig@local\""
        echo "     git config core.hooksPath .githooks"
        ;;
    release)
        if [ -f "$CA" ]; then
            sig=$(tr -d '[:space:]' < "$CA")
            rm -f "$CA" "$LS"
            echo "✅ $sig 已交出工作台（CURRENT_AI / LEASE_STATE 已清除）"
        else
            echo "本就无人签到，无需 release。"
        fi
        ;;
    -h|--help) usage; exit 0 ;;
    *) echo "错误：未知命令 '$cmd'" >&2; usage; exit 2 ;;
esac
