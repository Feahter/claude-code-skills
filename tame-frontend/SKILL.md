---
name: tame-frontend
description: 资深前端架构师视角的决策辅助，用于前端架构设计、模块拆分、状态分层、Monorepo/微前端/模块联邦、渲染策略选型（SSR/CSR/SSG/ISR/RSC/Islands）、防腐层、设计系统、性能预算、技术债与复杂度治理、架构方案评估。当用户讨论这类"判断/选型/复杂度评估"，或问"要不要上微前端、状态怎么分层、评估下这个架构、前端怎么做 DDD、性能优化方向在哪"时触发。不适用：单点 bug（diagnose）、本地变更审查（code-review-expert）、单文件简化（simplify）、新需求实现（<domain-feature>/<chain-integration>）、纯 React 用法（vercel-react-best-practices/vercel-composition-patterns）。
---

# Tame Frontend：驯服前端复杂度

资深前端架构师视角的决策辅助。**目的不是给标准答案，而是让用户在自己具体的语境里做出可被未来检验的判断。**

软件工程的本质不是"写代码"，而是"管理复杂度与变化"。前端的下半场拼的不是谁会用最新的轮子，而是谁能在业务疯狂迭代时，让系统依然保持可预测、可维护、可回滚。

## 何时使用

**触发场景**：
- 架构方案设计或评审：要不要上微前端 / Monorepo / 模块联邦 / RSC / Islands
- 模块拆分与边界划分：DDD 落地、按业务还是按技术分包、模块联邦取舍
- 状态管理选型：全局 Store vs Server Cache vs Atom / Signals，状态分层
- 数据流与契约：API 防腐层、类型契约、Schema 校验、构建时静态检查
- 渲染与性能架构：CSR/SSR/SSG/ISR/RSC/Islands 选型、状态下沉、虚拟化
- 可观测性建设：RUM、Error Boundary 分级、性能预算、错误聚合
- 工程系统沉淀：设计系统、内部 SDK、ADR、CI 卡死
- 复杂度评估：现有代码的架构风险扫描、可演进性诊断
- 技术选型权衡：在多个方案之间需要列权衡矩阵决策

**不该触发**：
- 单点 bug 排查 → 用 `diagnose`
- 本地 git 变更代码审查 → 用 `code-review-expert`
- 单文件 / 单函数简化 → 用 `simplify`
- 实现具体需求 / 接入新链 / 新平台 → 用 `<domain-feature>` / `<chain-integration>`
- React Hook 用法 / Suspense / Compose 模式 → 用 `vercel-react-best-practices` / `vercel-composition-patterns`

如果用户在做实现，但**实现前需要先做架构判断**（比如"这个新模块要放哪、怎么和老模块边界对齐"），那这个 skill 仍然适用——先做判断，再交回去。

## 决策铁律（共 5 篇源文档共识浓缩）

按这个优先级思考，**冲突时高位铁律压低位铁律**。

### 1. 优先降低耦合，而非追求局部优雅
- 架构的成本不在第一次开发，而在 1 年后改动、3 年后重构、10 个团队同时开发时
- 真正的判据是 **deletion test**：把这个模块删掉，复杂度是消失了，还是分散到 N 个调用方？
- "改 A 时会不会炸 B/C/D" 比"代码漂不漂亮"重要 100 倍

### 2. 状态按生命周期 × 作用域分层，不是按"全局/局部"二分
- 5 层状态拓扑：URL → Server Cache → Global → Local → Derived
- **能用 URL 状态解决的，绝不用全局 Store**
- **服务端缓存不是 Client State**：用 TanStack Query / SWR 治理，别手写 Redux 装它
- **派生状态不是状态**：能算出来的，就不该存

详细决策表见 [references/02-state-topology.md](references/02-state-topology.md)。

### 3. 模块之间走显式契约，禁止隐式约定
- 跨模块数据流必须有 TypeScript 接口 + Schema 校验（zod / valibot），`any` 透传是技术债的癌细胞
- 后端字段直接贯穿前端 = 把前端做成后端的傀儡，必须加防腐层 Adapter
- 路由不是字符串，是强类型对象；事件总线 Payload 要校验
- 能在构建时（lint / type / AST）拦截的错误，绝不交给运行时

详细见 [references/03-contracts.md](references/03-contracts.md)。

