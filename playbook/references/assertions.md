# 断言：web-first 是底线

## 核心原则

Playwright 的 `expect(locator).xxx()` 自带智能重试（默认 5s），自动等待 DOM 稳定 + 网络空闲。**任何手动 `sleep` / `waitForTimeout` / 自己写 while 循环都是反模式。**

## web-first 断言全表

| API | 用途 |
|---|---|
| `toBeVisible()` | 元素存在且可见 |
| `toBeHidden()` | 元素不可见或不存在 |
| `toHaveText(s)` | 完整文本匹配（支持正则） |
| `toContainText(s)` | 文本包含 |
| `toHaveValue(v)` | input 值 |
| `toHaveAttribute(k, v)` | 属性值 |
| `toHaveClass(c)` | className 含 |
| `toHaveCount(n)` | locator 命中数量 |
| `toBeEnabled()` / `toBeDisabled()` | button 等可交互态 |
| `toBeChecked()` | checkbox / radio |
| `toHaveURL(u)` | page URL（页面跳转后） |
| `toHaveTitle(t)` | document.title |

页面级：`expect(page).toHaveURL(...)` / `toHaveTitle(...)`

API 响应级：`expect(response).toBeOK()` / `expect(await response.json()).toEqual({...})`

## 反模式禁令（validate-test.sh 会拦截）

```ts
// ❌ 死等
await page.waitForTimeout(2000);

// ❌ 手动轮询
while (!(await page.locator('.foo').isVisible())) { /* ... */ }

// ❌ 不带断言的 click 后没验证
await page.getByRole('button').click();
// 然后没有 expect - 等于没测

// ❌ 用 isVisible() 当断言
if (await page.locator('.foo').isVisible()) { /* ... */ }
// isVisible 是即时检查，不重试。要用 expect(locator).toBeVisible()
```

## 何时该用 `waitFor`

`locator.waitFor({ state })` 是显式等待，**只在断言不适用时用**：

```ts
// 等元素消失后再做下一步（不是断言，是流程控制）
await page.getByRole('alert').waitFor({ state: 'detached' });
await page.getByRole('button', { name: '继续' }).click();
```

90% 场景应该用 `expect(...).toBeHidden()` 而不是 `waitFor({ state: 'detached' })`。

## 网络等待

```ts
// ✅ 等具体接口完成
const respPromise = page.waitForResponse(r =>
  r.url().includes('/api/orders') && r.status() === 200
);
await page.getByRole('button', { name: '提交订单' }).click();
const resp = await respPromise;
expect(await resp.json()).toMatchObject({ status: 'created' });
```

**先创 promise 再触发动作**——顺序反了会丢响应。

## soft 断言（连续验证多个点）

```ts
// 一个失败不阻断后续，最后一起报
await expect.soft(page.getByText('订单号')).toBeVisible();
await expect.soft(page.getByText('总金额')).toBeVisible();
await expect.soft(page.getByText('收货地址')).toBeVisible();
```

适合"页面渲染后整体校验"。

## 自定义超时

```ts
await expect(page.getByText('上传完成')).toBeVisible({ timeout: 30_000 });
```

只对特定慢操作（上传、长轮询）放宽，**不要全局调高**——会掩盖真正的 flaky 问题。

## 视觉断言

```ts
await expect(page).toHaveScreenshot('checkout.png', {
  maxDiffPixelRatio: 0.01,
  mask: [page.getByTestId('current-time')],  // 屏蔽动态内容
});
```

首次跑生成基线图，后续对比。CI 上跑前确保字体/渲染环境一致（用 Docker）。

## 双模态断言（抓 DOM 正确但体验错的隐形 bug）

DOM 断言通过了，但按钮被弹窗遮挡 / opacity:0 / 视口外渲染——单测会全绿，生产上用户点不到。三种模态组合断言：

```ts
test('提交订单按钮真的可用', async ({ page }) => {
  await page.goto('/checkout');
  const submit = page.getByRole('button', { name: '提交订单' });

  // 模态 1：语义层（无障碍树）
  await expect(submit).toBeEnabled();
  await expect(submit).toHaveAccessibleName('提交订单');

  // 模态 2：视觉层（位置 + 可见性）
  await expect(submit).toBeInViewport();        // 真在视口内
  await expect(submit).toHaveCSS('opacity', '1'); // 不是透明

  // 模态 3：交互层（Playwright click 自带遮挡检测）
  await submit.click(); // 被遮挡时抛 Element Not Interactable
});
```

### 何时启用双模态

不是所有按钮都要双模态——成本会爆炸。**只对关键操作按钮**用：
- 支付 / 提交订单 / 同意条款 等"用户必须能点到"的元素
- 弹窗里的确认按钮（容易被父层遮挡）
- 浮层 / drawer 上的操作（z-index 问题高发）

普通元素 `expect(...).toBeVisible()` 就够。

### 关键断言

| API | 抓什么 bug |
|---|---|
| `toBeInViewport()` | 元素渲染了但在视口外（fixed 错位、滚动失败） |
| `toHaveAccessibleName(s)` | 按钮没文字 / icon-only 没 aria-label |
| `toHaveCSS('opacity', '1')` | CSS 误把元素隐藏（旧动画状态） |
| `toHaveCSS('pointer-events', /^(auto|inherit)$/)` | `pointer-events: none` 让点击无效 |
| `click({ trial: true })` | 试探能不能点，不真的点（验证遮挡） |

### a11y 自动化

```ts
import AxeBuilder from '@axe-core/playwright';

const results = await new AxeBuilder({ page }).analyze();
expect(results.violations).toEqual([]);
```

需 `@axe-core/playwright`。比手写 a11y 断言全得多——但也更慢，**只对关键页跑**。

## 配合阅读

- `selectors.md`：断言的目标元素怎么定位（`expect(locator)` 里的 locator 走那套优先级）
- `architecture.md`：断言放哪一层（业务结果断言在 spec，UI 细节断言别写进 E2E）
