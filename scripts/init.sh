#!/usr/bin/env bash
# 一键安装：把协同机制装到目标项目。
#
# 用法：bash init.sh <git 仓库路径>
#
# 会做五件事：
#   0. 框架实例 → <工作区>/multi-agent-collab/ （自包含：scripts/ hooks/ templates/
#                 references/ README 等；不入库，每个项目一份）
#   1. hooks/  →  <repo>/.githooks/          并设 core.hooksPath
#   2. templates/ → <工作区>/                 （AGENTS.md / PROGRESS.md / HANDOFF.md，不入库）
#   3. creds/  → <工作区>/creds/              （700，工作树外、绝不入库）
#   4. 兜底忽略 → <repo>/.git/info/exclude    （本地级，不入库；对应 PITFALLS #6）
#
# 前提：仓库的父目录即工作区（git 工作树之外），框架实例、凭据与状态都放这里，
# 因此 git add -A 永远抓不到它们。本框架不依赖任何厂商的技能系统——只产出
# 明文脚本 + 明文文档 + git 钩子，WorkBuddy / CodeBuddy / GLM 等任何能跑
# git 与 bash 的 AI 都能用。
# 第 4 步是这条前提的兜底：万一状态文件被误建进工作树，也不会被误提交。
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

# 0) 框架实例 —— 把整套框架（不含 .git 与 SKILL.md）实例化为工作区下的自包含目录。
#    每个项目一份，放在各自工作区；不入库。脚本靠 BASH_SOURCE 自定位，所以
#    任何 AI 用 `bash <工作区>/multi-agent-collab/scripts/xxx.sh` 即可调用，
#    不依赖任何厂商的技能发现路径或占位符。幂等：已存在则刷新静态文件。
FW_DIR="$WS/multi-agent-collab"
if [ "$SELF_DIR" = "$FW_DIR" ]; then
    echo "  · 框架实例即当前目录，跳过复制"
else
    mkdir -p "$FW_DIR"
    for item in scripts hooks references templates README.md CREDITS.md LICENSE; do
        [ -e "$SELF_DIR/$item" ] || continue
        rm -rf "$FW_DIR/$item"
        cp -r "$SELF_DIR/$item" "$FW_DIR/$item"
        echo "  ✓ 框架 $item"
    done
    echo "  ✓ 框架实例 $FW_DIR（自包含，不入库）"
fi
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

# 2) 模板
# 落点：协同规范、进度看板、交接文档统一放工作区（不入库；多 AI 共用工作区、不污染项目库）。
for t in "$SELF_DIR"/templates/*; do
    [ -f "$t" ] || continue
    base="$(basename "$t")"
    dst="$WS/$base"                     # 不入库：协同规范 / 进度看板 / 交接文档（多 AI 共用工作区）
    if [ -f "$dst" ]; then
        echo "  · $base 已存在，跳过（不覆盖别人的进度）"
    else
        cp "$t" "$dst"
        echo "  ✓ 模板 $base  →  ${dst/#$repo_root/<repo>}"
    fi
done
echo ""

# 3) 凭据目录 —— AGENTS.md / HANDOFF.md 都把凭据位置记为 <工作区>/creds/，
#    这里由安装脚本负责把它建出来（700，工作树之外、绝不入库）。
#    幂等：已存在则跳过，且不动目录里已有的任何文件。
mkdir -p "$WS/creds"
chmod 700 "$WS/creds" 2>/dev/null || echo "  ⚠️ 无法 chmod 700 $WS/creds（非当前用户所有？）" >&2
echo "  ✓ 凭据目录 $WS/creds（700，工作树外、绝不入库）"
echo ""

# 4) 兜底忽略 —— 对应 PITFALLS #6「签到文件被误建进 git 工作树」。
#    状态文件本该落在<工作区>（工作树之外），但若有人 cd 进仓库后用相对路径误建，
#    兜底忽略能让 git add -A 也抓不到它们。
#    写在 .git/info/exclude：本地级忽略，不进版本库、不需要 commit——
#    因此不改动目标项目自身的 .gitignore，也不影响其他协作者。
#    幂等：已存在完全相同的一行就跳过，重复跑 init.sh 不会堆积。
exclude_file="$repo_root/.git/info/exclude"
if [ -f "$exclude_file" ]; then
    for pat in CURRENT_AI LEASE_STATE PUSH_TOKEN credscan-patterns.txt; do
        grep -qxF "$pat" "$exclude_file" 2>/dev/null || echo "$pat" >> "$exclude_file"
    done
    echo "  ✓ 兜底忽略 → .git/info/exclude（本地级，不入库）"
fi
echo ""

cat <<EOF
安装完成。

框架实例：$FW_DIR
协同规范：读 $WS/AGENTS.md（或 $FW_DIR/templates/AGENTS.md）

下一步：
  1. 签到：    bash $FW_DIR/scripts/lease.sh acquire <署名> "本轮用途"
  2. 自检：    bash $FW_DIR/scripts/doctor.sh
  3. 若项目有内网 IP / 内部域名等专属敏感串，写入（工作树外、不入库）：
       $WS/credscan-patterns.txt     每行一个正则

注意：push 前须取得用户批准并签发令牌：
     bash $FW_DIR/scripts/approve-push.sh "<用户于何时批准哪一批改动>"
EOF
