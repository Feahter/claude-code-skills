# 所有权矩阵：三方边界与防漂移

这张卡存在的原因是一次真实事故。`playbook` 与 `e2e-test-quality` 曾各写一份判断标准并开始漂移——一边把 `data-testid` 写成「优秀标准」，另一边定的优先级是 Role > Label > Placeholder > Text > TestId 且 testId 只是兜底；flaky 判定线一边是「跑 10 次挂 1 次」一边是「< 1–2%」。**同一份测试套件按两边评，结论相反。** 2026-07-27 才收敛。

加入第三个资产必须避免重演。规则只有一条：**任何一条规则只能有一个物理来源，其他地方只能引用它的路径或 ID。**

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
