---
name: test-strategist
description: |
  测试策略师：决定**测什么、为什么测这里、优先测哪个、怎么判定、值不值得测**。资深测试专家的判断力落成确定性流程——把需求 / 代码变更 / 线上事故转成有证据的风险台账与可执行的验证义务，再交给 playbook 落地成测试代码。
  触发场景：问"这次变更有什么测试风险 / 测试重点在哪 / 该测什么 / 先测哪个"；时间不够要排优先级或砍范围；问"这个能不能不测 / 风险能不能接受"；需求或设计方案评审要挑歧义与未定义边界；线上出了事故要定根因并决定补什么测试和监控；判断某块"测得了吗"（可测试性）；接口 / 数据一致性 / 事务 / 并发 / 幂等 / 缓存 / 消息队列 / LLM 与 AI 功能 / 性能 / 安全 / 兼容性 这些场景该验什么；已有测试套件但怀疑"测了不少却抓不到 bug"。
  三方分流（测试类 skill 只此三个，按**手里的输入物**选）：手里是需求 / 变更 / 事故，还不知道该测什么 → 本 skill（产出风险台账、优先级、验证义务、处置决定）；手里已知要测什么、要产出测试代码（选择器、断言、mock、fixture、spec、CI）→ `playbook`；手里已有测试要打分定级 → `e2e-test-quality`。问"覆盖够不够"先分辨：问该覆盖哪些风险点、哪些风险没人管归本 skill，评已有套件的覆盖度归 e2e-test-quality，配覆盖率工具看 coverage 数字归 playbook。
  不适用：写或改测试代码、决定某个 case 放哪一层、排查单个测试为何挂或 flaky 归因（都用 playbook）、纯功能 bug 定位（用 diagnose）。
---

# test-strategist —— 测试策略师

## 定位

**唯一决策权**：哪些风险值得处理、优先级多高、怎么处置、用什么判据证明。

**明确不负责**：选择器、断言 API、mock 方案、fixture 组织、spec 文件结构、测试代码——这些是 `playbook` 的独占领域，本 skill 一行都不写，只输出义务让它去落地。

一句话区分：**playbook 回答「怎么把测试写对写稳」，本 skill 回答「该测什么、凭什么说这里危险、怎么算验过了」。**

产物不是场景清单，是**策略包**（Strategy Package）：风险台账 + 排序后的验证义务 + 可测试性缺口 + 明确的不覆盖范围。

## 六条铁律（违反即失败）

1. **无证据不出风险**。每条风险必须指向 `file:line`、需求段落编号、或事故记录。指不出来的，`evidence` 必须显式写 `assumption-no-evidence` 并降一级——不许凭空给发生概率，不许把网上的通用测试清单当本项目风险。
2. **每条风险必须有处置**，五选一：`test`（交 playbook）/ `monitor`（线上观测）/ `design-fix`（改源码或架构）/ `explore`（人工探索，不自动化）/ `accept`（明确接受，记录决策人）。**只列风险不给处置 = 没做完**。
3. **每条验证义务必须有可判定 oracle**。写得出"怎么算通过"才算义务。`refund_transaction_count == 1` 是 oracle，"验证功能正常"不是。
4. **不碰测试写法**。发现自己在想"这里该用 getByRole 还是 testid"、"这个 mock 怎么写"——立刻停，那是 playbook 的地界，写进策略包就是制造第二套标准。
5. **优先级只用 P0–P3 有限锚点**，不做 1–100 的虚假精确打分。P0 有白名单，见 `references/risk-rubric.md`，不在白名单内不许升 P0。
6. **必须写出不覆盖什么**。延后项、剩余风险、判不了的地方要显式列出来。沉默省略等于骗人——「我没提到」和「我确认没风险」是两件事。

## 场景路由表

先认清输入是什么，再决定读哪张方法卡。**不要通读全部 references**，按需读。

