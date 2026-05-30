---
name: playbook
description: |
  前端自动化测试全层引擎：掌握单元 / 集成 / E2E 全套方法论，四阶段脚本驱动（探测项目栈 → 规划分层用例 → 生成测试 → 校验稳定性）的确定性流程。当用户要给前端项目加测试、写测试用例、判断该测哪一层、排查 flaky、上 CI、做覆盖率审计、或问"这块怎么测"时，必须用本 skill 而不是凭经验自由发挥。
  触发关键词：playwright、E2E、e2e、end-to-end、自动化测试、UI 测试、集成测试、单元测试、单测、vitest、jest、testing-library、msw、测试金字塔、测试覆盖、覆盖率、coverage、flaky、storageState、fixture、trace、codegen、playwright.config、testid、page object。
  不适用：移动端原生测试（Appium/Detox）、性能测试（用 performance-optimizer）。
---

# playbook —— 前端自动化测试全层引擎

## 角色定位

资深前端测试工程师视角，掌握**全套前端自动化测试经验与技巧**，不局限单一项目。**流程稳定 > 灵活创新**：每一步用脚本和模板兜底，把"现场判断意图"压到最低。生成的代码评审者看不出是 AI 写的。

playbook 三位一体：(1) **测试方法论权威**——references 覆盖单元/集成/E2E 全套技巧；(2) **全层执行引擎**——四阶段对单元/集成/E2E 分层分流、自带通用生成；(3) **驱动引擎**——项目有专属测试 skill / 标杆时，由本 skill 的方法论与四阶段驱动它因地制宜生成，无则用通用模板兜底（见末尾「与其他 skill 协作」）。

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
>
> 旧版 `project.json` 若缺 `unitTesting` 字段（全层引擎前生成的），单测/集成规划会读不到单测底座信息，需重跑 detect。

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

读 `.playbook/project.json` + 用户的测试目标（哪些页面、哪些流程），**第一步先过测试金字塔判断**（分层决策树详见 `references/test-pyramid.md`，E2E 层细节见 `references/architecture.md`）。playbook 是全层引擎，逻辑级/数据流级**不再推回甩手，而是落进分层 backlog 由对应层承接**：

- 流程级目标（登录→下单→支付）→ **E2E** ✅ 走下面四阶段
- 逻辑级目标（金额计算、表单校验）→ **单元**，进 backlog（见下「分层承接」）
- 数据流目标（组件→hook→接口→渲染）→ **集成**，进 backlog
- 单组件视觉细节（弹窗动画、tooltip）→ component / visual-regression

一次迭代常跨多层，不是三选一。产出的 `.playbook/test-plan.md` 顶部先列**分层 backlog**：

| 被测对象 | 拟定层级 | 理由 | 承接方式 |
|---|---|---|---|
| `calcPrice()` | unit | 纯逻辑无 DOM | gen-unit-test unit-pure / 项目标杆 |
| `useOrderPanel()` | unit(hook) | hook 行为 | gen-unit-test hook |
| `<OrderList/>` | integration | 组件+数据流 | gen-unit-test component-integration / 项目标杆 |
| 登录→下单→支付 | e2e | 跨页赚钱路径 | 本 skill 四阶段 + business-dsl |

**分层承接**（阶段 3/4 据此分流）：unit/integration 行 → 若项目有专属测试 skill / 标杆则委托它照标杆生成，否则 `gen-unit-test.sh` 通用模板兜底（底座缺失先 `scaffold-unit.sh`）；e2e 行 → 继续走下面四阶段。

E2E 层按下表挑路径（纯 E2E 任务时 test-plan 退化成与原来一致的结构）：

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

`test-plan.md` 字段固定：**目标 / 分层 backlog / 金字塔判断 / 用例清单 / 业务动作清单 / 选择器策略 / 数据准备 / Mock 策略 / 是否派 agent**（用例清单及之后字段针对 E2E 层；unit/integration 层在 backlog 里标注被测模块路径 + import 即可）。

### 阶段 3：生成（Generate）

**先按 backlog 层级分流**：unit/integration 行 → 项目有专属 skill/标杆则委托它照标杆生成，否则 `bash scripts/gen-unit-test.sh --template <unit-pure|hook|component-integration> --out <path> --module <import路径> ...`（`--help` 查全）；e2e 行 → 走下面 Playwright 生成。

对 `test-plan.md` 中每条 **E2E** 用例：

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

**按层分流**：unit/integration 用 `bash scripts/validate-unit.sh <test-file>`（静态查 Math.random/真实等待/mock 子组件等单测反模式 + `vitest run --coverage`）；e2e 用下面的 `validate-test.sh`。两者结果统一回流 `.playbook/report.md`，每条标层级。

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

