---
name: multi-agent-collab
description: "多个 AI 串行接手同一代码库时的协同规范与工具：接手流程、工作台签到、一键自检、push 审批令牌、提交前凭据拦截。用于「接手别人（AI）未完成的工作」「交出工作台」「多人/多 AI 共用一份代码库」等场景。关键词：接手、交接、多 AI 协同、串行开发、CURRENT_AI、HANDOFF、push 审批、工作台"
version: "1.0.0"
author: "workbuddy-agent"
created: "2026-10-13"
updated: "2026-10-13"
---

# 多 AI 串行协同（Multi-Agent Collaboration）

> **Goal**: 让多个 AI 在同一份代码库上**串行**接力时不丢进度、不越界、不泄密。
> 核心思路：进度归仓库不归记忆，规矩尽量由代码强制而非文档约束。

## When to Use

- 用户让你「接手」某个已有项目（前任是人或其他 AI）
- 你要把工作台交给下一位 AI
- 多个 AI 共用一台共享开发机 / 同一个工作区

## When NOT to Use

- 单人单 AI 开发、不涉及交接
- 需要多 AI **并行**改同一份代码——本 skill 是串行模型，并行请改用 git worktree 隔离方案

## 铁律（先看这四条）

1. **进度属于仓库，不属于你的记忆。** 无论你多确定现场是什么样，接手时必须真跑 git 命令再决策。
2. **单 AI 串行**，靠 commit 留进度；被硬中断时没提交的东西等于没做过。
   **commit 按「可验证小步」细分，不按看板条目**——一整项做完才提交，中断时丢得更多。
   判据：**「现在被打断，这一步的产出值不值得留下？」** 值得就提交。
3. **push / 打 tag / 触发 CI 每次都要用户单独批准**，上次批准不延续。
4. **私密信息不入库**：IP、域名、口令、私钥、token 不得进任何进 git 的文件，含 commit message。

## 接手六步

1. **签到**：`bash scripts/lease.sh acquire <你的署名> "本轮用途"`
   署名 = 产品名小写 + `-agent`（如 `qoder-agent`）。不知道自己叫什么 → 拒绝开工，问用户。
   同时 `git config --local user.name/email` 与 `core.hooksPath` 指向本 skill 的 hooks。
2. **归档他人未提交改动**：`git status` 有东西就 `git add -A && git commit -m "wip: ..."`。
   **禁止** `reset --hard` / `checkout --` / `clean -fd`。
3. **对齐远端**：`git fetch && git log --oneline -5`，对比 `origin/main`。**以此输出为唯一事实**。
4. **读现状**：`bash scripts/doctor.sh` —— 一条命令出齐接手所需全部事实。
5. **动手前对齐**（治越界，必做）：先向用户复述「我理解你要的是 X，范围到 Y 为止，不含 Z」，拿到确认再写。
   中途要偏离 → 停下来重新确认。
6. **收工**：更新交接文档 → 取得用户批准 → push → `git status` 确认干净。

**现场五元组**（回复用户的第一条消息必含）：
署名 / HEAD（vs origin）/ 工作树 dirty 数 / 最近 3 笔作者 / 下一个未勾项。

## 工具

| 脚本 | 用途 |
| --- | --- |
| `scripts/lease.sh` | 工作台签到。**非阻塞**：只记录谁在、何时签的，不拦任何人 |
| `scripts/doctor.sh` | 一条命令出齐：环境 / 签到 / 上一位遗留 / git 位置 / 看板 / 凭据扫描 |
| `scripts/approve-push.sh` | 签发一次性 push 令牌（30 分钟，push 后自动消费） |
| `scripts/init.sh` | 一键安装：复制模板 + 挂钩子到目标项目 |

钩子（安装后由 git 自动调用）：

- `hooks/pre-commit`：署名格式 + 与签到文件一致 + email 一致 + **凭据扫描**
- `hooks/pre-push`：**无令牌直接拒绝 push**

## 凭据扫描的配置（重要）

内置只含**通用特征**（私钥头、GitHub token 前缀等），不含任何项目专属串。

项目专属特征（如内网 IP、内部域名）请写到**工作树外**的文件：

```
<工作区>/credscan-patterns.txt     # 每行一个正则，绝不入库
```

钩子会自动读取并合并。这样公开的本 skill 不含任何真实凭据。

## 参考（按需加载）

- `references/CONFORMANCE.md` — 七条硬规矩「谁把关」判定表。**注意：用户把关强于代码**，因为代码能被 `--no-verify` 绕过，用户绕不过。
- `references/PITFALLS.md` — 真实踩过的坑（含一次"测试安全工具反而造成泄密"的事故）
- `templates/` — `AGENTS.md` / `HANDOFF.md` / `PROGRESS.md` 模板

## 借鉴来源

见 `CREDITS.md`：思路来自 `claude-codex-handoff`（租约/doctor）、`agent-orchestra`（Approval 契约）、`grove`（证据驱动）。本 skill 按「用户全程在环」的实际形态做了改造，**不是原样照搬**。
