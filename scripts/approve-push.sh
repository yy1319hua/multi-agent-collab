#!/usr/bin/env bash
# 签发一次性 push 令牌 —— 把「push 需用户单独批准」从文档约束变成代码强制。
#
# 背景：这条规矩写在文档里时拦不住任何人。真实事故：某 AI 把「一次性豁免」
# 当成长期授权，未经本次批准直接推送了三个 commit。装上 pre-push 后，
# 没有令牌物理上推不上去。
#
# 用法：approve-push.sh "<用户于何时批准哪一批改动>"
# 令牌落在工作区（git 工作树之外），30 分钟有效，push 通过后自动消费。
set -uo pipefail

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "不在 git 仓库内" >&2; exit 2
}
WS="${WORKSPACE:-$(dirname "$repo_root")}"
TOKEN="$WS/PUSH_TOKEN"
MINUTES="${PUSH_TOKEN_MINUTES:-30}"

note="${1:-}"
if [ -z "$note" ]; then
    echo "用法：approve-push.sh <批准说明>" >&2
    echo "  说明里写清：谁批准的、批准哪一批改动。" >&2
    exit 2
fi

if [ -f "$TOKEN" ]; then
    exp=$(sed -n 's/^EXPIRE_EPOCH=//p' "$TOKEN")
    if [ "${exp:-0}" -gt "$(date +%s)" ]; then
        echo "⚠️  已存在未使用的有效令牌：" >&2
        sed 's/^/    /' "$TOKEN" >&2
        echo "   如需覆盖请先 rm $TOKEN" >&2
        exit 1
    fi
fi

now_s=$(date +%s); exp_s=$(( now_s + MINUTES * 60 ))
{
    echo "ISSUED_AT=$(date '+%Y-%m-%dT%H:%M:%S%:z')"
    echo "ISSUED_EPOCH=$now_s"
    echo "EXPIRE_EPOCH=$exp_s"
    echo "EXPIRE_AT=$(date -d "@$exp_s" '+%Y-%m-%dT%H:%M:%S%:z')"
    echo "BY=$(cat "$WS/CURRENT_AI" 2>/dev/null || echo unknown)"
    echo "NOTE=$note"
} > "$TOKEN"
chmod 600 "$TOKEN"

echo "✅ push 令牌已签发（${MINUTES} 分钟有效，一次性）"
sed 's/^/   /' "$TOKEN"
echo ""
echo "   现在可以 push；pre-push 通过后会自动消费该令牌。"
