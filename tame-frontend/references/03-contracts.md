# 显式契约与防腐层

## 核心命题

**架构的健壮程度，取决于它能在编译期拒绝多少错误。**

模块之间只通过编译期可校验的契约通信，绝不依赖"约定俗成"。`any` 透传是技术债的癌细胞。

> 能在构建时做的事，绝不拖到运行时；能在 CI 拦截的错误，绝不交给用户。

## 三大契约层

### 1. 类型契约（编译期）
任何跨模块的数据流，**先定义 TypeScript 接口/Schema，再写实现**。

```ts
// ❌ 任意 JSON 透传
function fetchUser(): Promise<any> { ... }

// ✅ 接口先行
interface UserModel {
  id: string;
  name: string;
  isAdmin: boolean;
}
function fetchUser(): Promise<UserModel> { ... }
```

铁律：
- 公共 API 函数必须有显式参数和返回值类型
- 异步函数显式 `Promise<T>`
- 禁止 `any` 透传，未知数据用 `unknown` + 类型守卫
- 不主动收紧已有类型（除非用户明确要求做类型修整）

### 2. 运行时校验（边界）
TypeScript 只在编译期生效，运行时数据进入系统的边界（API 响应、用户输入、外部消息）必须**运行时校验**。

```ts
import { z } from 'zod';

const UserSchema = z.object({
  id: z.string(),
  name: z.string(),
  isAdmin: z.boolean(),
});
type User = z.infer<typeof UserSchema>;

async function fetchUser(): Promise<User> {
  const raw = await api.get('/user');
  return UserSchema.parse(raw); // 校验 + 类型推导一步到位
}
```

工具：`zod` / `valibot` / `arktype`。不要自己手撸校验逻辑。

### 3. 静态分析（构建期）
用 ESLint 自定义规则 / Babel 插件 / AST 工具，在构建时强制项目级架构约束：

- 禁止直接 `fetch`，必须走 `services/` 封装
- 禁止跨 domain import（`domains/order` 不能 import `domains/user/internal/*`）
- 禁止 React 组件 import API 客户端
- 禁止字符串路由，必须用强类型 Routes 对象

这些规则在 PR 阶段就拦死，不靠 code review。

## 防腐层（Anti-Corruption Layer / Adapter）

前端开发最痛苦的莫过于：**后端接口变了，前端跟着大改**。直接把后端原始 JSON 满世界乱传，前端实际上已经沦为后端的"傀儡"。

### 解决方案：Adapter

在 API 请求和前端核心模型之间，强制加一道防腐适配器：

```ts
// services/userAdapter.ts
import { z } from 'zod';

// 后端 DTO（外部，可能很丑）
const BackendUserDTO = z.object({
  user_id: z.string(),
  nick_name: z.string().nullable(),
  role_mask: z.number(),
  // 历史包袱字段
  is_vip_v2: z.boolean().optional(),
  is_vip_v3: z.boolean().optional(),
});

// 前端 Model（内部，稳定干净）
interface UserModel {
  id: string;
  name: string;
  isAdmin: boolean;
  isVip: boolean;
}

export function transformUser(raw: unknown): UserModel {
  const data = BackendUserDTO.parse(raw);
  return {
    id: data.user_id,
    name: data.nick_name ?? '未知用户',
    isAdmin: data.role_mask === 1,
    isVip: data.is_vip_v3 ?? data.is_vip_v2 ?? false, // 历史兼容隐藏在这里
  };
}
```

收益：
- 后端字段怎么变，只改 `userAdapter.ts` 一处
- 业务逻辑和 UI 永远在消费最干净、最稳定的标准模型
- 隐晦的后端约定（`role_mask === 1` 是管理员）在入口处抹平
- 历史兼容代码集中，不污染业务

### Adapter 放哪

```
domains/user/
├── api/
│   └── userApi.ts           # 调用接口
├── adapter/
│   └── userAdapter.ts       # 防腐层，把后端 DTO 转成前端 Model
├── model/
│   └── User.ts              # 前端模型定义
└── ...
```

API 层只调接口，不直接给业务用。业务从 `useUser()` hook 拿到的永远是 `UserModel`，不是后端 DTO。

## 强类型路由

