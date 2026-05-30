---
name: playbook
description: |
  Playwright E2E 自动化测试工作流引擎：探测项目栈 → 规划测试用例 → 生成 .spec.ts → 校验稳定性，全程脚本驱动的确定性流程。当用户要给前端项目加 Playwright/E2E 测试、写测试用例、排查 flaky 测试、上 CI、做覆盖率审计时，必须用本 skill 而不是凭经验自由发挥。
  触发关键词：playwright、E2E、e2e、end-to-end、自动化测试、UI 测试、集成测试、测试覆盖、flaky、storageState、fixture、trace、codegen、playwright.config、testid、page object。
  不适用：单元测试（Vitest/Jest/Mocha）、组件级隔离测试、移动端原生测试（Appium/Detox）。
---

# playbook —— Playwright E2E 工作流引擎

## 角色定位

资深前端测试工程师视角。**流程稳定 > 灵活创新**：每一步用脚本和模板兜底，把"现场判断意图"压到最低。生成的代码评审者看不出是 AI 写的。

## 六条铁律（违反即失败）

1. **测业务行为，不测 UI 细节**——spec 描述"admin 能审批退款"，不是"点这个按钮再点那个"。UI 操作封装到 `tests/actions/` 业务动作里。详见 `references/architecture.md`。
2. **测用户能感知的，不测组件内部**——断言用户看见什么、能做什么；不测 className、不测 store、不测 hook。
3. **选择器优先级 Role > Label > Text > TestId > CSS**。绝不用 `nth-child` / `xpath` / 动态 className（如 `.css-xxhash`）——这些选择器在 UI 重构时第一个挂。
4. **永远 web-first 断言，禁 `waitForTimeout`**。`expect(locator).toBeVisible()` 自带智能重试；`page.waitForTimeout(1000)` 是 flaky 之源。
5. **测试隔离**：每条用例独立数据 + 独立 `storageState`。共享状态会让"单跑过、批量挂"。
6. **流程稳定 > 灵活**：先跑脚本看结果，再决定要不要发挥。脚本说项目没装 Playwright，就老老实实搭建，不要上手就写 spec。

## 工作流：四阶段（必读）

```
┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐
│ 1. 探测   │──▶│ 2. 规划   │──▶│ 3. 生成   │──▶│ 4. 校验   │
└──────────┘   └──────────┘   └──────────┘   └──────────┘
detect-project  决策表          gen-test       validate-test
project.json    test-plan.md    *.spec.ts      report.md
```

每阶段产出一个**确定性工件**到 `.playbook/`，工件存在则跳过该阶段（幂等可重跑）。**不要跳阶段**——上一阶段的工件是下一阶段的输入。

> 幂等的前提是工件没过期。**换了 framework / 包管理器 / UI 库，或升级了 Playwright 后，先 `rm -rf .playbook/` 再重跑**——否则 `project.json` 会停在旧栈，后续决策全基于过期信息。

### 阶段 1：探测（Detect）

```bash
bash ~/.claude/skills/playbook/scripts/detect-project.sh > .playbook/project.json
```

产出 `.playbook/project.json`，字段固定：
- `framework`：next / vite / nuxt / remix / cra / astro / vue-cli / unknown
- `language`：ts / js
- `packageManager`：pnpm / npm / yarn / bun
- `hasPlaywright`、`configPath`、`testDir`、`baseURL`
- `existingSelectors`：项目里已经在用的选择器风格（data-testid / role / css）
- `uiLib`：antd / mui / shadcn / element-plus / unknown

脚本异常 → 改读 `references/project-detect.md` 用人工清单兜底。

### 阶段 2：规划（Plan）

读 `.playbook/project.json` + 用户的测试目标（哪些页面、哪些流程），**第一步先过测试金字塔判断**（详见 `references/architecture.md`）：

- 流程级目标（登录→下单→支付）→ E2E ✅ 继续
- 逻辑级目标（金额计算、表单校验）→ ❌ 推回让用户写 unit
- 单组件级目标（弹窗动画、tooltip）→ ❌ 推回让用户写 component test

通过金字塔判断后，按下表挑路径，产出 `.playbook/test-plan.md`：