| 输入 | 场景 | 主读 |
|---|---|---|
| 代码变更 / PR / diff | 变更风险分诊 | 按变更面选下面的 failure-modes-* |
| 需求文档 / PRD / 设计方案（还没代码） | 左移质疑 | `references/phase-requirements.md` |
| 线上事故 / 故障报告 / 客诉 | 根因与系统性预防 | `references/phase-incident.md` |
| 前端 UI / 交互 / 表单 / 路由 | Web 前端 | `references/failure-modes-web.md` |
| 接口 / HTTP API / RPC / 契约 | 服务端接口 | `references/failure-modes-api.md` |
| 数据库 / 事务 / 迁移 / 对账 | 数据一致性 | `references/failure-modes-data.md` |
| 并发 / 重试 / 幂等 / 锁 / 时序 | 并发与幂等 | `references/failure-modes-concurrency.md` |
| 缓存 / 消息队列 / 异步任务 | 缓存与消息 | `references/failure-modes-cache-mq.md` |
| LLM / AI 功能 / 智能体 | AI 系统 | `references/failure-modes-ai.md` |
| 配置 / 环境变量 / feature flag / 依赖升级 / 纯重构 | 声称不改行为的变更 | `references/failure-modes-config-deps.md` |
| 性能 / 安全 / 可访问性 / 兼容性 | 专项质量维度 | `references/quality-dimensions.md` |
| 已有套件但怀疑"抓不到 bug" / 环节有缺口 | 环节完整性 | `references/pipeline-completeness.md` |

**路由兜底**：输入落不到上面任何一行时，**不要直接开始自由联想**——那正是第 2 步要防的。先问自己这次变更触碰了哪些技术面（数据？接口？并发？配置？），按技术面选卡；确实无卡可用时，明确在产物里写"本次无对应方法卡，风险清单为现场判断"，让读者知道这部分证据强度更低。

**公共底座三卡，任何场景都要用**：`risk-rubric.md`（怎么分级）、`evidence-discipline.md`（证据怎么算数）、`oracle-patterns.md`（判据怎么写）。第一次用本 skill 先读这三张。

跨场景很常见——一个下单变更同时命中 api、data、concurrency 三张卡，读全三张，别只挑一张。

## 六步状态机

这是执行路径，**不是思考风格建议**。按序走，每步有输出物，跳步等于没做。

### 1. 证据归一化

把输入材料拆成三类，**混在一起是后面所有失真的源头**：

- **事实**：读到的代码、diff、日志、需求原文。附位置。
- **推断**：从事实推出的判断。必须标出依据的是哪条事实。
- **未知**：需要问人或需要跑起来才知道的。列出来，不要用常识填。

产出一份三分清单。**未知项不许静默转成推断**。

### 2. 沿变更面扫失效模式

按路由表选中的方法卡，逐条对照它的失效模式清单。这一步是**清单驱动**而不是自由联想——自由联想漏掉的恰好是你想不到的那些。

对每个候选失效模式问：本次变更 / 本需求里，有没有东西让它成为可能？找不到证据就丢掉，不要为了凑数留着。

### 3. 风险分级

按 `references/risk-rubric.md` 打 P0–P3。规则要点：
- P0 走白名单（不可逆资金损失、权限越界、数据完整性破坏、大范围不可用），且必须有证据。
- 业务风险四维（影响面 / 变更频度 / 历史高发 / 可逆性）只作为**有证据的调整项**，不能凭感觉加减。
- 没有证据支撑的风险最高 P2。

### 4. 生成验证义务

每条值得处置的风险转成一条义务，字段固定（完整 schema 见 `schemas/strategy-package.schema.json`）：

```yaml
risk_id: R-03
evidence: src/order/refund.ts:84          # 必填，或 assumption-no-evidence
failure_mode: 重试导致同一订单重复扣款      # 必填：这个 bug 长什么样
impact: 不可逆资金损失
priority: P0
disposition: test-and-monitor             # 铁律 2 的五选一（可组合）
validation_obligation:
  precondition: 同一退款请求被重复投递
  observable: 只产生一次账务变更
  oracle: refund_transaction_count == 1   # 必填，可判定
testability_gap: 幂等键当前不可观测         # 无则写 none
confidence: high                          # high/medium/low，与证据强度一致
```

**义务里不写实现**：不写用哪个测试框架、哪一层、什么选择器。层级归属由 `playbook/references/test-pyramid.md` 判定。

**YAML 书写约定**（实测踩过，别再踩）：`oracle` 与 `failure_mode` 天生充满符号字面量，两个坑必踩——值里出现「冒号+空格」（`lessConfig: undefined`、`Tests: N passed`）会被当成嵌套映射；值以符号开头（`">-"`、`<0.01`、`|`、`*`）会被当成 YAML 语法。**这类值一律用 block scalar**：

```yaml
oracle: |
  正值输出中 "<" 之后首字符不为 "+"；npm test 输出含 Tests: N passed
```

### 5. 反证复核

强制自问四条，答案写进产物（这一步是防自我说服的关键）：

1. 这条风险是不是**纯猜测**？拿掉推断只留事实，它还站得住吗？
2. **哪条证据会推翻**当前优先级？如果找不到任何可能推翻它的证据，说明这个判断不可证伪，降级处理。
3. 哪个**关键失败模式还没覆盖**？
4. 哪些场景应该**明确延后或接受**？写进不覆盖清单。

