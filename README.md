# multi-agent-collab

一套给**多个 AI 串行接手同一代码库**用的协同规范与工具，打包成 Agent Skill。

> **创作者**：workbuddy-agent（2026-10-13）
> **思路来源**：[claude-codex-handoff](https://github.com/OpenMOSS/claude-codex-handoff) ·
> [agent-orchestra](https://github.com/3338902669-ops/agent-orchestra) ·
> [grove](https://github.com/alxshelepenok/grove) — 详见 [`CREDITS.md`](CREDITS.md)，
> 本项目按其思路做了**针对实际场景的改造**，不是原样照搬。

---

## 这是什么

一个 Agent Skill。AI 加载它之后，就懂得如何在**别人（人或另一个 AI）用过的代码库**上接手干活，
以及干完怎么交出去，而不丢进度、不越界、不泄密。

核心主张只有一句：

> **进度属于仓库，不属于你的记忆。**

由此推出三条：接手必须真跑 git 命令（不能凭印象）、进度必须靠 commit 落到仓库、
规矩尽量由代码强制而不是写在文档里等着被违反。

---

## 解决什么问题

下面每一条都是**真实发生过的事故**，本 skill 的每个设计都对应其中某一行：

| # | 事故 | 后果 | 本 skill 的对策 |
| --- | --- | --- | --- |
| 1 | 把「一次性豁免」当成长期授权，擅自 push 三个 commit | 未经批准的代码进了远端 | `pre-push` 校验一次性令牌，无令牌**物理上推不上去** |
| 2 | 把「先出框架」做成完整实现 | 替用户做了决策，白做一轮 | 「动手前对齐」：先复述范围，确认再写 |
| 3 | 测试安全工具时用真实口令 + `git reset --hard` | 反而造成泄密 | `pre-commit` 凭据扫描 + 测试纪律写进文档 |
| 4 | 交接文档里的「当前 HEAD」落后 6 笔 | 下一位按过期信息干活 | 文档**不记位置型 sha**，一律以 `git log -1` 为准 |
| 5 | 环境时区导致测试假红 | 误判为产品 bug，白排查一轮 | `doctor.sh` 输出时区；约定跑测试固定 `TZ` |
| 6 | 签到文件被误建进 git 工作树 | 差点被 `git add -A` 提交 | 脚本路径写死在工作区、与 CWD 无关 |
| 7 | 「已完成 17/22 项」真值是 24/27 | 误差逐任累积 | **禁止派生计数**，要数字就现算 |

完整的事故经过、根因与处置，见 [`references/PITFALLS.md`](references/PITFALLS.md)。

---

## 快速开始

```bash
# 1. 安装 skill
git clone https://github.com/yy1319hua/multi-agent-collab.git \
    ~/.codebuddy/skills/multi-agent-collab

# 2. 装到目标项目
bash ~/.codebuddy/skills/multi-agent-collab/scripts/init.sh <你的 git 仓库路径>
```

`init.sh` 做三件事：

| 动作 | 落点 |
| --- | --- |
| `hooks/` → | `<repo>/.githooks/`，并设 `core.hooksPath .githooks` |
| `scripts/` → | `<工作区>/tools/`（工作区 = 仓库的**父目录**，不入库） |
| `templates/` → | `<工作区>/`（已存在则不覆盖，不会抹掉别人的进度） |

**工作区约定**：仓库的父目录即工作区，所有状态与凭据都放这里、**git 工作树之外**——
所以 `git add -A` 永远抓不到它们。

```
<工作区>/
├── CURRENT_AI          谁在场
├── LEASE_STATE         签到详情
├── PUSH_TOKEN          push 令牌（一次性）
├── credscan-patterns.txt   项目专属敏感串（可选，不入库）
├── PROGRESS.md         进度看板
├── AGENTS.md           协同规范
├── tools/              脚本
└── <repo>/             git 工作树
    ├── HANDOFF.md      对外交接文档（入库）
    └── .githooks/      钩子
```

---

## 接入场景：有共用沙箱 vs 无共用沙箱

本 skill 有两种部署形态，区别只在一点：**多个 AI 是不是在同一台机器上操作同一个仓库克隆。**

> **一个前提要记牢**：钩子（`.githooks/`）入库、随仓库走；脚本工具（`tools/`）和凭据配置（`credscan-patterns.txt`）放在**工作树外、不入库**。所以 `git clone` 下来有钩子但没有工具，每棵新工作树都得补工具、配 `core.hooksPath`。而 skill 知识层（`SKILL.md` + `references/` 等）装在 **AI 的 CodeBuddy 环境**，与仓库、与机器都是两码事。

### 情况 A：有共用沙箱（多 AI 共用一台开发机 / 同一份克隆）

典型如 oci-panel-app：多个 AI 在共享机上接力同一份仓库克隆。

- 仓库只 clone 一份在共享机；对这棵工作树跑**一次** `init.sh` 即可，钩子、脚本、模板一次到位。
- 因为大家都操作同一份克隆，工作区的 `CURRENT_AI` / `LEASE_STATE` / `PUSH_TOKEN` / `credscan-patterns.txt` 是**单份共享**的——上一位签到，下一位一眼可见。这正是非阻塞签到的设计预期。
- skill 知识层：装在参与协作的 CodeBuddy 环境上。若多个 AI 共用同一实例则装一次；若各自独立实例则各装各的，但钩子与工作区仍共享。
- 天然匹配「共享一台开发机 / 一个工作区」场景（见下文适用边界）。

### 情况 B：无共用沙箱（各 AI 各自独立环境）

典型：A 在自己机器上干完交出去，B 在另一台机器上 clone 接手。

- 每个 AI 各自 clone；**每个新克隆都要单独跑 `init.sh`**——因为 `tools/` 与 `credscan-patterns.txt` 不入库、`core.hooksPath` 不被 clone 继承，clone 下来既没有工具也没配钩子。
- skill 知识层：每个 CodeBuddy 实例装到自己环境一次。
- **关键差异**：工作区状态（`CURRENT_AI` 等）**各机器各一份、互不同步**——A 在机器甲的签到不会反映到机器乙的克隆。因此「谁在场、干到哪」的唯一真相只能落在**仓库内**：`HANDOFF.md`（入库）+ commit 历史 + 把签到信息写进 commit / HANDOFF。这正是「进度属于仓库，不属于本地文件」的体现：跨机器时，本地工作区文件不再是状态载体，仓库才是。
- 实操：交接双方靠 `git fetch` + 读 `HANDOFF.md` + 看最近 commit 对齐，而不是靠共享一份 `CURRENT_AI`。

### 对照

| 维度 | 有共用沙箱（A） | 无共用沙箱（B） |
| --- | --- | --- |
| 仓库克隆 | 一份，全员共享 | 各 AI 各一份 |
| `init.sh` | 跑一次 | 每个克隆各跑一次 |
| 工作区状态（`CURRENT_AI` 等） | 单份共享，天然传递 | 各机各份，互不同步 |
| 状态真相载体 | 工作区文件 + 仓库 | 以仓库（`HANDOFF` + commits）为主 |
| skill 知识层 | 装共享机 / 各实例 | 装各自实例 |
| 适用 | 多 AI 共用开发机 | 跨机器串行交接 |

> 无论哪种情况，skill 知识层都不装在「远程构建机」上——构建机（如某台 ARM 共享机）只是 SSH 可达的运行环境，协同机制跟着**项目仓库**和 **AI 的大脑（skill）**走，不跟远程机器走。

---

## 完整流程

### 接手

```bash
bash tools/lease.sh acquire qoder-agent "重构流量页"
bash tools/doctor.sh
```

然后按六步走（详见 `templates/AGENTS.md`）：

1. **签到** —— 署名 = 产品名小写 + `-agent`。不知道自己叫什么就**拒绝开工、问用户**。
   签完把 `git config --get user.name` 放进回复用户的第一条消息，**让否决窗口打开**。
2. **归档他人未提交改动** —— `git add -A && git commit -m "wip: ..."`。
   **禁止** `reset --hard` / `checkout --` / `clean -fd`。
3. **对齐远端** —— `git fetch && git log --oneline -5`。**以此输出为唯一事实**，与记忆冲突时服从 git。
4. **读现状** —— 一条 `doctor.sh`。
5. **动手前对齐** —— 先向用户复述「我理解你要的是 X，范围到 Y 为止，不含 Z」，拿到确认再写。
6. **收工** —— 更新 `HANDOFF.md` → 取得批准 → push → 确认 `git status` 干净。

**现场五元组**（回复用户的第一条消息必含）：

```
署名 / HEAD（vs origin: ahead|behind|equal）/ 工作树 dirty 数 / 最近 3 笔作者 / 下一未勾项
```

### push

```bash
bash tools/approve-push.sh "用户于 2026-10-13 06:14 批准：xxx 改动入库"
git push origin HEAD
```

没有令牌，`pre-push` 会拒绝并打印如何取得批准。令牌 30 分钟有效、**一次性**（push 通过即自动消费）。

---

## 工具

### `tools/lease.sh` — 工作台签到

```bash
lease.sh status                        # 谁在、何时签的、多久没动静
lease.sh acquire <署名> "本轮用途"      # 签到
lease.sh release                       # 交出工作台
```

**只记录，不互斥。** 曾照搬过硬锁 + 抢占拒绝的方案（源自无人值守的自动协作场景），
在人工调度下反而挡路：上一位卡住不放，用户钦点的下一位就进不来。

### `tools/doctor.sh` — 一条命令出齐接手事实

输出：环境（含时区）/ 签到 / **上一位遗留**（最后提交距今多久）/ git 位置 / 工作树 /
看板 / push 令牌 / 凭据扫描 / 下一步提示。

存在的理由：手敲一串命令既易漏、也易取样错误——真实事故中用 `grep | head -1`
取「当前 HEAD」时命中了文档里另一处过期值，误报过一次。

### `tools/approve-push.sh` — 签发 push 令牌

```bash
approve-push.sh "<用户于何时批准哪一批改动>"
```

令牌落在工作区（不入库），push 通过后自动消费。

### `tools/init.sh` — 一键安装

见上文「快速开始」。

---

## 钩子

### `pre-commit`

四条校验，任一不过就拒绝提交：

1. `user.name` 匹配 `^[a-z][a-z0-9-]*-agent$`
2. `user.name` == `<工作区>/CURRENT_AI`（防忘记签到、也防上一位的签到仍在生效）
3. `user.email` == `<user.name>@local`
4. **凭据扫描**：暂存新增行命中私密特征即拒

第 4 条的设计：

- 只扫**本次暂存的新增行**，不翻历史
- 内置仅**通用特征**（私钥头、`github_pat_`、`ghp_`、常见 API key 形态）
- **项目专属特征**（内网 IP、内部域名）从工作区的 `credscan-patterns.txt` 读取，
  每行一个正则，**该文件绝不入库**——所以本 skill 自己不携带任何真实凭据
- 扫描**排除钩子所在目录**：否则钩子文件里的特征串会被自己拦下（自指问题）

### `pre-push`

无有效令牌直接拒绝，并打印取得批准的方法。

诚实说明两个局限：

1. `core.hooksPath` 不会被 `git clone` 继承，只在配了钩子的那棵工作树生效
2. 技术上可用 `--no-verify` 绕过——钩子的价值是把「随手就推」变成「必须主动违规才能推」

---

## 模板

| 模板 | 位置 | 用途 |
| --- | --- | --- |
| `AGENTS.md` | 工作区（不入库） | 协同规范：接手六步、硬规矩、现场五元组 |
| `HANDOFF.md` | 仓库内（**入库**） | 给下一位看的对外说明 |
| `PROGRESS.md` | 工作区（不入库） | 进度看板，完成一项勾一项 + 记 sha |

---

## 设计原则

### 1. 用户把关不是弱约束

> 代码能被 `--no-verify` 绕过，**用户绕不过**。

这是与自动化多 agent 框架的关键分歧。它们服务于**无人值守**场景，只能靠代码；
而多数真实项目是**人类调度 AI**，每步都要人点头——把用户把关的条目标成"无强制"是本末倒置。

判定表见 [`references/CONFORMANCE.md`](references/CONFORMANCE.md)：
每条规矩问一句「违反时是谁/什么会拦下来」，只有**谁都拦不住**的才是真缺口。

### 2. 只记录，不互斥

见 `lease.sh`。硬锁在人工调度场景下是负担，不是保护。

### 3. 区分「位置型」与「归因型」sha

- **位置型**（"当前 HEAD 在哪"）→ 不要写进文档。任何 commit 都无法在内容里包含自身 sha
  （自指循环），记"最新"永远差 1 笔，记"上一笔"会累积漂移。
- **归因型**（"某改动由哪笔完成"）→ 照常记录，永久有效。

### 4. 文档不写派生计数

「已完成 17/22 项」靠"上一位的数 + 我的增量"手算，**增量对了但基数错了，误差会一路传下去**。
需要数字就现算（`grep -c`）。

### 5. 测试安全工具时也要守安全纪律

用**伪造内容**做测试串；撤销测试提交只用 `--mixed` / `--soft`——
`--hard` 会抹掉未提交的改动（本 skill 的钩子就曾被这样回退成旧版，导致测试文件真进了库）。

附带知识点：只跑 `git gc` 删不掉刚撤回的 commit，**reflog 仍引用着它**，
必须先 `git reflog expire --expire=now --expire-unreachable=now --all` 再 `gc --prune=now`。

---

## 适用边界

| 适合 | 不适合 |
| --- | --- |
| 多个 AI **串行**接力同一代码库 | 多 AI **并行**改同一份代码（用 git worktree 隔离） |
| 共享一台开发机 / 一个工作区 | 无人值守的自动化编排（看纯代码强制的协议框架） |
| 人类全程在环、逐步批准 | 需要自动合并 / 自动验收的流水线 |

---

## FAQ

**Q：能防住 AI 故意绕过吗？**
不能，也不打算。`--no-verify` 绕得过任何钩子。本 skill 的目标是防**无意违规**——
把"随手就推"变成"必须主动违规才能推"，并留下痕迹。防故意破坏靠人，不靠脚本。

**Q：为什么签到不做成硬锁？**
因为串行由**用户调度**，不是系统调度。硬锁在"上一位挂了"时会卡住用户钦点的下一位。
只给信息、不拦人，反而更符合实际。

**Q：凭据扫描为什么不含项目专属串？**
因为本 skill 是公开仓库。专属串（内网 IP、内部域名）放进库里等于公开它们。
改由各项目写在工作树外的配置文件里，库本身保持干净。

**Q：只有我一个 AI 在开发，需要这个吗？**
大概率不需要。核心价值在**交接**——接手别人的活、以及把活交出去。单人单 AI 用不上。

---

## 借鉴与致谢

三个开源项目给了关键启发，但都按"用户全程在环"的实际形态做了改造：

| 项目 | 借鉴了什么 | 改了什么 |
| --- | --- | --- |
| `claude-codex-handoff` | 纯文件承载状态、doctor 自检、lease 概念 | 硬锁 → 非阻塞签到 |
| `agent-orchestra` | Approval 契约、Evidence 理念 | 「是否代码强制」→「谁把关」，用户把关不再算弱 |
| `grove` | 防"声称完成其实没完成"、结构化上下文 | 未采纳其图驱动工作流，对当前规模偏重 |

详见 [`CREDITS.md`](CREDITS.md)。感谢以上作者公开这些思路。

---

## License

MIT。Copyright (c) 2026 workbuddy-agent。
