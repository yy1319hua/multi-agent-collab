#!/usr/bin/env bash
# 签发 push 令牌 —— 把「push 需用户批准」从文档约束变成代码强制。
#
# 背景：这条规矩写在文档里时拦不住任何人。真实事故：某 AI 把「一次性豁免」
# 当成长期授权，未经本次批准直接推送了三个 commit。装上 pre-push 后，
# 没有令牌物理上推不上去。
#
# 两种令牌：
#   batch（默认）一次推送，30 分钟有效，push 后自动消费。
#   plan  方案级  方案期内可多次推送，且**每次都由 pre-push 机械校验改动文件
#                是否在批准范围内**，越界即拒；受「范围 + 时间」双重约束。
#
# 为什么 plan 模式必须带范围（--paths）：
#   令牌若说不清「批准了什么」，就只能靠缩短有效期来限制风险——那正是
#   「每推一次都要停下来请示」的成因。把范围写进令牌，把关的维度就从时间
#   换成范围：实现阶段不必反复打断，而越界仍由代码拦截，不是靠文档承诺。
#
# 令牌落在工作区（git 工作树之外）。
set -uo pipefail

BATCH_MINUTES="${PUSH_TOKEN_MINUTES:-30}"
PLAN_DAYS="${PUSH_TOKEN_PLAN_DAYS:-7}"

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "不在 git 仓库内" >&2; exit 2
}
WS="${WORKSPACE:-$(dirname "$repo_root")}"
TOKEN="$WS/PUSH_TOKEN"

usage() {
    cat >&2 <<EOF
用法：
  approve-push.sh "<批准说明>"
      batch 令牌：一次推送有效，${BATCH_MINUTES} 分钟过期，push 后自动消费。

  approve-push.sh --plan "<方案名>" --paths "<范围>" "<批准说明>"
      plan 令牌：方案期内可多次推送，${PLAN_DAYS} 天过期；
      每次 push 由 pre-push 校验改动文件是否在「范围」内，越界即拒。
      例：--plan "M1 指标采集" --paths "scripts/ templates/"
      范围按空格分词，不支持含空格的路径。

  approve-push.sh --revoke
      撤回当前令牌。plan 令牌在方案结束、或范围需要变更时应显式撤回。

说明里写清：谁批准的、批准哪一批改动 / 哪个方案。
EOF
}

MODE=batch
PLAN=""
PATHS=""
NOTE=""
REVOKE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --plan)
            [ $# -ge 2 ] || { echo "错误：--plan 需要给出方案名" >&2; exit 2; }
            MODE=plan; PLAN="$2"; shift 2 ;;
        --paths)
            [ $# -ge 2 ] || { echo "错误：--paths 需要给出批准范围" >&2; exit 2; }
            PATHS="$2"; shift 2 ;;
        --minutes)
            [ $# -ge 2 ] || { echo "错误：--minutes 需要给出数字" >&2; exit 2; }
            BATCH_MINUTES="$2"; shift 2 ;;
        --days)
            [ $# -ge 2 ] || { echo "错误：--days 需要给出数字" >&2; exit 2; }
            PLAN_DAYS="$2"; shift 2 ;;
        --revoke)  REVOKE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *)         NOTE="$1"; shift ;;
    esac
done

# ---------- 撤回 ----------
if [ "$REVOKE" = 1 ]; then
    if [ -f "$TOKEN" ]; then
        rm -f "$TOKEN"
        echo "✅ 已撤回 push 令牌（$TOKEN）"
        echo "   下次 push 需重新取得用户批准。"
    else
        echo "本就没有令牌，无需撤回。"
    fi
    exit 0
fi

# ---------- 校验 ----------
if [ -z "$NOTE" ]; then
    echo "错误：缺少批准说明" >&2
    echo "  说明里写清：谁批准的、批准哪一批改动 / 哪个方案。" >&2
    echo "" >&2
    usage
    exit 2
fi

if [ "$MODE" = plan ]; then
    if [ -z "$PLAN" ]; then
        echo "错误：--plan 模式下必须给出方案名" >&2; exit 2
    fi
    if [ -z "$PATHS" ]; then
        echo "错误：--plan 模式下必须用 --paths 给出批准范围" >&2
        echo "  没有范围的方案令牌形同无把关，故拒绝签发。" >&2
        exit 2
    fi
    # 拒绝覆盖整个仓库的 pathspec：那样 pre-push 的范围校验形同虚设
    for p in $PATHS; do
        case "$p" in
            .|./|/|\*)
                echo "错误：--paths 中出现覆盖整个仓库的范围（'$p'）" >&2
                echo "  那样 pre-push 的范围校验会形同虚设。请给出具体目录或文件。" >&2
                exit 2 ;;
        esac
    done
fi

# 已有未使用的有效令牌 → 拒绝覆盖（防「长期授权」错觉，见 PITFALLS #1）
if [ -f "$TOKEN" ]; then
    exp=$(sed -n 's/^EXPIRE_EPOCH=//p' "$TOKEN")
    if [ "${exp:-0}" -gt "$(date +%s)" ]; then
        echo "⚠️  已存在未使用的有效令牌：" >&2
        sed 's/^/    /' "$TOKEN" >&2
        echo "   如需覆盖：approve-push.sh --revoke 后重新签发" >&2
        exit 1
    fi
fi

# ---------- 签发 ----------
now_s=$(date +%s)
if [ "$MODE" = plan ]; then
    exp_s=$(( now_s + PLAN_DAYS * 86400 ))
else
    exp_s=$(( now_s + BATCH_MINUTES * 60 ))
fi

{
    echo "MODE=$MODE"
    echo "ISSUED_AT=$(date '+%Y-%m-%dT%H:%M:%S%:z')"
    echo "ISSUED_EPOCH=$now_s"
    echo "EXPIRE_EPOCH=$exp_s"
    echo "EXPIRE_AT=$(date -d "@$exp_s" '+%Y-%m-%dT%H:%M:%S%:z')"
    echo "BY=$(cat "$WS/CURRENT_AI" 2>/dev/null || echo unknown)"
    echo "NOTE=$NOTE"
    if [ "$MODE" = plan ]; then
        echo "SCOPE_PLAN=$PLAN"
        echo "SCOPE_PATHS=$PATHS"
    fi
} > "$TOKEN"
chmod 600 "$TOKEN"

if [ "$MODE" = plan ]; then
    echo "✅ plan 令牌已签发（方案「$PLAN」，${PLAN_DAYS} 天有效，可多次推送，按范围校验）"
else
    echo "✅ batch 令牌已签发（${BATCH_MINUTES} 分钟有效，一次性）"
fi
sed 's/^/   /' "$TOKEN"
echo ""
if [ "$MODE" = plan ]; then
    echo "   方案期内可直接 push；每次 pre-push 会校验改动文件是否在 SCOPE_PATHS 内，越界即拒。"
    echo "   打 tag / 新分支首次推送仍须逐次批准（plan 令牌不适用）。"
    echo "   方案结束或范围变更请执行：approve-push.sh --revoke"
else
    echo "   现在可以 push；pre-push 通过后会自动消费该令牌。"
fi
