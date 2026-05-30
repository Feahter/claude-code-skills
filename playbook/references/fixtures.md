# Fixture vs POM：组织测试的两种思路

## 决策表（先选模型再写代码）

| 项目情况 | 推荐 | 理由 |
|---|---|---|
| 用例 < 30，3 个月内规模可控 | Fixture | 代码量减半，无类继承心智负担 |
| 用例 ≥ 50，多人维护 | Fixture + 选择性 POM | 公共流程用 fixture，超复杂页面才包 POM |
| 已经有大量 POM，存量代码 | 维持 POM，新增走 fixture | 不要重写，新增即可 |
| 用例多用同一组 setup（登录、造数据） | Fixture | fixture 自带依赖注入 |

**结论**：默认用 fixture，超复杂的页面（10+ 子组件、多个交互区）再单独抽 POM 类。

## Fixture 模式

```ts
// tests/fixtures/index.ts
import { test as base } from '@playwright/test';

type MyFixtures = {
  authedPage: Page;          // 已登录的 page
  testUser: { id: string; email: string };
};

export const test = base.extend<MyFixtures>({
  testUser: async ({}, use) => {
    const user = await createTestUser();  // 调你的 API
    await use(user);
    await deleteTestUser(user.id);  // teardown
  },
  authedPage: async ({ page, testUser }, use) => {
    await login(page, testUser);
    await use(page);
  },
});

export { expect } from '@playwright/test';
```

用例里：
```ts
import { test, expect } from '../fixtures';

test('用户能看到自己的订单', async ({ authedPage, testUser }) => {
  await authedPage.goto('/orders');
  await expect(authedPage.getByText(testUser.email)).toBeVisible();
});
```

## Fixture 作用域

| scope | 何时用 |
|---|---|
| `test` (默认) | 每个用例新建 |
| `worker` | 每个 worker 进程新建一次（多用例共享） |

worker-scoped fixture 适合：登录态共享、DB 连接池、初始化一次的 mock server。

```ts
testUser: [async ({}, use) => {
  const user = await createTestUser();
  await use(user);
  await deleteTestUser(user.id);
}, { scope: 'worker' }],
```

## auth fixture（标准模板）

完整代码见 `examples/auth.fixture.ts`。要点：

1. `globalSetup.ts` 跑一次登录 → 存 `storageState` 到 `.auth/user.json`
2. `playwright.config.ts` 设 `use: { storageState: '.auth/user.json' }`
3. 多角色场景：每个角色一个 storageState 文件 + 一个 fixture

## POM（页面对象模型）

仅用于**复杂页面**（10+ 交互、多个状态）。简单页直接用 locator 链就够。

```ts
// pages/checkout.page.ts
export class CheckoutPage {
  constructor(public readonly page: Page) {}

  readonly addressInput = this.page.getByLabel('收货地址');
  readonly submitBtn = this.page.getByRole('button', { name: '提交订单' });

  async fillAddress(addr: string) {
    await this.addressInput.fill(addr);
  }

  async submit() {
    await this.submitBtn.click();
    await expect(this.page).toHaveURL(/\/orders\/\d+/);
  }
}
```

**POM 反模式**：
- ❌ 不要把所有 page 都包成 POM——简单页只是给 fixture 添麻烦
- ❌ 不要在 POM 方法里写 `await page.waitForTimeout(500)`
- ❌ 不要让 POM 方法返回 `Promise<boolean>` 让用例自己 if/else——直接 `expect`

## 数据准备：API 优先于 UI

```ts
// ❌ 慢且 flaky
await page.goto('/login');
await page.fill('#email', 'a@b.com');
await page.fill('#password', 'xxx');
await page.click('button[type=submit]');

// ✅ 快且稳
const token = await api.login('a@b.com', 'xxx');
await page.context().addCookies([{ name: 'token', value: token, ...}]);
```

UI 只测"用户路径"，前置数据全用 API 造。
