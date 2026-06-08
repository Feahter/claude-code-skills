# 渲染架构与性能

## 核心命题

**前端性能本质：少渲染、少计算、少传输。**

优先级：**渲染次数 >>> JS 计算 >>> 微优化**。

天天 useMemo/useCallback/memo 是反模式——性能没提升，复杂度翻倍。真正的性能架构是先看"树"（渲染树），再看函数。

## 渲染策略选型矩阵

不要拿一把名为 "SPA" 的锤子敲所有钉子。按业务场景选：

| 场景 | 核心诉求 | 推荐策略 | 备注 |
|---|---|---|---|
| 营销落地页 / 活动页 | 极致首屏 + SEO | **SSG**（静态生成）或 Astro Islands | 内容稳定，构建即出 |
| 电商首页 / 信息流 | 高频更新 + SEO | **ISR**（增量静态再生）或 RSC | 缓存边缘渲染 |
| 详情页（商品/文章） | SEO + 动态内容 | **SSR / RSC** | 用户身份个性化用边缘 |
| 重交互后台 / 收银台 | 状态频繁交互、无 SEO | **CSR（SPA）** | 用户登录后才进，没必要 SSR |
| 实时协作 / Dashboard | 复杂客户端状态、实时更新 | **CSR + WebSocket** | SSR 没有意义 |
| 混合页面（壳静态、岛交互） | 大部分静态 + 局部交互 | **Islands**（Astro / Qwik） | 减少 hydration 成本 |

### 现代默认起点

新项目（2026）默认用 meta-framework + Server-First：

- **Next.js（App Router + RSC）** / **Nuxt** / **SvelteKit** / **Remix**
- 数据获取下沉到服务端，只把交互必要的轻量 JS 发到客户端
- 结合 Edge Runtime（Cloudflare Workers / Vercel Edge）做请求级个性化

避免：纯 Vite + React 从零搭重业务项目。

### RSC（React Server Components）要点

```tsx
// 默认 Server Component（不发 JS 到客户端）
export default async function ProductPage({ params }) {
  const product = await db.product.findUnique({ where: { id: params.id } });
  return (
    <article>
      <h1>{product.name}</h1>
      <AddToCartButton productId={product.id} />  {/* Client Component */}
    </article>
  );
}

// 'use client' 标记的才发 JS
'use client';
export function AddToCartButton({ productId }) {
  const [pending, setPending] = useState(false);
  // ...
}
```

收益：bundle 大幅瘦身、LCP/INP 改善。但要注意：RSC 心智模型新，团队上手成本不低，小项目反而是负担。

## 边缘渲染 + 动态岛

### 边缘渲染（Edge Rendering）
利用 Cloudflare Workers / Vercel Edge / Deno Deploy 在离用户最近的节点做请求级渲染。读 cookie 中的用户身份，直接生成个性化首屏 HTML。

延迟从 500ms 降到 50ms。

### Islands 架构
页面 95% 内容静态孤岛，在边缘直接输出；剩下 5% 高交互部分（实时聊天、股价、购物车）声明为独立小岛，客户端异步注入并自管理状态。

**关键点**：小岛之间必须设计**声明式通信总线**（CustomEvent / 轻量 Pub/Sub）。**绝不能**在顶层共享一个大状态对象，否则岛与岛又耦合，性能优势荡然无存。

代表实现：Astro / Qwik / Fresh。

## 渲染树优化（CSR 性能基础）

### 1. 状态下沉
不要 App 顶部持有所有 state。下沉到真正用到它的最小子树。详见 [02-state-topology.md](02-state-topology.md)。

### 2. Context 拆分
一个巨型 Context 变化会让所有消费者 rerender。

```tsx
// ❌ 巨型 Context
<AppContext value={{ user, theme, cart, settings }}>

// ✅ 拆开 / 改用 Atom
<UserContext>
  <ThemeContext>
    <CartContext>
```

### 3. 列表虚拟化
超大列表用 `react-window` / `TanStack Virtual` / `vue-virtual-scroller`。1000+ 行的表格不虚拟化就是给浏览器送葬。

### 4. 路由级 / 模块级 / 组件级切割

```tsx
// 路由级
const ProductPage = lazy(() => import('./pages/Product'));

// 组件级
const HeavyChart = lazy(() => import('./HeavyChart'));
```

不是整个 bundle 一刀切。

### 5. memo / useMemo 的正确用法

