# 所有权矩阵：三方边界与防漂移

同一条判断标准在两个资产里各写一份，就会各自漂移，最后同一份测试套件按两边评会得出相反结论。所以规则只有一条：**任何一条规则只能有一个物理来源，其他地方只能引用它的路径或 ID。**

## 决策权矩阵

| 资产 | 独占决策权 | 明确不负责 |
|---|---|---|
| **test-strategist** | 风险识别与分级、优先级排序、处置决定（test/monitor/design-fix/explore/accept）、验证义务与 oracle 内容、可测试性缺口判定、不覆盖范围 | 选择器、断言 API、mock 方案、fixture 组织、分层归属、CI 配置、测试代码；已有测试的评分 |
| **playbook** | 测试写法与实现的单一事实源：分层归属（test-pyramid）、选择器优先级、断言规范、mocking、fixtures、flaky 归因与判定线、CI 分片与门禁配置、trace 定位、防腐指标 | 重新定义业务风险优先级；决定某风险是否值得测 |
| **e2e-test-quality** | 已有测试的评分卡、判级线、覆盖度算法、审核报告格式 | 自行发明风险并据此改评分；重算风险优先级；定义好写法 |

## 交叉地带的划法

这几处最容易两边都想写，逐条钉死：

| 交叉点 | 归谁 | 另一方能做什么 |
|---|---|---|
| **对抗性覆盖** | 「为什么该攻击这个面、风险多高」归 test-strategist；「用什么 payload / mock / 断言 / 稳定性策略」归 `playbook/references/adversarial-coverage.md` | test-strategist 只能引用 playbook 的维度名与文档路径，**不复制那 92 行** |
| **6 维技术清单 vs 业务风险四维** | 6 维（异常路径/角色/网络/边界数据/并发/a11y）是 playbook 的，回答「一个功能点从哪些角度测」；四维（影响面/变更频度/历史高发/可逆性）是 test-strategist 的，回答「先测哪个功能点」 | 两者正交，各自保留，不合并成一张表 |
| **覆盖度算法** | 公式（已验证 / 已识别阻断风险点）归 e2e-test-quality | test-strategist 提供「已识别风险点」这个分母的内容，但不定义公式与达标线 |
| **风险点穷举** | 穷举方法与失效模式清单归 test-strategist（`failure-modes-*.md`） | e2e-test-quality 评覆盖度时**引用** test-strategist 的风险台账作为分母来源，不自己再穷举一遍 |
| **可测试性反推** | 「测不动 → 源码病灶 → 反推动作」的信号表归 `playbook/references/source-pushback.md` | test-strategist 判定 `testability_gap` 时引用它，不复述信号表 |
| **oracle** | 判据的**内容**（判什么、判到什么程度）归 test-strategist 的 `references/oracle-patterns.md`；判据的**写法**（用哪个断言 API、web-first、怎么不 flaky）归 `playbook/references/assertions.md` | 分界线是：一句自然语言判据 vs 一行断言代码 |
| **分层归属** | 归 `playbook/references/test-pyramid.md` | test-strategist 的验证义务里**不写层级**。只有当风险本身限定了观察位置（如「必须在服务端验证，前端校验可被绕过」）才写 `layer_hint`，那是风险属性不是分层决定 |
| **flaky** | 判定线与归因归 `playbook/references/flaky.md` | test-strategist 遇到「测试不稳定」只做一件事：判断它是否影响某条风险的验证有效性 |

## 问法路由：用户这么问，该进哪个 skill

上面两张表管的是**规则写在哪**（决策权）。这一节管的是**用户开口时该选哪个 skill**（入口路由）——两者是同一套分工的内外两面，但解决的是不同问题：决策权矩阵只有被选中的 skill 才读得到，而选择发生在只看得见三方 description 的时刻。**入口路由错了，后面的决策权划得再细也用不上。**

### 第一问：手里的输入物是什么

不要按话题分流（"话题是测试"三方全中），按**手里已有什么**分流：

| 手里有 | 要产出 | 进 |
|---|---|---|
| 需求 / 代码变更 / 线上事故 —— 还没有测试 | 风险台账、优先级、验证义务、处置决定 | `test-strategist` |
| 待测代码 + 已知要测什么 | 测试文件、底座、CI 配置 | `playbook` |
| 已有测试代码 / 已有套件 | 分数、判级、审核报告 | `e2e-test-quality` |