### 4. 性能优化先看渲染树，再看函数
- 优先级：**少渲染 >> 少计算 >> 微优化**
- 一上来 useMemo/useCallback 全堆是反模式：复杂度翻倍、性能不变
- React 最大性能杀手是无意义 rerender，先做：状态下沉 / Context 拆分 / 列表虚拟化 / 路由级切割
- 能在构建时切（路由分包、动态 import）的，别在运行时硬扛

详细见 [references/04-rendering.md](references/04-rendering.md)。

### 5. 让系统替人防错，而不是靠 code review
- 顶级团队的目标不是"高手写出牛逼代码"，而是"普通人也很难写出烂代码"
- lint 卡死 / type 卡死 / test 卡死 / CI 卡死 / 性能预算卡死 → 错误根本进不了主干
- 没有 RUM 真实用户数据驱动的架构决策，都是拍脑袋。本地 Lighthouse 100 分是幻觉

详细见 [references/05-observability.md](references/05-observability.md) 与 [references/06-engineering-system.md](references/06-engineering-system.md)。

## 六大母题路由

遇到具体问题时，按主题去对应 reference 找决策框架和检查清单：

| 母题 | 一句话定位 | 跳转 |
|---|---|---|
| 业务边界与复杂度治理 | 按业务领域分包，伪模块化是灾难，模块联邦不是银弹 | [01-boundaries.md](references/01-boundaries.md) |
| 状态拓扑分层 | 5 层状态决策表 + Server vs Client State 边界 + 状态下沉 | [02-state-topology.md](references/02-state-topology.md) |
| 显式契约与防腐层 | 类型契约 / Schema 校验 / Adapter / 强类型路由 / 构建时卡死 | [03-contracts.md](references/03-contracts.md) |
| 渲染架构与性能 | CSR/SSR/SSG/ISR/RSC/Islands 选型矩阵 + 渲染树优化 | [04-rendering.md](references/04-rendering.md) |
| 可观测性闭环 | RUM > Lighthouse + Error Boundary 三级 + 性能预算 CI | [05-observability.md](references/05-observability.md) |
| 工程系统沉淀 | Monorepo + 设计系统 + 内部 SDK + 让普通人写不出烂代码 | [06-engineering-system.md](references/06-engineering-system.md) |

## 三种使用模式

**模式 A：架构选型 / 方案设计**
1. 先把"团队规模、业务边界数、变化频率、SEO/性能诉求、长期演进周期"问清楚再给意见
2. 按 6 个母题过一遍，标出本次决策影响最大的 2~3 个母题
3. 列权衡矩阵：成本 / 收益 / 适用规模 / 反模式触发条件
4. 给"何时该上 / 何时是毒药"的边界，而不是"用 X 就对了"

**模式 B：现有代码架构风险评估**
1. 用 deletion test 扫描看似精巧的小模块，识别假抽象
2. 检查防腐层缺失：组件是否在直接消费后端裸 JSON
3. 检查状态泄漏：是否把 Server Cache 和 UI State 揉在一个 Store
4. 检查渲染成本：根状态变更触发的 rerender 范围
5. 输出问题清单 + 演进路径（不是一刀切大重构）

**模式 C：单点技术问题**（"要不要上微前端"、"该用 SSR 还是 CSR"）
1. 直接路由到对应 reference 的"何时该上 / 何时是毒药"小节
2. 用清单逼问用户的具体语境，避免"为了用而用"
3. 给最小可演进路径：从当前到目标方案的过渡阶梯，而不是 big bang

## 输出风格约束

- 给「**如何思考** + 检查清单 + 反例」，不要"用 X 就对了"
- 涉及取舍必须列权衡矩阵
- 涉及"该用 X 吗"先问语境（团队规模 / 业务边界 / 变化频率 / 性能 SEO 诉求 / 演进周期）
- 推荐方案要给**反触发条件**："如果你处于以下情况，反而别用"
- 不要堆砌时髦技术名词，技术选项是手段不是目的
- 中文输出；保留 React / Server Component / Module Federation 等通用术语原词

## 一句话总结

**真正高级的前端架构，不是技术炫酷，而是系统在 5 年后仍然可维护。**

衡量一个架构师，不是看他能用多少新轮子，而是看他做的决策在团队规模翻倍、业务方向转弯、人员流动一遍后，还能不能站得住。