```ts
// ❌ 字符串路由四处散落
router.push('/user/' + userId);
router.push('/order/detail?id=' + orderId);

// ✅ 强类型 Routes 对象
export const Routes = {
  UserDetail: (id: string) => `/user/${id}`,
  OrderDetail: (params: { id: string; tab?: 'info' | 'logs' }) =>
    `/order/detail?id=${params.id}${params.tab ? `&tab=${params.tab}` : ''}`,
};

router.push(Routes.UserDetail(userId));
router.push(Routes.OrderDetail({ id: orderId, tab: 'logs' }));
```

收益：路径变更只改 Routes 一处；TypeScript 校验所有传参；重构友好。

进阶：用 `tanstack-router` / `nuxt typed routes` 等带类型的路由方案，类型校验更彻底。

## 事件总线 Payload 必须校验

```ts
// ❌ Payload 是 any，谁都不知道传什么
emitter.emit('order:created', { orderId, total });
emitter.on('order:created', (payload) => {
  console.log(payload.totalAmount); // 拼错了，运行时才崩
});

// ✅ Schema 校验
const OrderCreatedPayload = z.object({
  orderId: z.string(),
  total: z.number(),
});

const orderEvents = createTypedEmitter({
  'order:created': OrderCreatedPayload,
});

orderEvents.emit('order:created', { orderId, total });  // 类型校验
orderEvents.on('order:created', (payload) => {
  payload.total;  // 类型推导
});
```

如果用 RxJS / EventEmitter，包一层 typed wrapper。

## 构建时 vs 运行时

能在构建时做的事，绝不拖到运行时：

| 能在构建时做 | 反例（运行时做） |
|---|---|
| 路由配置生成强类型对象 | 运行时拼字符串 |
| GraphQL Schema → TypeScript 类型 | 运行时手维护类型 |
| 接口 client 用 OpenAPI / TypeSpec 生成 | 手写 fetch 包装 |
| 静态资源用 Tree-Shaking 清理 | 运行时 if 判断 |
| 国际化 key 静态校验 | 运行时缺 key 才发现 |

**Tree-Shaking 是架构洁癖的度量衡**——如果架构设计导致大量代码无法被 Tree-Shake，说明模块耦合度超标。

## 检查清单

- [ ] 公共 API 函数有没有显式参数和返回值类型？
- [ ] 项目里有多少 `any`？是否在边界进入时就用 zod 校验？
- [ ] API 响应是否被直接传给 UI 组件消费？还是过了 Adapter？
- [ ] 后端字段名（snake_case）和前端代码字段名是否一致？一致 = 防腐层缺失
- [ ] 路由是字符串还是强类型对象？
- [ ] 事件总线 Payload 有没有 Schema 校验？
- [ ] ESLint / TS 是否配置了项目级架构约束（跨 domain import 禁止等）？
- [ ] 哪些"运行时配置"其实可以构建时生成？

## 反例与代价

| 反模式 | 代价 |
|---|---|
| `Promise<any>` 满天飞 | 重构地狱，Bug 在运行时才暴露 |
| 后端 DTO 直接消费 | 后端改字段 → 前端到处改 |
| 字符串路由 | 改路径要全局搜索替换，遗漏即 404 |
| 自己手撸校验 | 漏边界、不一致、维护成本高 |
| 没有 Adapter，组件直接调 fetch | 测试困难，缓存策略乱 |
| 事件总线 Payload 是 any | 改字段不报错，运行时才崩 |
| 把架构规则写进文档让大家自觉遵守 | 永远遵守不了，靠 lint 卡死 |

## 决策路径

用户问"前端怎么和后端对接才不会改字段就崩"，给这个阶梯：

1. **第一步**：在 services 层加 Adapter，把后端 DTO 转成前端 Model（即使字段一一对应也加，建立习惯）
2. **第二步**：用 zod / valibot 在 Adapter 里做运行时校验
3. **第三步**：业务代码全部消费前端 Model，不再 import DTO 类型
4. **第四步**：建立 ESLint 规则，禁止跨层 import（components 不能 import api）
5. **第五步**：考虑用 OpenAPI / TypeSpec / GraphQL CodeGen 把 DTO 自动生成

## 延伸阅读

- [01-boundaries.md](01-boundaries.md)：Adapter 在 domain 结构里的位置
- [02-state-topology.md](02-state-topology.md)：Server Cache 与 Adapter 的配合
- [05-observability.md](05-observability.md)：契约违反的检测与上报
