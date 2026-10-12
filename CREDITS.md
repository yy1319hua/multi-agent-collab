# 借鉴来源

本 skill 的思路受以下三个开源项目启发。我们按自身场景（用户全程在环的串行协同）
做了改造，**不是原样照搬**——下面也写明了改了什么、为什么改。

## [OpenMOSS/claude-codex-handoff](https://github.com/OpenMOSS/claude-codex-handoff)

异步、文件驱动、两个 agent 共享一个工作区的交接协议。

**借鉴**：
- 工作台状态用**纯文件**承载，无 daemon、无服务器——这一点完全适用于共享开发机的场景
- `tools/doctor.py` 的自检思路 → 本 skill 的 `scripts/doctor.sh`
- atomic lease 的概念

**改造**：
- 它的 lease 是**硬锁 + 抢占拒绝**，服务的是"两个 agent 定时自动唤醒、无人调度"。
  我们是**用户手动点将串行**，硬锁会挡住用户钦点的下一位（上一位卡住就要等超时）。
  → 改为**非阻塞签到**，只记录「谁、何时、用途」，不拦任何人。

## [3338902669-ops/agent-orchestra](https://github.com/3338902669-ops/agent-orchestra)

治理型多 agent 协同协议。主张 **"Agents can work. They cannot declare success."**

**借鉴**：
- Approval 契约：「未经批准不得执行外部动作」→ 本 skill 的 `pre-push` + 一次性令牌
- Evidence 理念：结论须可验证，不能只声称

**改造**：
- 它用「ENFORCED / DOCUMENTED ONLY」判定每条 MUST 是否有代码强制。
  我们照搬了一次，结果把**用户把关**的条目打成了 ❌——这是错的。
  它服务于无人值守系统，只能靠代码；我们用户全程在环，而代码可被 `--no-verify` 绕过、
  用户绕不过。**用户把关强于代码。**
  → 判定标准改为「谁把关」（代码 / 用户 / 无人），见 `references/CONFORMANCE.md`。

## [alxshelepenok/grove](https://github.com/alxshelepenok/grove)

跨会话、跨 agent 的长期项目工作流协议。

**借鉴**：
- 「Agent 报告完成但其实没完成」的问题意识 → 本 skill 的证据原则
- 上下文严格结构化而非有损压缩 → 体现在模板设计里

**未采纳**：
- 它的图驱动 / 形式化工作流对当前规模偏重，我们只需"接手六步 + 一张看板"。

---

感谢以上作者公开这些思路。本 skill 中所有事故记录均来自真实实践，可自由取用。
