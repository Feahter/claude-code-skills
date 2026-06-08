# tame-frontend

资深前端架构师视角的决策辅助 skill。覆盖业务边界、状态分层、显式契约、渲染架构、可观测性、工程系统六大母题。

## 目录

```
tame-frontend/
├── SKILL.md                     # 主文件：触发条件、6 个维度路由、决策铁律
└── references/
    ├── 01-boundaries.md         # 业务边界与复杂度治理
    ├── 02-state-topology.md     # 状态拓扑分层
    ├── 03-contracts.md          # 显式契约与防腐层
    ├── 04-rendering.md          # 渲染架构与性能
    ├── 05-observability.md      # 可观测性闭环
    └── 06-engineering-system.md # 工程系统沉淀
```

## 内容来源

合并 `~/Documents/md/fe/` 下 5 篇文档（chatgpt-fe / deepseek-fe / gemini-fe / grok-fe / kimi-fe），各自的"神级前端架构 TOP5"。

合并去重原则：
- 共识观点（≥2 篇支持）作为铁律和决策矩阵
- 单一来源观点保留并标注语境（"何时该上 / 何时是毒药"）
- 时髦但争议大的（如纯微前端方案、特定框架强观点）只在反例与决策路径里出现

## 设计形态

决策辅助型，不是流程驱动型。给"如何思考 + 检查清单 + 反例"，不给"用 X 就对了"。

每个 reference 文件结构统一：
1. 核心命题
2. 决策框架 / 决策矩阵
3. 检查清单
4. 反例与代价
5. （部分）决策路径
6. 延伸阅读

## 迭代记录

- 2026-05-27 初版，基于 5 篇源文档合并

## 未来增量更新指引

如果有新的"前端架构经验"文档加进来，按主题往对应 reference 增补：

- 业务领域 / 模块拆分 / 微前端 → 01-boundaries
- 状态管理 / 状态分层 / Server Cache → 02-state-topology
- 类型 / 校验 / 防腐层 / 路由契约 → 03-contracts
- 渲染策略 / 性能优化 / RSC / Islands → 04-rendering
- 监控 / 错误处理 / 性能预算 → 05-observability
- Monorepo / 设计系统 / SDK / CI → 06-engineering-system

新主题如果不在这 6 个里，先评估是否要新增 reference 还是合并到主文件。
