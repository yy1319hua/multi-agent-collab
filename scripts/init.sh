#!/usr/bin/env bash
# 一键安装：把协同机制装到目标项目。
#
# 用法：bash init.sh <git 仓库路径>
#
# 会做三件事：
#   1. hooks/  →  <repo>/.githooks/          并设 core.hooksPath
#   2. scripts/ → <工作区>/tools/             （工作区 = 仓库的父目录，不入库）
#   3. templates/ → <工作区>/                 （AGENTS.md / HANDOFF.md / PROGRESS.md）
#
# 前提：仓库的父目录即工作区（git 工作树之外），凭据与状态都放这里，
# 因此 git add -A 永远抓不到它们。
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="${1:-}"

if [ -z "$target" ]; then
    echo "用法：bash init.sh <git 仓库路径>" >&2
    exit 2
fi
if [ ! -d "$target/.git" ]; then
    echo "不是 git 仓库：$target" >&2
    exit 2
fi

repo_root=$(cd "$target" && git rev-parse --show-toplevel)
WS=$(dirname "$repo_root")

echo "仓库：$repo_root"
echo "工作区：$WS"
echo ""

# 1) 钩子
mkdir -p "$repo_root/.githooks"
for h in "$SELF_DIR"/hooks/*; do
    [ -f "$h" ] || continue
    cp "$h" "$repo_root/.githooks/$(basename "$h")"
    chmod +x "$repo_root/.githooks/$(basename "$h")"
    echo "  ✓ 钩子 $(basename "$h")"
done
(cd "$repo_root" && git config core.hooksPath .githooks)
echo "  ✓ core.hooksPath = .githooks"
echo ""

# 2) 脚本
mkdir -p "$WS/tools"
for s in "$SELF_DIR"/scripts/*; do
    [ -f "$s" ] || continue
    cp "$s" "$WS/tools/$(basename "$s")"
    chmod +x "$WS/tools/$(basename "$s")"
    echo "  ✓ 脚本 $(basename "$s")"
done
echo ""

# 3) 模板
# 落点分两类：协同规范与看板放工作区（不入库），交接文档放仓库内（入库，对外）。
for t in "$SELF_DIR"/templates/*; do
    [ -f "$t" ] || continue
    base="$(basename "$t")"
    if [ "$base" = "HANDOFF.md" ]; then
        dst="$repo_root/$base"          # 入库：给下一位看的对外说明
    else
        dst="$WS/$base"                 # 不入库：协同规范 / 进度看板
    fi
    if [ -f "$dst" ]; then
        echo "  · $base 已存在，跳过（不覆盖别人的进度）"
    else
        cp "$t" "$dst"
        echo "  ✓ 模板 $base  →  ${dst/#$repo_root/<repo>}"
    fi
done
echo ""

cat <<EOF
安装完成。

下一步：
  1. 签到：    bash $WS/tools/lease.sh acquire <署名> "本轮用途"
  2. 自检：    bash $WS/tools/doctor.sh
  3. 若项目有内网 IP / 内部域名等专属敏感串，写入（工作树外、不入库）：
       $WS/credscan-patterns.txt     每行一个正则

注意：push 前须取得用户批准并签发令牌：
     bash $WS/tools/approve-push.sh "<用户于何时批准哪一批改动>"
EOF
