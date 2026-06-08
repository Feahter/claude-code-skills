# 工程系统沉淀

## 核心命题

**真正顶级的人，写代码时间反而越来越少——他在构建"生产代码的系统"。**

顶级团队的目标不是"高手写出牛逼代码"，而是 **"普通人也很难写出烂代码"**。靠系统替人防错，不靠 code review。

> 人一定会犯错，所以不要依赖"人"，要让系统自动防错。

普通团队靠 code review 保质量。顶级团队直接：lint 卡死 / type 卡死 / test 卡死 / CI 卡死。**错误根本进不了主干。**

## 工程系统包含什么

- **代码层**：lint / format / type check / test
- **构建层**：bundler / tree-shaking / code-gen / 性能预算
- **CI/CD**：自动化测试 / 构建 / 部署 / 灰度
- **可观测性**：监控 / 告警 / 日志 / Session Replay（详见 [05-observability.md](05-observability.md)）
- **基础设施层**：脚手架 / 内部 SDK / 设计系统 / Monorepo 工具链
- **决策层**：ADR（Architecture Decision Record）/ 性能预算 / Feature Flags

## Monorepo：组织代码的现代方式

当业务扩展到 Web、H5、小程序、多个后台管理系统时，最忌讳"各写各的"。复制粘贴代码是架构腐烂的开始。

### 推荐栈

- **包管理**：`pnpm workspaces` / `bun workspaces`（不要再用 yarn workspaces）
- **构建编排**：`Turborepo` 或 `Nx`，靠缓存让 CI 时间砍半
- **变更管理**：`Changesets` 管版本

### 目录编排

```
my-app/
├── apps/
│   ├── web/                # 主站
│   ├── admin/              # 后台
│   └── mobile/             # H5
├── packages/
│   ├── ui/                 # 设计系统组件（基于 Radix / HeadlessUI 封装）
│   ├── shared/             # 业务工具、Adapter、常量
│   ├── sdk/                # 内部 SDK：鉴权、权限、i18n、日志
│   ├── config/             # 共享 ESLint / TS / Prettier 配置
│   └── design-tokens/      # 设计令牌
└── turbo.json
```

### 何时该上 Monorepo

- 团队 ≥ 5 人或多个独立 app
- 有需要共享的组件库 / 工具 / 配置
- 想统一规范（ESLint / TS / Prettier）

### 何时不该上

- 单 app、单团队、< 3 人 → 单仓单 app 就够了，Monorepo 是负担

### 与微前端的关系

**先做 Monorepo（逻辑解耦），再做微前端（部署解耦）。** 跳过 Monorepo 直接上微前端是 90% 团队后悔的决策。详见 [01-boundaries.md](01-boundaries.md)。

## 设计系统（不是组件库）

**不要直接用 Ant Design / MUI 糊业务**。要建造自己的"组件平台层"。

### 三层结构

```
┌─────────────────────────────────────┐
│ 业务组件层（domain components）       │  ← 注入业务逻辑，限当前项目
├─────────────────────────────────────┤
│ 原子组件层（@company/ui）             │  ← 严格遵循 WAI-ARIA，无业务逻辑
├─────────────────────────────────────┤
│ 设计令牌层（@company/design-tokens） │  ← 颜色、间距、字号、阴影等
└─────────────────────────────────────┘
```

### 设计令牌（Design Tokens）

把所有视觉原子（颜色、间距、阴影、字号）定义为平台无关的 JSON / YAML，通过 `Style Dictionary` / `Tokens Studio` 自动生成：

- CSS Custom Properties
- Tailwind config
- iOS / Android 变量

一次调整，全平台生效。

```json
{
  "color": {
    "brand": { "primary": { "value": "#FF5722" } },
    "text":  { "primary": { "value": "{color.gray.900}" } }
  },
  "spacing": {
    "sm": { "value": "8px" },
    "md": { "value": "16px" }
  }
}
```

### 原子组件层规则

- 严格遵循 WAI-ARIA（基于 Radix / HeadlessUI / Ark UI 封装）
- 无任何业务逻辑
- 强制接受 `className` 和 `...rest` props，支持自定义
- Storybook 文档化
- Chromatic / Playwright 视觉回归

### 业务组件层规则

- 注入领域行为
- 不在原子层重复实现 UI
- 限当前 app 内使用

## 内部 SDK（基础设施 SDK）

把鉴权、权限码、国际化、日志、路由守卫、缓存策略包装成统一的 `@company/sdk`：

```ts
import { auth, i18n, log, router, http } from '@company/sdk';

// 任何新建子应用必须依赖它
```

收益：10 个团队产出的页面，行为一致、安全基线一致、升级方式一致。

这看起来前期成本巨大，但它会在团队扩张到 20 人以上时，**成为阻止混沌工程的唯一堤坝**——也是架构师留给团队最持久的遗产。

## ADR（Architecture Decision Record）

任何重大架构决策必须写 ADR：

