# 状态拓扑分层

## 核心命题

**99% 前端项目后期崩盘的原因不是代码量，而是状态失控**——不知道数据从哪来、不知道谁修改了它、不知道谁依赖它。

状态管理最重要的不是"管理状态"，而是**管理状态的流向**。

> 状态管理的复杂度，与全局 Store 的体积成正比。

## 决策框架：5 层状态拓扑

按"生命周期 × 作用域"分层，从上到下优先选择：

| 层级 | 特征 | 生命周期 | 推荐技术 | 例子 |
|---|---|---|---|---|
| **URL 状态** | 需要分享、刷新可恢复、SEO | 与 URL 同步 | React Router / Next.js Router / Vue Router | 当前选中的 tab、分页、筛选条件、详情 ID |
| **Server Cache** | 远程数据，有失效策略 | 受请求 / 失效控制 | TanStack Query / SWR | 用户资料、商品列表、订单详情 |
| **Global UI** | 跨路由、跨模块共享 | 应用级 | Zustand / Jotai / Pinia | 主题色、登录态、侧边栏开关 |
| **Local** | 单页面/单组件内 | 组件挂载期 | useState / ref | Modal 开关、表单临时值、loading |
| **Derived** | 可计算，无副作用 | 不存在的状态 | useMemo / computed / Selector | 列表过滤后结果、合计金额 |

### 铁律
1. **能用 URL 状态解决的，绝不用全局 Store**——URL 状态天然支持分享和刷新恢复
2. **能用 Server Cache 自动管理的，绝不手写 Redux**——TanStack Query / SWR 已经把 80% 全局状态消除了
3. **派生状态不是状态**——能算出来的，就不该存。`filteredList = list + filter` 永远不该出现在 state 里

### 反铁律：不要按"全局 vs 局部"二分
新手最大错误是把"是否多组件用到"当成"是否要全局"。其实大量"多组件用到"的状态本质是 URL 状态或 Server Cache，根本不该进 Store。

## Server State ≠ Client State

这是状态分层最重要的认知。两者**生命周期完全不同**：

| 维度 | Server State | Client State |
|---|---|---|
| 来源 | 后端，唯一真实源在远程 | 前端自己产生 |
| 时效性 | 会过期，需要 revalidate | 不过期 |
| 多用户 | 可能被别人改 | 自己控制 |
| 同步策略 | 缓存 + 失效 + 重取 | 直接读写 |

**最大错误**：把 Server State 塞进 Redux/Pinia 当本地状态管。然后：

- 缓存怎么失效？手写 invalidation 地狱
- 重复请求？要写 dedup
- 数据过期？要写定时刷新
- 乐观更新？要手写 rollback

这些 TanStack Query / SWR 已经全部解决。继续手写就是重新造一个三流的轮子。

## 全局 Store 的边界

经过前面的分层后，能进 Global Store 的实际很少：

✅ 适合放全局：
- 登录态、当前用户基础信息（虽然用户详情更适合放 Server Cache）
- 主题色 / 语言 / 单位偏好
- 跨路由共享的临时 UI 状态（侧边栏收起、全局 Modal）

❌ 不适合放全局：
- 任何远程数据 → 用 Server Cache
- 任何能从 URL 推导出的 → 用 URL 状态
- 任何能从其他状态算出来的 → 派生
- 任何只在一个页面/组件用的 → 局部

剩下这点状态，**Atom / Signals 优先于巨型 Store**。

## Atom / Signals vs 集中式 Store

| 维度 | 集中式 Store（Redux/Vuex） | Atom（Jotai）/ Signals |
|---|---|---|
| 心智模型 | reducer + dispatch + selector | 细粒度反应式数据 |
| 渲染粒度 | 大，依赖 selector 优化 | 天然按需渲染 |
| 模板代码 | 多 | 少 |
| 调试 | 时间旅行强 | 较弱但简单 |
| 适合场景 | 复杂状态机、需要时间旅行 | 大多数现代应用 |

**默认选 Atom / Signals**（Jotai、Zustand-with-selectors、Vue Reactivity、Solid Signals），只有真的需要严肃状态机时才上 Redux Toolkit。