只在性能 profile 显示有问题时用，不无脑全堆。优先：
1. 状态下沉，让根 state 变化不影响子树
2. 拆 Context
3. 列表虚拟化
4. 真还有问题，再考虑 React.memo / useMemo

`useCallback` 在大多数场景是噪音——除非传递给 memo 化的子组件，否则没用。

## INP / LCP / CLS：不是技术指标，是架构指标

| 指标 | 含义 | 架构意义 |
|---|---|---|
| **LCP** | 最大内容绘制 | 首屏架构（SSR/SSG/Edge）的 KPI |
| **INP** | 交互响应延迟（替代 FID） | 主线程是否被 JS 卡住的体检 |
| **CLS** | 布局抖动 | 异步内容是否有 Skeleton 占位 |

本地 SSD + 千兆网测出的 Lighthouse 100 分是幻觉。看 RUM（真实用户监控）数据。详见 [05-observability.md](05-observability.md)。

## 性能预算（Performance Budget）

在 CI 里植入 Lighthouse CI 或自定义 puppeteer 脚本，强制设定预算：

- 关键路径 JavaScript ≤ 150 KB
- LCP ≤ 2.5s（P75）
- INP ≤ 200ms（P75）
- CLS ≤ 0.1

任何破坏预算的 PR 直接构建失败。比 code review 管用 100 倍。

## 第三方脚本隔离

广告、统计、客服插件必须用 `iframe` / Shadow DOM 隔离，它们崩溃不能拖垮主应用。

```html
<iframe src="..." sandbox="allow-scripts" loading="lazy"></iframe>
```

## 检查清单

- [ ] 项目类型是否真的需要 SPA？营销页可以 SSG / 详情页可以 SSR
- [ ] 团队规模 / 业务复杂度是否值得上 RSC？小项目反而是负担
- [ ] 上 Server-First 时，是否清楚 Client Component 的边界？滥用 `'use client'` 等于回到 SPA
- [ ] App 顶部有多少 state？根状态变更触发的 rerender 范围是？
- [ ] 大于 200 行的列表有没有虚拟化？
- [ ] 路由是不是按需切包？还是一个巨大 main bundle？
- [ ] 有没有性能预算 + CI 卡死？还是只看本地 Lighthouse？
- [ ] INP / LCP / CLS 在 RUM 真实数据下的 P75 值是多少？
- [ ] 第三方脚本（埋点、广告、客服）有没有隔离？

## 反例与代价

| 反模式 | 代价 |
|---|---|
| 全站 SSR（包括登录后台、内部工具） | 服务器成本翻倍，没收益 |
| 全站 CSR（包括营销落地页） | SEO 0 分，首屏 5s+ |
| 一上来 useMemo/useCallback 全堆 | 复杂度翻倍，性能不变 |
| 状态全堆 App 顶部 | 任何变化全树 rerender |
| 巨型 Context | 同上 |
| 1000+ 列表不虚拟化 | 滚动卡顿，主线程长任务 |
| 没有路由级代码切割 | 首屏 bundle 几 MB |
| 第三方脚本同步阻塞 | 第三方挂掉拖垮主应用 |
| 只看本地 Lighthouse 100 分 | 真实用户性能糟糕，没人发现 |
| 滥用 `'use client'` | RSC 优势全失，回到 SPA |
| 微前端各子应用 React 版本不一致 | 运行时错误、性能开销 |

## 决策路径

用户问"我的页面性能不好，怎么办"，按这个顺序排查：

1. 先看真实数据（RUM）：LCP / INP / CLS 的 P75
2. **首屏问题（LCP 高）**：
   - 静态内容 → 上 SSG / SSR / Edge
   - 大 bundle → 路由级切割
   - 慢接口 → 边缘渲染 / 流式 SSR / Suspense
3. **交互卡（INP 高）**：
   - 主线程长任务 → 看渲染树（状态下沉、Context 拆分）
   - 大列表 → 虚拟化
   - 重计算 → Web Worker
4. **布局抖动（CLS 高）**：
   - 异步内容缺占位 → Skeleton
   - 图片缺尺寸 → width/height
5. 都查完还有问题，才上 useMemo / React.memo 这种微优化

## 延伸阅读

- [02-state-topology.md](02-state-topology.md)：状态下沉与渲染性能的关系
- [05-observability.md](05-observability.md)：RUM 与性能预算
- [01-boundaries.md](01-boundaries.md)：分层渲染（Shell / Content / Interaction）
