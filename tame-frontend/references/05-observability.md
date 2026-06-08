# 可观测性闭环

## 核心命题

**没有 RUM（真实用户监控）数据的架构决策，都是拍脑袋。**

绝大多数前端架构师只关心怎么写代码，不关心线上运行时究竟发生了什么。神级架构师会把可观测性视为架构的一等公民。

> 你的架构有多优雅，取决于它在网络抖动、CDN 故障、第三方挂掉时的表现有多体面。

> 架构演进的方向，应该由真实用户的 pain points 决定，而不是技术团队的 vanity metrics。

## 三件事必须做

1. **性能可观测**：RUM 监控 LCP / INP / CLS / TTFB
2. **错误可观测**：分级错误边界 + 结构化上报
3. **行为可观测**：用户路径（埋点 + Session Replay 数据源）

## 性能监控：RUM > Lighthouse

| 维度 | Lighthouse（合成） | RUM（真实） |
|---|---|---|
| 来源 | 本地或 CI 跑 | 真实用户上报 |
| 网络 | 模拟 | 真实多样 |
| 设备 | 模拟 | 真实多样 |
| 价值 | 回归检测 | 决策依据 |

**本地 Lighthouse 100 分是幻觉**。决策必须看 RUM 的 P75 / P95。

工具：Vercel Analytics / Cloudflare Web Analytics / Sentry Performance / 自建（用 `web-vitals` 库 + 自家上报）。

```ts
import { onLCP, onINP, onCLS } from 'web-vitals';

onLCP(metric => report('lcp', metric));
onINP(metric => report('inp', metric));
onCLS(metric => report('cls', metric));
```

按 `URL × 浏览器 × 设备 × 版本` 聚合，找出最差的 P75 路径。

## Error Boundary 三级分级

不要全站只有一个 ErrorBoundary 显示"出错了"。按严重度分三级：

### 1. 致命级（白屏 / 整个 App 崩）
- **现象**：根级未捕获错误
- **处理**：兜底页 + 立即上报
- **位置**：App 根

### 2. 模块级（一个 Widget 崩）
- **现象**：某个区块 throw，但页面其他部分能用
- **处理**：局部降级为占位符 / 错误提示，主流程继续
- **位置**：每个 domain 模块根、关键 Widget 外层

```tsx
<ErrorBoundary fallback={<OrderListUnavailable />}>
  <OrderList />
</ErrorBoundary>
```

### 3. 静默级（非核心功能失败）
- **现象**：埋点上报、推荐位、A/B 实验取数失败
- **处理**：隐藏该功能，不影响主流程，静默上报
- **位置**：包裹非核心组件

```tsx
<SilentErrorBoundary>
  <RecommendWidget />
</SilentErrorBoundary>
```

### 错误上报必带的上下文

捕获错误时，自动提取：
- 当前组件 props 摘要（脱敏后）
- 用户最近 N 步操作栈（Breadcrumb）
- 当前 Store / Atoms 快照
- 当前 URL、用户 ID、会话 ID
- 浏览器、设备、版本
- 网络状态

工具：Sentry / Datadog RUM / OpenTelemetry。

## Skeleton 是架构组件，不是体验优化

加载态不是"体验优化"，是架构对网络不确定性的承诺。每个异步依赖必须有对应的 Skeleton 契约：

```tsx
<Suspense fallback={<UserCardSkeleton />}>
  <UserCard />
</Suspense>
```

**Skeleton 的 DOM 结构应与真实内容同构**——避免布局抖动（CLS）。Skeleton 高度、占位框尺寸要和真实内容一致。

## 性能预算 CI 卡死

在 CI 里植入：

- **Lighthouse CI** / **size-limit** / **bundlesize**：检查 bundle 体积
- **puppeteer + web-vitals**：在受控环境测 LCP / INP
- **关键路径 JS ≤ 150KB**、**LCP ≤ 2.5s**、**INP ≤ 200ms**：超出直接构建失败

```yaml
# .github/workflows/perf-budget.yml
- run: npm run build
- run: npx size-limit
- run: npx lhci autorun --upload.target=temporary-public-storage
```

## 用户路径 → 代码分割策略

不是平均用力分包，而是 RUM 数据驱动：

1. 看真实用户访问路径热力图，发现 80% 用户只访问 3 个核心页面
2. 围绕这 3 个页面做极致优化：核心首屏 SSG / 边缘渲染 / 关键 CSS inline
3. 长尾页面用 lazy + Suspense

## 错误聚合 = 架构体检

错误按 `错误类型 × 模块 × 浏览器 × 版本` 聚合。如果某个模块错误率突增，**架构上一定是该模块的输入契约被破坏了**——回到 [03-contracts.md](03-contracts.md) 看防腐层。

## 第三方脚本隔离

广告、统计、客服插件必须 iframe / Shadow DOM 隔离。

监控第三方脚本是否在拖累主应用：
- TBT（Total Blocking Time）增量
- 长任务（Long Task）来源
- Console 错误来源

## 检查清单

- [ ] 是否有 RUM？P75 LCP / INP / CLS 是多少？
- [ ] 错误是否分级处理（致命 / 模块 / 静默）？还是整站一个 ErrorBoundary？
- [ ] 错误上报是否带组件 props / 用户路径 / store 快照？
- [ ] 异步加载点是否都有 Skeleton？Skeleton 高度是否和真实内容一致（防 CLS）？
- [ ] 性能预算是否在 CI 卡死？还是只看本地 Lighthouse？
- [ ] 第三方脚本是否隔离？挂掉时主应用是否能继续工作？
- [ ] 错误率突增时，是否有自动告警？告警是否带模块归属？
- [ ] 代码分割是不是按真实用户访问数据做的？

## 反例与代价

| 反模式 | 代价 |
|---|---|
| 只看本地 Lighthouse | 真实用户性能糟糕，无人察觉 |
| 全站一个 ErrorBoundary 显示"出错了" | 一个小组件崩拖垮整页 |
| 错误上报只有 stack trace，没有上下文 | 排查 2 小时 vs 2 分钟的差距 |
| 没有 Skeleton，异步加载页面跳来跳去 | CLS 飙升，体验崩溃 |
| 性能优化靠"感觉"，没数据 | 优化错地方，浪费工时 |
| 第三方脚本同步加载 | 第三方崩 = 主应用崩 |
| 错误率告警靠人盯 | 等用户投诉才发现 |
| 把可观测性当作"上线后再说"的事 | 永远做不上 |

## 决策路径

用户问"我们要不要建可观测性体系，从哪开始"：

1. **第一步（一周内）**：接入 web-vitals 自动上报 LCP/INP/CLS，看真实数据
2. **第二步**：接 Sentry 或类似平台，拿到错误聚合
3. **第三步**：在 App 根 + 每个 domain 模块加分级 ErrorBoundary
4. **第四步**：错误上报补充上下文（props / breadcrumb / store snapshot）
5. **第五步**：CI 接 Lighthouse CI / size-limit，定性能预算
6. **第六步**：建告警阈值（错误率 / P75 LCP / P75 INP）
7. **第七步**：基于 RUM 数据做下一轮架构演进决策

不要一上来铺一整套，分阶段建是关键。

## 延伸阅读

- [03-contracts.md](03-contracts.md)：错误聚合发现的契约违反
- [04-rendering.md](04-rendering.md)：性能指标对应的优化方向
- [06-engineering-system.md](06-engineering-system.md)：CI / ADR / 自动化把这些卡死