### 歧义问法消歧表

这些问法三方都像自己的，逐条钉死。改动这张表必须同步三份 description：

| 用户实际会说 | 归谁 | 判据 |
|---|---|---|
| "这块怎么测" | **看输入物**：只有功能 / 需求，还不知道测什么 → `test-strategist`；已知测什么、问用什么写法落地 → `playbook` | 这是最高频的误路由源，不许任何一方用强措辞独占 |
| "该测哪一层 / 这个该放单测还是 E2E" | `playbook` | 分层归属是 `test-pyramid.md` 的独占决策权 |
| "覆盖够不够" | **看输入物**：有已有套件要评 → `e2e-test-quality`（覆盖度公式）；问该覆盖哪些风险点、哪些风险没人管 → `test-strategist`（风险穷举）；要配覆盖率工具 / 看 coverage 数字 → `playbook` | 三种问法在中文里几乎同形，必须靠输入物区分 |
| "这测试不稳定 / 一会儿过一会儿挂 / flaky" | `playbook` | 判定线与归因归 `flaky.md`，无例外 |
| "选择器该怎么写 / Page Object 怎么组织" | `playbook` | 写法单一事实源 |
| "这条 case 该不该留 / 这测试写得好不好" | `e2e-test-quality` | 已有测试 + 要评价 |
| "能不能不测 / 这风险能不能接受 / 时间不够先测哪个" | `test-strategist` | 处置决定与优先级 |
| "测了不少却没抓到 bug" | **看诉求**：要找哪些风险漏了 → `test-strategist`；要给现有套件打分定基线 → `e2e-test-quality` | 前者补台账，后者出分数 |
| "测试挂了 / 这条为什么失败" | `playbook`（`trace-debug.md`）；确认是应用 bug 不是测试写错 → `diagnose` | 都不是评分和风险问题 |

### description 层的同步纪律

description 是入口文本，**必须自包含**——选择时刻不会去读 references，所以它无法只写"见 ownership.md"。这是「绝不复制正文」的唯一例外，代价是三份 description 里各有一份精简分流句。约束：

- 三份 description 都要写**全三方**的分流，不能只单向指路。选择时刻是并行比较所有 description，单向指路的一方被先扫到时看不到完整分流。
- description 里只写"归谁 + 判据一句话"，不写具体规则内容（不写选择器优先级、不写评分线、不写风险维度）。
- 本表是事实源。改本表后同步三份 description，并跑 `bash ~/.claude/skills/test-strategist/scripts/check-routing-sync.sh` 校验没有一方漏写分流或写回越界词。

## 闭环协议

三方靠 `risk_id` 串起来，没有 ID 回执的「闭环」只是文档接力：

```
test-strategist              playbook                    e2e-test-quality
    │                            │                              │
    ├─ 策略包 ──────────────────▶│                              │
    │  disposition: test         ├─ 生成测试，注释或用例名        │
    │  的义务 + risk_id          │  回填 risk_id ───────────────▶│
    │                            │                              ├─ 按 risk_id 验收：
    ├─ monitor 项 ─▶ 监控        │                              │  义务是否真被实现
    ├─ design-fix ─▶ 独立任务    │                              │  实现得好不好（评分卡）
    ├─ explore ───▶ 人工         │                              │
    └─ accept ────▶ 记录决策人   │                              │
```

**回执要求**：playbook 落地的测试要能反查到 risk_id（写在用例名或紧邻注释里，形式由 playbook 定）。e2e-test-quality 审核时若发现某 P0/P1 风险没有对应实现，报「义务未落实」，但**不重新判断这个风险该不该是 P0**——那是 test-strategist 的决定，有异议走反馈而不是自行改判。

## 漂移自查

发现下面任一情况，说明已经开始漂移，立刻停下收敛：

- test-strategist 的某张卡里出现了具体断言代码、选择器写法、测试框架 API
- playbook 里出现了业务风险优先级判断（哪个功能更重要）
- e2e-test-quality 里出现了新的风险维度定义或新的失效模式清单
- 同一个概念（flaky 判定线、覆盖度公式、选择器优先级、风险四维）在两个资产里各有一份正文
- 三方对同一份产物给出相反结论

收敛方法：认定唯一来源，另一处删正文改成引用路径，并在提交说明里写清依据。**不要两边各留一份摘要**——摘要是漂移的温床，它一开始只是「简化版」，半年后变成第二套标准。