**第一次用本 skill，先读 `test-pyramid.md` 定层**（这次该测单元/集成还是 E2E）。判定 E2E 后，再按序读 `architecture.md`（业务 DSL 分层）→ `selectors.md`（选择器优先级）→ `assertions.md`（web-first 断言）这 3 篇 E2E 打底；判定单元/集成则读 `unit-integration.md`。下表按场景补查。

| 当前情景 | 该读 |
|---|---|
| 拿到任务先判断该测哪一层（单元/集成/E2E） | `references/test-pyramid.md` |
| 写单元/集成测试（test.each / renderHook / RTL / Mock 边界） | `references/unit-integration.md` |
| 测试老挂/改文案就红/越改越脆（防腐） | `references/anti-rot.md` |
| 测写不出 / 必须 mock 一大坨 / 加载就崩（反推源码） | `references/source-pushback.md` |
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
| `detect-project.sh` | 探测项目栈（含单测底座 `unitTesting`），输出 JSON |
| `scaffold.sh` | 按 framework 一键搭建 Playwright 配置 |
| `gen-test.sh` | 按模板生成 .spec.ts（E2E） |
| `validate-test.sh` | E2E 静态 + 动态双检 |
| `coverage-audit.sh` | 列覆盖维度差距，辅助阶段 4.5 |
| `scaffold-unit.sh` | 一键搭建 Vitest 单测/集成底座（config + test-utils + msw） |
| `gen-unit-test.sh` | 按模板生成 .test.ts/.test.tsx（单元/集成） |
| `validate-unit.sh` | 单测/集成静态 + 动态双检（vitest run --coverage） |

## 提交前 checklist（强制）

- [ ] 跑过 `validate-test.sh`，`.playbook/report.md` 全 ✅（⚠️ 至少有解释）
- [ ] 用例独立可单跑：`npx playwright test <file> --workers=1`
- [ ] spec 是业务语义而非 UI 操作（多步流程必须走 `tests/actions/`）
- [ ] 含登录的流程已配 `storageState`
- [ ] 用例数 ≥ 5 时 CI 已配分片（≥ 2 shards）
- [ ] 选择器全部语义优先级，无 `nth-child`/`xpath`/动态 className
- [ ] 用例描述不含 `validation/format/util/hover/style` 等 unit/component 该测的关键字

**单元 / 集成层（若 backlog 含该层）**：
- [ ] 已过 `test-pyramid.md` 分层判断（被测对象确实该落这层，没把逻辑硬塞 E2E）
- [ ] 跑过 `validate-unit.sh`：无 `Math.random`/真实等待，未 mock 子组件
- [ ] MSW 在 HTTP 边界拦截，fixture 对齐后端响应形态；快照（若有）< 50 行 + 配显式断言
- [ ] 覆盖率对照 `test-pyramid.md` 分层门限（关注分支覆盖，非只看行）

## 触发与边界

**触发**：用户消息含 playwright / E2E / 自动化测试 / UI 测试 / 单元测试 / 单测 / 集成测试 / vitest / jest / testing-library / msw / 测试金字塔 / 测试覆盖 / 覆盖率 / flaky / storageState / fixture / trace / codegen / page object 任一关键词，或要求"给项目加测试"、问"这块怎么测"。

**承接范围**：
- 单元测试（Vitest/Jest）+ 集成测试（Testing Library + MSW）→ 本 skill 给方法论 + 分层判断 + 通用生成；项目有专属 skill/标杆则驱动它因地制宜生成
- E2E（Playwright）→ 四阶段全流程

**不适用**：
- 组件级隔离测试（Storybook play / Cypress component）
- 移动端原生（Appium / Detox）
- 性能测试（用 `performance-optimizer` skill）
- 仅"跑一下 dev server 看页面" → 用 `webapp-testing` skill

## 与其他 skill 的协作

**驱动协议（playbook 是上游引擎）**：playbook 提供测试方法论 + 四阶段 + 分层判断；项目级全层测试生成 skill（如某项目的 `generate-tests`）是 playbook 驱动下、在具体技术栈因地制宜的专属下游——它照本项目的测试标杆 / `test-utils` 基建生成单元/集成测试，并把 E2E 委托回 playbook。二者通过金字塔分层与 `.playbook/` 四阶段工件解耦：
- **项目有专属测试 skill / 标杆** → 阶段 3 的 unit/integration 行委托它照标杆生成（命名、打桩风格贴合项目），playbook 只给方法论与层级判断。
- **裸项目（无专属 skill）** → playbook 用 `gen-unit-test.sh` 通用模板兜底，`scaffold-unit.sh` 搭底座，任何项目都能直接被驱动生成全层测试。

其他协作：
- `webapp-testing`：阶段 4 校验失败时，调用它跑 dev server 抓页面状态
- `dispatching-parallel-agents`：阶段 4.5 派 agent 时遵循其方法论
- `verify` / `run`：用户需要手动看效果时调用
- `code-review-expert`：测试代码写完后让它审一遍