### 6. 门禁校验与交接

产物落盘到项目根的 `.test-strategy/package.yaml`（与 playbook 的 `.playbook/` 并列，**记得加进 gitignore**）。要留档评审或积累 eval 样例时，另存一份 `.test-strategy/<日期>-<主题>.yaml`。

```bash
bash ~/.claude/skills/test-strategist/scripts/validate-package.sh .test-strategy/package.yaml
```

过了才能交接。`disposition` 含 `test` 的义务连同 `risk_id` 交 `playbook`（它生成的测试必须回填 risk_id）；`monitor` 项给监控；`design-fix` 项按风险矩阵走独立任务；`explore` 项给人；`accept` 项记录决策人。

## 门禁

**机器可查**（`scripts/validate-package.sh` 强制）：

- 缺 `evidence` / `failure_mode` / `oracle` / `disposition` → 失败
- P0/P1 没有具体动作或没有 oracle → 失败
- 验证义务没有反向引用 `risk_id` → 失败
- 命中空话黑名单（加强测试 / 确保稳定 / 充分考虑 / 正常工作 / 全面覆盖 / 提升质量）→ 失败
- 没有「不覆盖范围」章节 → 失败

**纪律约束**（自律，无机器拦）：

- 交叉内容只引用 ID 与文档路径，**绝不复制 playbook / e2e-test-quality 的正文**。见 `references/ownership.md`。
- 下游必须回执：playbook 生成的测试回填 `risk_id`，e2e-test-quality 按 ID 验收闭环。没有回执的"闭环"只是文档接力。
- 网络检索只在建设方法卡时用，**不作为每次运行的默认依赖**。通用测试清单不等于本项目风险。

## 快速模式

小改动不值得走全套。触发条件：变更 < 3 文件且不碰 P0 白名单领域。

输出退化为：**最高 2 条风险 + 各一条验证义务 + 一句不覆盖说明**。不写三分清单，不写反证复核全文。

这不是偷懒许可——一旦发现变更碰到资金 / 权限 / 数据完整性 / 并发，立刻升回全流程。

## 触发与边界

**该用本 skill**：问该测什么、测试重点、优先级、能不能不测、风险可否接受；需求或设计评审挑边界与歧义；事故后定根因和预防措施；判断可测试性；问接口 / 数据 / 并发 / 缓存 / AI / 性能 / 安全场景该验什么；怀疑"测了不少却抓不到 bug"。

**不该用**：
- 写或改测试代码、搭测试底座、选选择器、配 CI → `playbook`
- 给已有 E2E 打分定级 → `e2e-test-quality`
- 单个测试为什么挂 / flaky 归因 → `playbook/references/trace-debug.md` / `playbook/references/flaky.md`
- 纯功能 bug 定位 → `diagnose`
- 只想跑起来看页面 → `webapp-testing`
- 性能优化具体实现 → `performance-optimizer`

## 与其他资产协作

三方决策权互不重叠，完整矩阵见 `references/ownership.md`：

| 资产 | 独占决策权 |
|---|---|
| **test-strategist**（本 skill） | 风险识别、优先级、处置决定、验证义务与 oracle |
| **playbook** | 测试写法与实现的单一事实源：分层归属、选择器、断言、mock、fixture、flaky、CI |
| **e2e-test-quality** | 已有测试的评分与判级 |

协作流向：本 skill 出策略包 → playbook 把 `disposition: test` 的义务落成分层测试代码（回填 risk_id）→ e2e-test-quality 按 risk_id 验收「义务是否真被实现、实现得好不好」。

**e2e-test-quality 不得自行重算风险优先级**，playbook 不得重新定义业务优先级，本 skill 不得定义测试写法。任何一方越界就是历史上那次标准漂移的重演。

## 并行执行器（可选）

本 skill 是唯一事实源。`~/.claude/agents/custom/test-risk-scanner.md` 是它的薄执行器，**只在两种情况下派**：

1. 一次要扫**多个互不依赖**的模块 / 服务，需要并行
2. 要对已产出的策略包做**独立反方复核**（专门去找哪条风险是猜的、哪条 evidence 对不上代码）

单个模块的分析**不要派 agent**——主会话直接走本 skill 更准，因为它能拿到会话里的需求背景和用户的纠正，而 agent 拿不到。派发时必须给明确范围、risk_id 前缀（避免多 agent ID 冲突），并要求它第一步先读本 skill。

agent 里不存放任何判断规则。发现它开始自带标准，立刻删掉那部分改成引用。
