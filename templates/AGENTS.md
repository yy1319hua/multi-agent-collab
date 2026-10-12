# 多 AI 协同入口

> 位置：`<工作区>/AGENTS.md`（**git 工作树之外**，不入库）
> 谁都能改，改完在底部「变更」追加一行。

## 你是谁、该做什么

你大概是被用户叫醒、接手某个项目的 AI。本文件告诉你在**这台共享工作台**上怎么干活。

工作区约定（工作区 = git 仓库的父目录，**工作树之外**）：

| 项 | 路径 |
| --- | --- |
| git 仓库 | `<工作区>/<repo>/` |
| 签到文件 | `<工作区>/CURRENT_AI` |
| 进度看板 | `<工作区>/PROGRESS.md` |
| 交接文档 | 仓库内 `HANDOFF.md`（要对外，故入库） |
| 凭据 | `<工作区>/creds/`（700/600，**绝不入库**） |
| 工具 | `<工作区>/tools/` |

## 接手标准流程（每次都要走，别跳）

> 🔴 **进度属于仓库，不属于你的记忆。** 无论你是不是「刚经手的老 AI」、无论你觉得现场是什么样，
> 都必须真跑下面的 git 命令再决策。凭记忆直接续做会覆盖别人的里程碑。

### 第 1 步：签到

```bash
bash <工作区>/tools/lease.sh acquire <你的署名> "本轮用途"
cd <repo> && git config --local user.name "<署名>" && git config --local user.email "<署名>@local"
git config core.hooksPath .githooks
```

署名 = 产品名小写 + `-agent`。**不知道自己叫什么 → 拒绝开工，回报用户。**
签完把 `git config --get user.name` 放进回复用户的第一条消息，**让否决窗口打开**。

### 第 2 步：归档他人未提交改动

```bash
git status
# 有东西就：git add -A && git commit -m "wip: 接手 <上一位署名> 的未提交改动"
```

**禁止** `reset --hard` / `checkout --` / `clean -fd`。看着像垃圾的也可能是半成品。

### 第 3 步：对齐远端

```bash
git fetch && git log --oneline -5
```

**以此输出为唯一事实。** 凡与你的记忆/假设冲突，一律服从 git。

### 第 4 步：读现状

```bash
bash <工作区>/tools/doctor.sh
```

一条命令出齐：环境 / 签到 / 上一位遗留 / git 位置 / 看板 / 凭据扫描。

### 第 5 步：动手前对齐（治越界，必做）

先向用户复述「**我理解你要的是 X，范围到 Y 为止，不含 Z**」，拿到确认再写代码。
中途发现要偏离已确认范围 → **停下来重新确认**，不得自行扩大。

### 第 6 步：收工

更新 `HANDOFF.md` → 取得用户批准 → `push` → 确认 `git status` 干净。

**收工判据（硬性）**：若在 `PROGRESS.md` 勾了任意一项，`HANDOFF.md` 的「已完成 / 下一步」
必须同轮改，否则算未收工。
**禁止写派生计数**（如「已完成 17/22 项」）——基数错了误差会一路传下去。要数字就现算。

## 现场五元组（回复用户的第一条消息必含）

```
署名：<你签的什么>
HEAD：<git rev-parse --short HEAD>（vs origin：ahead/behind/equal）
工作树：dirty=<n> files
最近 3 笔作者：<git log --format=%an -3>
下一未勾项：<PROGRESS.md 里那条完整文字>
```

## 硬规矩

1. **单 AI 串行**。靠 commit 把进度留在仓库里；被硬中断时没提交的东西等于没做过。
2. **署名**：第 1 步写入 `CURRENT_AI` + `git config --local`；用户可否决，立刻重签。
3. **push / 打 tag / 触发 CI 每次都要用户单独批准**。上次批准不延续。
   `pre-push` 会校验一次性令牌，无令牌物理上推不上去。
4. **历史重写默认禁**：`filter-branch` / `rebase` / 强推 / `reset --hard origin/*`
   须用户事前单独批准，批准前先 `git bundle create` 存档。**AI 不自作主张修历史。**
5. **目录铁律**：只在授权目录内读写。
6. **私密信息不入库**：IP、域名、口令、私钥、token 不得进任何进 git 的文件，含 commit message。
   `pre-commit` 会扫描暂存新增行，命中即拒。
7. **方案先行**：新增功能 / UI 改动必须先出方案（必要时附效果图）交用户过目，
   拿到明确批准前禁止改代码、禁止打包。

关于「谁把关」的完整判定，见 skill 的 `references/CONFORMANCE.md`——
**注意：用户把关不是弱约束。代码能被 `--no-verify` 绕过，用户绕不过。**

## 变更

| 日期 | 署名 | 改了什么 |
| --- | --- | --- |
| （初始化） | — | 由 multi-agent-collab skill 生成 |
