#!/usr/bin/env bash
# 工作台自检 —— 一条命令出齐接手所需的全部事实。
#
# 存在的理由：接手时手敲一串命令既易漏、也易取样错误
# （真实事故：用 grep|head -1 取「当前 HEAD」时命中了文档里另一处过期值，误报了一次）。
#
# 凭据扫描：内置通用特征 + 可选的项目专属特征（从工作区、工作树外的
# credscan-patterns.txt 读取），本脚本自身不含任何真实凭据。
set -uo pipefail

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "不在 git 仓库内" >&2; exit 2
}
WS="${WORKSPACE:-$(dirname "$repo_root")}"
line() { printf '%s\n' "--------------------------------------------------------------"; }

fmt_ago() {
    local s=$1 d h m
    d=$(( s / 86400 )); h=$(( (s % 86400) / 3600 )); m=$(( (s % 3600) / 60 ))
    if   [ "$d" -gt 0 ]; then echo "${d}天${h}小时"
    elif [ "$h" -gt 0 ]; then echo "${h}小时${m}分"
    else                      echo "${m}分钟"; fi
}

# 凭据特征：通用 + 工作区可选扩展（扩展文件不入库）
BASE_PATTERN='BEGIN OPENSSH PRIVATE KEY|BEGIN RSA PRIVATE KEY|BEGIN PRIVATE KEY|github_pat_|ghp_|AIza[0-9A-Za-z_-]{10,}|sk-[A-Za-z0-9]{20,}'
PATTERN="$BASE_PATTERN"
if [ -f "$WS/credscan-patterns.txt" ]; then
    while IFS= read -r p; do
        [ -z "$p" ] && continue
        case "$p" in \#*) continue;; esac
        PATTERN="$PATTERN|$p"
    done < "$WS/credscan-patterns.txt"
fi

echo "== 工作台自检 $(date '+%m-%d %H:%M %Z') =="
line
echo "【环境】"
echo "  主机: $(hostname)   时区: $(date '+%Z %z')   —— 跑测试建议固定 TZ，避免时间类用例假红"
line

echo "【署名与签到】"
echo "  CURRENT_AI: $(cat "$WS/CURRENT_AI" 2>/dev/null || echo '（缺失）')"
if [ -f "$WS/LEASE_STATE" ]; then
    bash "$(dirname "$0")/lease.sh" status | sed 's/^/  /'
else
    echo "  签到：无人记录（空闲）"
fi
line

cd "$repo_root" || exit 1
echo "【上一位遗留】"
read -r lh la ld ls_ < <(git log -1 --format='%h %an %ct %s' 2>/dev/null)
if [ -n "${lh:-}" ]; then
    ago=$(( $(date +%s) - ${ld:-0} ))
    echo "  最后提交：$lh | $la | $(date -d "@${ld:-0}" '+%m-%d %H:%M') | ${ls_:0:44}"
    echo "  距今：$(fmt_ago "$ago")$([ "$ago" -gt 86400 ] && echo '  ⚠️ 久未动工，接手前先确认对方是否还在')"
else
    echo "  （无提交记录）"
fi
echo "  最近 3 笔："
git log -3 --format='    %h | %an | %ad | %s' --date=format:'%m-%d %H:%M' 2>/dev/null | cut -c1-80
line

echo "【git 位置】"
echo "  HEAD: $(git rev-parse --short HEAD)    origin/HEAD: $(git rev-parse --short origin/HEAD 2>/dev/null || echo '（需 fetch）')"
echo "  ahead=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo '?') behind=$(git rev-list --count HEAD..@{u} 2>/dev/null || echo '?')"
echo "  user.name: $(git config --get user.name)   hooksPath: $(git config --get core.hooksPath)"
line

echo "【工作树】"
dirty=$(git status --porcelain 2>/dev/null | wc -l)
echo "  dirty=$dirty 条"
[ "$dirty" -gt 0 ] && git status --short | sed 's/^/    /'
line

if [ -f "$WS/PROGRESS.md" ]; then
    echo "【看板】"
    echo "  已勾 $(grep -c '^- \[x\]' "$WS/PROGRESS.md") / 未勾 $(grep -c '^- \[ ]' "$WS/PROGRESS.md")"
    next=$(grep -m1 '^- \[ \]' "$WS/PROGRESS.md")
    [ -n "$next" ] && echo "  下一未勾项：$next" || echo "  下一未勾项：（无 —— 全完工）"
    line
fi

echo "【push 令牌】"
if [ -f "$WS/PUSH_TOKEN" ]; then
    exp=$(sed -n 's/^EXPIRE_EPOCH=//p' "$WS/PUSH_TOKEN"); left=$(( exp - $(date +%s) ))
    [ "$left" -gt 0 ] && echo "  ✅ 有效（剩 $(( left / 60 )) 分钟）：$(sed -n 's/^NOTE=//p' "$WS/PUSH_TOKEN")" \
                      || echo "  ⏰ 已过期：$(sed -n 's/^NOTE=//p' "$WS/PUSH_TOKEN")"
else
    echo "  （无 —— push 会被 pre-push 拦截，需先取得用户批准并签发令牌）"
fi
line

echo "【凭据残留扫描（工作树内）】"
# 自指排除：凭据特征串（私钥头 / github_pat_ 等）的定义本身就写在 skill 文件里
# （.githooks/pre-commit、hooks/pre-commit、scripts/doctor.sh）。若不排除，扫描会把自己的
# 特征定义当成命中，报假阳性 —— 与 pre-commit 排除 hooks 目录同理。
# 这些目录是 skill 自身脚手架、不存用户真实凭据；且只在它们确实落在被扫描的仓库树内时才排除，
# 不会误伤目标仓库里同名目录（如用户的 scripts/）。
SCAN_EXCLUDE=( ":(exclude).githooks" ":(exclude)hooks" )
self_dir=$(dirname -- "$0")
if [ "$self_dir" != "." ] && [ "$self_dir" != "/" ] \
   && git ls-files --error-unmatch -- "$self_dir" >/dev/null 2>&1; then
    SCAN_EXCLUDE+=( ":(exclude)$self_dir" )
fi
if git grep -inE "$PATTERN" -- . "${SCAN_EXCLUDE[@]}" 2>/dev/null | head -3 | grep -q .; then
    echo "  ⛔ 命中，立即处理："
    git grep -inE "$PATTERN" -- . "${SCAN_EXCLUDE[@]}" 2>/dev/null | head -3 | cut -c1-110 | sed 's/^/    /'
else
    echo "  ✅ 无命中"
fi
line
echo "【下一步】动手前先向用户复述「我理解你要的是 X、范围到 Y」，确认后再写代码。"
