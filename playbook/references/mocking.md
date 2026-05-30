# 网络 Mock：三层策略

## 决策表

| 场景 | 用哪层 |
|---|---|
| 测前端 UI 行为，后端不重要 | route-level（`page.route`） |
| 后端联调，要真实接口 | 不 mock |
| 复杂业务流程，多接口配合 | fixture file（JSON 文件） |
| 多端共享 mock（开发也用） | MSW |
| CI 跑得稳，本地用真后端 | 环境分支：`process.env.CI ? mock : real` |

## 第 1 层：`page.route`（最常用）

```ts
test('订单列表 - 空状态', async ({ page }) => {
  await page.route('**/api/orders', route =>
    route.fulfill({ status: 200, json: { items: [] } })
  );
  await page.goto('/orders');
  await expect(page.getByText('暂无订单')).toBeVisible();
});
```

**模式**：
```ts
// 拦截单个接口
await page.route('**/api/orders', handler);

// 拦截多个，按 method 区分
await page.route('**/api/orders', async route => {
  if (route.request().method() === 'POST') {
    return route.fulfill({ status: 201, json: { id: '123' } });
  }
  return route.continue();  // 其他放过
});

// 拦截后修改原响应
await page.route('**/api/orders', async route => {
  const resp = await route.fetch();
  const json = await resp.json();
  json.items = json.items.slice(0, 1);  // 只保留 1 条
  await route.fulfill({ response: resp, json });
});
```

**坑**：
- `**/api/orders` 通配符不会匹配 `?` 后面的 query。要带 query 用正则
- `page.route` 放在 `goto` 之前，不然首次请求拦不住
- 多个 `page.route` 注册同一 URL，**最后注册的优先**

## 第 2 层：fixture file（JSON 数据）

```
tests/mocks/
├── orders/
│   ├── empty.json
│   ├── normal.json
│   └── overflow.json
└── users/
    └── admin.json
```

```ts
import ordersEmpty from '../mocks/orders/empty.json';

test('空订单', async ({ page }) => {
  await page.route('**/api/orders', r =>
    r.fulfill({ json: ordersEmpty })
  );
  // ...
});
```

适合：响应数据复杂、多用例复用、有版本管理需求。

## 第 3 层：MSW（开发+测试共享）

如果项目已经有 `msw` 用于本地开发 mock，e2e 直接复用：

```ts
// tests/fixtures/msw.ts
import { setupServer } from 'msw/node';
import { handlers } from '../../src/mocks/handlers';

export const server = setupServer(...handlers);

// global-setup
server.listen();
```

**何时不用 MSW**：项目没在用、只为 e2e 引入 → 太重。直接 `page.route` 就够。

**MSW 真正发力的场景**：单元测试（Vitest/Jest）+ 组件测试 + E2E **共用同一套 handlers**，避免三处维护三份假数据。前提是项目已经在 `src/mocks/handlers.ts` 用 MSW 做本地开发 mock。

```
src/mocks/handlers.ts        ← 单一数据源
       ├──→ Vitest（jsdom 拦 fetch）
       ├──→ Storybook（Service Worker）
       ├──→ 本地开发（dev server）
       └──→ E2E（Node setupServer 或 Service Worker）
```

### MSW 在 Vitest 的完整 setupServer 配方

单测/集成层用 `msw/node` 的 `setupServer`，生命周期统一在 setup 文件接管（见 `references/setup-recipes.md` 的 `test-utils/setup.ts`）：

```ts
// test-utils/server.ts —— 单一数据源
import { setupServer } from 'msw/node';
import { handlers } from '../mocks/handlers';
export const server = setupServer(...handlers);

// test-utils/setup.ts —— 全局生命周期（vitest.config 的 setupFiles 引它）
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));  // 漏 mock 的请求直接报错，别静默放过
afterEach(() => server.resetHandlers());   // 关键：每个用例后重置，避免用例间污染
afterAll(() => server.close());
```

用例里用 `server.use()` **动态覆盖** handler 测异常路径——这是高价值用例：