```md
# ADR-0042: 状态管理选用 TanStack Query + Jotai

## Status
Accepted (2026-03-15)

## Context
我们之前用 Redux Toolkit 管理服务端缓存，导致 ...

## Decision
- 服务端缓存全部迁到 TanStack Query
- 客户端共享状态用 Jotai
- 已有 Redux 代码渐进式替换

## Consequences
✅ ...
❌ ...

## Alternatives Considered
- SWR：...
- Redux Toolkit Query：...
```

放 `docs/adr/` 目录，按编号递增。

收益：
- 新人 onboarding 知道历史决策原因
- 半年后想"为什么当时选 X" 有答案
- 重构时知道哪些决策可以改、哪些是硬约束

## CI 卡死流水线

```yaml
# 必备
- lint (eslint)
- format (prettier)
- type-check (tsc --noEmit)
- unit-test (vitest)
- build (turbo build)

# 推荐
- size-limit / bundlesize
- lighthouse-ci
- chromatic（视觉回归）
- e2e（playwright，关键路径）
- changeset 检查（PR 必须带 changelog）
```

任何一项失败 = PR 不可合并。

## Feature Flags（功能开关）

新功能默认在 Feature Flag 后面：

- 灰度发布
- A/B 实验
- 出问题快速回滚（不发新版本）
- 不同租户 / 用户群差异化

工具：LaunchDarkly / Unleash / GrowthBook / 自建。

## 自动化质量门 + AI 闭环

2026 年的工程系统标配：
- **AI 辅助 review**：用 Claude / Cursor 自动看 PR 给反馈
- **AI 生成 boilerplate**：脚手架命令直接生成符合规范的新模块
- **AI 写测试**：基于实现自动补单测
- **人类专注架构决策、ADR、跨模块设计**

## 检查清单

- [ ] 团队规模 ≥ 5 人 / 多个 app，是否上了 Monorepo？
- [ ] 是用 Ant Design 直接糊业务，还是有自己的设计令牌 + 原子组件？
- [ ] 鉴权、i18n、日志这些基础能力，是每个 app 自己写一遍，还是统一 SDK？
- [ ] 重大架构决策有没有 ADR 文档？
- [ ] CI 是否卡 lint / type / test / size 预算？还是靠 code review？
- [ ] 新功能是否走 Feature Flag？还是直接发线上？
- [ ] PR 是否要求 Changeset？
- [ ] 视觉回归是否自动化（Chromatic）？
- [ ] e2e 是否覆盖关键路径？
- [ ] 团队有没有"普通人也很难写出烂代码"的具体机制？

## 反例与代价

| 反模式 | 代价 |
|---|---|
| 用 Ant Design 直接糊业务 | UI 一致性差，主题变更全站重做，无法跨平台 |
| 多 app 各写各的鉴权 / i18n / 日志 | 安全基线分散，升级要改 N 个地方 |
| 没有 ADR 文档 | 新人不知道为什么这么做，重构永远怕踩雷 |
| 没有 lint / type 卡死，靠 code review | 烂代码必然进主干 |
| 没有性能预算 | 性能慢慢退化没人发现 |
| 没有 Feature Flag，直接发线上 | 出问题只能回滚版本，影响其他功能 |
| 想一步到位建完整工程系统 | 永远建不完，团队反弹 |
| 工程系统建好后没人维护 | 配置过期，规则失效，不如不建 |

## 决策路径（用户问"我们怎么开始建工程系统"）

按优先级分阶段：

**第一阶段（团队 < 5 人）**
1. ESLint + Prettier + TS strict + Husky pre-commit
2. CI 卡 lint / type / test
3. 简单的 GitHub Actions 自动构建部署

**第二阶段（团队 5~10 人 / 多 app）**
4. 上 Monorepo（pnpm + Turborepo）
5. 抽取设计令牌 + 原子组件库
6. 写 ADR 模板，开始记录决策
7. CI 加 size-limit / Lighthouse CI

**第三阶段（团队 10+ 人）**
8. 内部 SDK（鉴权 / i18n / 日志统一）
9. Feature Flags
10. 视觉回归（Chromatic）
11. e2e（Playwright）覆盖关键路径
12. RUM 接入（详见 [05-observability.md](05-observability.md)）

**第四阶段（团队 20+ 人 / 多业务线）**
13. 微前端 / 模块联邦（如果业务真的独立了）
14. 内部脚手架 / codegen
15. 多团队治理机制（ADR review、平台委员会）

## 工程系统的终极标志

- 写代码的人越来越少，建系统的人越来越多
- 普通工程师也能产出符合规范的代码
- 架构变更通过工具一次推平，不靠"大家自觉改"
- 5 年后系统依然可维护

## 延伸阅读

- [01-boundaries.md](01-boundaries.md)：Monorepo / 微前端的边界判断
- [03-contracts.md](03-contracts.md)：lint 规则 / 类型 / Schema 怎么卡架构约束
- [05-observability.md](05-observability.md)：CI / 性能预算 / 错误监控