## 状态下沉：性能优化的底层逻辑

把状态下沉到**真正用到它的最小子树**，避免根状态变更引发全树 rerender。

### 反例：状态全堆 App 顶部
```tsx
// ❌
function App() {
  const [filter, setFilter] = useState('');
  const [list, setList] = useState([]);
  // ...所有 state 都在这
  return <Layout>...</Layout>;
}
```
任何 state 变化整个 App 子树重新渲染。

### 正例：下沉到使用点
```tsx
function App() {
  return <FilterableList />;  // App 自己不持有这些 state
}

function FilterableList() {
  const [filter, setFilter] = useState('');
  // ...
}
```

### Context 拆分
不要写一个巨型 Context。一个 Context 变化会让所有消费者 rerender。

```tsx
// ❌ 巨型 Context
<AppContext value={{ user, theme, cart, settings }}>

// ✅ 拆开
<UserContext>
  <ThemeContext>
    <CartContext>
      <SettingsContext>
```

或更进一步，用 Atom / Signals 替代 Context。

## 派生状态不是状态

```tsx
// ❌ 把派生值存进 state
const [list, setList] = useState([]);
const [filteredList, setFilteredList] = useState([]);
useEffect(() => {
  setFilteredList(list.filter(...));
}, [list, filter]);

// ✅ 派生
const [list, setList] = useState([]);
const [filter, setFilter] = useState('');
const filteredList = useMemo(() => list.filter(...), [list, filter]);
```

存派生值的代价：一定会有同步 bug——某次更新 list 忘了更新 filteredList，灾难就来了。

## 检查清单

- [ ] 当前的"全局状态"里，多少是远程数据？这部分应该全部迁到 TanStack Query / SWR
- [ ] 有没有用 useEffect + setState 同步两份数据？如果是，多半应该派生
- [ ] 选中的 tab、分页、筛选条件存在哪？如果是 Store，能不能改成 URL 状态？
- [ ] 一个 Modal 的开关状态需要进 Global Store 吗？99% 不需要
- [ ] App 根组件持有了多少 state？state 是否可以下沉到子组件？
- [ ] 是否存在巨型 Context，一变全场重渲染？
- [ ] 用 Redux 是真需要时间旅行 / 复杂状态机，还是惯性？
- [ ] 团队成员能不能讲清"状态从哪来、谁能改、谁会订阅"？讲不清就是乱

## 反例与代价

| 反模式 | 代价 |
|---|---|
| 把 Server Cache 塞进 Redux | 手写缓存失效、重复请求、乐观更新地狱 |
| 选中 tab / 分页 / 筛选放 Store | 不能分享 URL，刷新丢状态，浏览器后退异常 |
| 派生值存进 state | 同步 bug 早晚会出现 |
| 巨型 AppContext | 任何变动 = 全树 rerender，性能崩盘 |
| 状态全堆 App 顶部 | 任何细微变化都触发整树 reconcile |
| 一上来就 Redux + redux-saga 完整套件 | 50 行业务，500 行 boilerplate |

## 决策路径（用户来问"该用什么状态管理"）

按这个顺序追问：

1. 这个数据**来源**是什么？
   - 远程 → Server Cache（TanStack Query / SWR）
   - 浏览器 URL → URL 状态
   - 用户即时输入或交互 → Client State
2. 它的**作用域**是什么？
   - 单组件 → useState / ref
   - 一个子树 → 提到该子树根的 useState 或局部 Context
   - 跨路由 → Atom / Signals / 轻量 Store
3. 真的"跨路由"吗？还是其实可以 URL 化？
4. 真的需要 Redux 的时间旅行 / 严肃状态机吗？

走完这 4 步，你会发现"需要 Redux"的场景比想象中少 90%。

## 延伸阅读

- [01-boundaries.md](01-boundaries.md)：状态归属哪个 domain
- [04-rendering.md](04-rendering.md)：状态下沉与渲染性能
- [03-contracts.md](03-contracts.md)：Server State 入参出参怎么走防腐层