```ts
it('接口 500 时显示加载失败', async () => {
  server.use(http.get('/api/orders', () => HttpResponse.json(null, { status: 500 })));
  render(<OrderList />);
  expect(await screen.findByText('加载失败')).toBeInTheDocument();
});

it('网络断开时显示重试', async () => {
  server.use(http.get('/api/orders', () => HttpResponse.error()));
  render(<OrderList />);
  expect(await screen.findByRole('button', { name: '重试' })).toBeInTheDocument();
});
```

`onUnhandledRequest: 'error'` + `resetHandlers` 是两个最容易漏的点：前者让"忘了 mock"立刻暴露，后者防止上一个用例的 `server.use` 泄漏到下一个。集成测试写法详见 `references/unit-integration.md`。

## 第 4 层：HAR 录制回放（复杂状态机）

多接口、多状态、时序敏感的流程（订单状态流转、支付回调），手写 mock 容易漏时序。**HAR 录制 = 真实交互拷贝一份当契约**：

```ts
test('订单状态流转', async ({ page }) => {
  // 首次跑：把真实交互录到 HAR；后续跑：按 HAR 回放
  await page.routeFromHAR('tests/hars/order-lifecycle.har', {
    update: false,        // 首次设 true 录制，之后改 false 回放
    updateContent: 'embed',
    updateMode: 'minimal', // 只更新真正变化的接口
  });

  await page.goto('/order/123');
  await expect(page.getByTestId('status')).toHaveText('待支付');

  await page.getByRole('button', { name: '支付' }).click();
  // HAR 中已录了支付回调的 webhook 序列，含时序
  await expect(page.getByTestId('status')).toHaveText('已发货', { timeout: 10_000 });
});
```

**录制流程**：
1. 起真后端 → 跑用例时设 `update: true` → 真实接口都被录到 HAR
2. 提交 HAR 到 git（`tests/hars/*.har`）
3. 后续 CI / 本地：`update: false`，完全脱机回放

**HAR 优点**：
- 时序、状态码、payload、延迟都是真实的
- 后端改了接口，重新录制即可，不用手改 mock 代码
- HAR 文件可 review，等于"接口契约的快照"

**HAR 适用判断**：
| 场景 | 用 HAR | 用 page.route |
|---|---|---|
| 单接口几个固定响应 | | ✅ |
| 流程涉及 5+ 接口 + 时序 | ✅ | |
| 异常路径（500、超时） | | ✅（更可控） |
| 接口契约稳定，改动少 | ✅ | |
| 接口在快速迭代 | | ✅（不用频繁重录） |

**HAR 配合局部覆盖**：HAR 兜底 + `page.route` 覆盖单个异常分支：

```ts
await page.routeFromHAR('tests/hars/order.har');
// 在 HAR 之后注册的路由优先生效，覆盖 HAR 里的支付接口
await page.route('**/api/pay', r => r.fulfill({ status: 502 }));
```

## 拦截二进制 / 文件下载

```ts
await page.route('**/api/export.csv', route =>
  route.fulfill({
    status: 200,
    contentType: 'text/csv',
    body: 'col1,col2\n1,2\n',
  })
);
```

## 模拟接口失败

```ts
test('网络异常时显示重试按钮', async ({ page }) => {
  await page.route('**/api/orders', route => route.abort('failed'));
  await page.goto('/orders');
  await expect(page.getByRole('button', { name: '重试' })).toBeVisible();
});

// 模拟 500
await page.route('**/api/orders', r => r.fulfill({ status: 500 }));

// 模拟超时
await page.route('**/api/orders', async r => {
  await new Promise(res => setTimeout(res, 30_000));
  await r.continue();
});
```

异常路径测试是高价值用例，**对抗覆盖阶段必跑**。

## 何时不该 mock

- 接口契约测试（schema 验证）→ 用真后端 + 测试库（dredd / pact）
- 端到端验收测试（核心流程）→ 用真后端 + 测试环境
- 性能基线测试 → 真后端

测试金字塔：**Mock 多 = 跑得快但容易和真后端脱节**。关键路径至少留一条"全真"链。