| 输入条件 | 决策 | 该读 |
|---|---|---|
| `hasPlaywright === false` | 先搭建，按 framework 选配方 | `references/setup-recipes.md` |
| 用户目标含登录 | 必须 auth fixture + storageState | `examples/auth.fixture.ts` |
| 用户目标含表单提交 | 用 form-submit 模板 | `templates/form-submit.spec.ts.tmpl` |
| 用户目标含跨页流程 / 多角色 | 用业务 DSL + 派 agent 对抗覆盖 | `references/architecture.md` + `references/adversarial-coverage.md` |
| 用户目标含权限边界（角色 A 能、B 不能） | 用 permission-check 模板 | `templates/permission-check.spec.ts.tmpl` |
| `existingSelectors` 含 css/xpath | 警告并给迁移片段 | `references/selectors.md` |
| `uiLib` 是 antd/mui/element-plus | 选择器加库特定提示 | `references/selectors.md` |
| 用户提到"接口 mock"/"假数据" | 三层 Mock 决策 | `references/mocking.md` |
| 用户提到"性能预算"/"bundle 大小"/"a11y 守护" | 架构契约（可选） | `references/contracts.md` |
| 失败需要后端配合定位 | traceId 串联前后端日志 | `references/observability.md` |

`test-plan.md` 字段固定：**目标 / 金字塔判断 / 用例清单 / 业务动作清单 / 选择器策略 / 数据准备 / Mock 策略 / 是否派 agent**。

### 阶段 3：生成（Generate）

对 `test-plan.md` 中每条用例：

```bash
bash ~/.claude/skills/playbook/scripts/gen-test.sh \
  --template <happy-path|auth-required|form-submit|api-mock|visual-regression|business-dsl|permission-check> \
  --out tests/<file>.spec.ts \
  --name "<用例标题>" \
  --url <目标路径，如 /orders> \
  --api <API mock 匹配 pattern，仅 api-mock 用>
```

`--name/--url/--api` 的取值来自 `test-plan.md` 中**当前这条用例**：标题填 `--name`、目标页面填 `--url`、要 mock 的接口填 `--api`。脚本只认这几个参数（`--help` 可查全），**不接收 `--plan`/`--case`**——按用例逐条调用，一条用例生成一个 spec 文件。

**模板选型**：跨页/多步流程 → `business-dsl`（spec 调业务动作，UI 操作藏在 `tests/actions/`，见 `references/architecture.md` + `examples/actions/`）；单页简单流程 → `happy-path` / `form-submit`；多角色权限边界（admin 能进、guest 被挡）→ `permission-check`。

脚本内部：套模板 + 占位符替换 + 选择器规则注入。**LLM 不要自由写 spec**，永远先选模板。如果 dev server 在跑，可以辅助 `npx playwright codegen <url>` 抓真实 selector。

生成的 spec 必须满足：
- 选择器走 `references/selectors.md` 优先级
- 断言走 `references/assertions.md` web-first 清单
- 禁止出现 `waitForTimeout` / `:nth-child` / `xpath=` / `page.wait(\d+)`

模板里的选择器是占位示例，**gen-test 生成后必须依 `project.json` 的 `uiLib` 字段，对照 `references/selectors.md`「UI 库特定坑」逐处校准**（如 antd 按钮文本走正则、MUI 全走 Role、Modal 用 `getByRole('dialog')` 进作用域）——这一步是模板通用骨架落到具体 UI 库的关键，跳过会生成"看着对、跑起来抓不到元素"的选择器。

### 阶段 4：校验（Verify）

```bash
bash ~/.claude/skills/playbook/scripts/validate-test.sh tests/<file>.spec.ts
```

**静态检查**（grep/AST，确定性，无 LLM 判断）：
- 含 `waitForTimeout` / `page.waitForTimeout(\d+)` → ❌
- 含 `:nth-child` / `xpath=` → ❌
- 缺 `expect(...).toBe*/toHave*` web-first 断言 → ❌
- selector 含动态 className（`.css-[a-z0-9]+`）→ ⚠️

**动态检查**：
- `npx playwright test <file> --reporter=line --max-failures=1`
- 跑通过但 < 1s → ⚠️ 可能是空跑，没真的等到 UI
- 跑 3 次看是否 flaky（≥ 1 次失败）→ 进 `references/flaky.md` 流程
- 失败 → 自动开 trace，引用 `references/trace-debug.md` 5 分钟定位法

产出 `.playbook/report.md`：每条用例 ✅/❌/⚠️，失败给具体修复点。**不要凭直觉宣布"修好了"，以 report.md 为准。**

### 阶段 4.5：对抗覆盖（仅复杂场景触发）

触发条件（任一即可）：跨页流程 / 多角色（admin+user） / 高风险路径（支付、认证、数据写入）。

