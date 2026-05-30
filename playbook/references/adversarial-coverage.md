# 对抗覆盖：何时派 agent，怎么派

## 触发条件（任一即可）

- 用户目标含**跨页流程**（注册 → 登录 → 配置 → 第一次操作）
- **多角色**（admin / user / guest）权限边界
- **高风险路径**（支付、认证、写入数据库、调用链上交易）
- 用户明确要求"全面覆盖"或"对抗测试"

不在这些场景下默认**不派 agent**——成本高，价值低。

## 6 维度覆盖清单

测试 happy-path 之后，按下面 6 维度查漏：

| 维度 | 检查点 | 例 |
|---|---|---|
| **异常路径** | 接口 4xx/5xx、超时、断网 | 登录密码错误、订单创建失败 |
| **角色权限** | 不同角色访问受限页面 | guest 访问 admin 页应跳转 |
| **网络异常** | 慢网、丢包、重试 | 3G 模拟下能否完成结账 |
| **边界数据** | 空、超长、特殊字符、多语言 | 用户名 256 字符、emoji、SQL 注入字符 |
| **并发** | 同一用户多 tab、多用户操作同资源 | A 删了 B 正在编辑的文档 |
| **a11y** | 键盘导航、screen reader、对比度 | tab 顺序、aria-label 正确 |

## 派 agent 流程

调用 `dispatching-parallel-agents` skill 的方法论。每个维度派 1 个子 agent，并行：

### Agent prompt 模板

```
你是 Playwright 测试覆盖专家，负责"<维度>"维度。

任务：基于现有测试 .playbook/test-plan.md（已附），列出该维度下当前缺失的测试用例，
每条用例给出：
- 用例名（中文，描述用户行为）
- 触发条件（怎么进入这个场景）
- 预期结果
- 推荐模板（happy-path | auth-required | form-submit | api-mock | visual-regression）
- 是否需要新增 mock / fixture

不要写代码，只列用例清单（markdown 表格）。
不要重复 test-plan.md 已有的用例。
按用户价值排序，列前 5-8 条即可。

参考文档：
- selectors.md（选择器规则）
- mocking.md（异常路径 mock 模式）
- assertions.md（断言模式）
```

### 派发示例

```
Agent 1：异常路径（dispatching-parallel-agents 子任务）
Agent 2：角色权限
Agent 3：网络异常
Agent 4：边界数据
Agent 5：并发
Agent 6：a11y
```

并行返回后，把每个 agent 输出的用例清单**合并到 `.playbook/test-plan.md`**（标记 `[adversarial]` 前缀），然后回到主流程阶段 3+4。

## 覆盖审计脚本

```bash
bash ~/.claude/skills/playbook/scripts/coverage-audit.sh
```

输出当前 `.playbook/test-plan.md` 在 6 维度上的覆盖度（每维有几条用例），辅助决策"还该不该派 agent"。

## 何时停止扩展

不要无限补用例。停止条件（任一）：

- 6 维度每维 ≥ 3 条用例
- 增加用例的 ROI 已经低（用例总数 > 100 但新发现 bug 率 < 1%）
- 用户明确说"够了"

测试不是越多越好——**关键路径深，边角情况浅**。

## agent 输出质量要求

派出去的 agent 容易写出"听起来很对但实际跑不通"的用例。回流时检查：

- [ ] 用例触发条件具体、可执行（不是"用户在某种情况下"）
- [ ] 预期结果可验证（不是"系统应正常工作"）
- [ ] 标注了模板，方便阶段 3 套
- [ ] 没和 test-plan.md 已有用例重复

不达标的用例**直接丢回 agent 改**，不要带病合并。