按 `references/adversarial-coverage.md` 的 6 维度清单（异常路径 / 角色 / 网络异常 / 边界数据 / 并发 / a11y），**按名调用 `dispatching-parallel-agents` skill 派子 agent**（按 skill 名触发，无需文件路径），每 agent 负责一个维度。子 agent 产物回流到 `.playbook/test-plan.md` → 再走阶段 3+4。

**降级**：若 `dispatching-parallel-agents` 不可用，不要空转——退化为**单 agent 顺序自检**：先跑 `coverage-audit.sh` 看 6 维度当前覆盖差距，再对照 `references/adversarial-coverage.md` 里现成的 agent prompt 模板，逐维度补用例清单回流 `test-plan.md`。结果一致，只是不并行。

**默认不派 agent**——只在上面三个明确触发条件下才派，避免成本浪费。

## 决策跳转表

**第一次用本 skill，先按序读这 3 篇打底**（其余按需查表）：`architecture.md`（业务 DSL 分层 + 测试金字塔，决定测什么、怎么分层）→ `selectors.md`（选择器优先级，决定怎么定位）→ `assertions.md`（web-first 断言，决定怎么验证）。这三篇是六条铁律的展开，读完即可上手；下表按场景补查。

| 当前情景 | 该读 |
|---|---|
| 不知道项目能不能直接装 Playwright | `references/project-detect.md` |
| 项目栈对应的搭建配方 | `references/setup-recipes.md` |
| 用例代码组织 / 业务 DSL 分层 / 测试金字塔判断 | `references/architecture.md` |
| 选 selector / 现有项目用了 css selector | `references/selectors.md` |
| 要不要写 POM、怎么组织 fixture | `references/fixtures.md` |
| 要写什么断言、双模态断言抓隐形 bug | `references/assertions.md` |
| API/接口怎么 Mock / HAR 录制回放 / MSW 共享 | `references/mocking.md` |
| 用例失败要排查 root cause | `references/trace-debug.md` |
| 失败时串联前后端日志（traceId） | `references/observability.md` |
| 用例时不时挂（flaky） | `references/flaky.md` |
| CI 太慢 / 没上 CI / 要分片 | `references/ci.md` |
| 要做覆盖率审计、对抗测试 | `references/adversarial-coverage.md` |
| bundle 大小 / 外部域名 / a11y / 性能预算守护 | `references/contracts.md` |

## 黑盒脚本清单

所有脚本在 `~/.claude/skills/playbook/scripts/`，**支持 `--help`，禁止读源码**——把它们当编译过的命令用：

| 脚本 | 用途 |
|---|---|
| `detect-project.sh` | 探测项目栈，输出 JSON |
| `scaffold.sh` | 按 framework 一键搭建 Playwright 配置 |
| `gen-test.sh` | 按模板生成 .spec.ts |
| `validate-test.sh` | 静态 + 动态双检 |
| `coverage-audit.sh` | 列覆盖维度差距，辅助阶段 4.5 |

## 提交前 checklist（强制）

- [ ] 跑过 `validate-test.sh`，`.playbook/report.md` 全 ✅（⚠️ 至少有解释）
- [ ] 用例独立可单跑：`npx playwright test <file> --workers=1`
- [ ] spec 是业务语义而非 UI 操作（多步流程必须走 `tests/actions/`）
- [ ] 含登录的流程已配 `storageState`
- [ ] 用例数 ≥ 5 时 CI 已配分片（≥ 2 shards）
- [ ] 选择器全部语义优先级，无 `nth-child`/`xpath`/动态 className
- [ ] 用例描述不含 `validation/format/util/hover/style` 等 unit/component 该测的关键字

## 触发与边界

**触发**：用户消息含 playwright / E2E / 自动化测试 / UI 测试 / 测试覆盖 / flaky / storageState / fixture / trace / codegen / page object 任一关键词，或要求"给项目加测试"。

**不适用**：
- 单元测试（Vitest/Jest/Mocha）→ 让用户自己写或用其他 skill
- 组件级隔离测试（Storybook play / Cypress component）
- 移动端原生（Appium / Detox）
- 性能测试（用 `performance-optimizer` skill）
- 仅"跑一下 dev server 看页面" → 用 `webapp-testing` skill

## 与其他 skill 的协作

- `webapp-testing`：阶段 4 校验失败时，调用它跑 dev server 抓页面状态
- `dispatching-parallel-agents`：阶段 4.5 派 agent 时遵循其方法论
- `verify` / `run`：用户需要手动看效果时调用
- `code-review-expert`：测试代码写完后让它审一遍
