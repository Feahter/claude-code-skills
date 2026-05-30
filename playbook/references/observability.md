# 测试可观测性：失败 5 分钟定位

普通团队：测试挂了 → 人手翻 trace → 翻 CI 日志 → 找后端同学要 sentry → 1 小时定位。
神级团队：测试挂了 → 一个 traceId 串起前端 trace + 后端日志 + sentry → 5 分钟定位。

核心思想：**测试失败时，自动输出能直接跳到根因的链接，不需要人手拼凑**。

## 三层可观测能力

| 层 | 工具 | 价值 |
|---|---|---|
| Playwright trace | `trace: 'on-first-retry'` | 看用户视角的每一步 |
| 视频 / 截图 | `video / screenshot` | 失败瞬间的画面 |
| traceId 串联 | 自定义 fixture + 注入 header | 一键跳后端日志 |

## Playwright 内置（已在 examples/playwright.config.ts 配好）

```ts
use: {
  trace: 'on-first-retry',       // 失败重试时记 trace
  screenshot: 'only-on-failure', // 失败截图
  video: 'retain-on-failure',    // 失败留视频
}
```

trace 看法见 `references/trace-debug.md`。

## traceId 串联前后端

每个测试生成一个 `traceId`，注入所有请求 header；后端日志也按这个 id 记录。失败时 `report.md` 直接给"看 sentry/grafana 链接 + traceId"。

### Fixture：自动注入 traceId

```ts
// tests/fixtures/trace.ts
import { test as base } from '@playwright/test';

type TraceFixtures = { traceId: string };

export const test = base.extend<TraceFixtures>({
  traceId: async ({ page }, use, testInfo) => {
    const id = `e2e-${testInfo.testId}-${Date.now()}`;

    await page.route('**/*', async route => {
      const headers = { ...route.request().headers(), 'x-trace-id': id };
      await route.continue({ headers });
    });

    // 失败时把 traceId 附到测试报告
    await use(id);
    if (testInfo.status !== testInfo.expectedStatus) {
      testInfo.attachments.push({
        name: 'traceId',
        body: Buffer.from(id),
        contentType: 'text/plain',
      });
      // 可加内部链接：sentry/grafana
      console.log(`[FAIL] traceId=${id}  sentry=https://sentry.internal/?query=${id}`);
    }
  },
});
```

测试里：

```ts
test('下单失败时显示错误', async ({ page, traceId }) => {
  await page.goto('/checkout');
  // ... traceId 已经自动注入到所有请求
});
```

## 后端配合（一句话原则）

后端在 access log / sentry 里按 `x-trace-id` 索引。前端 trace + 后端日志按同一 id 关联，5 分钟定位 = 翻一个搜索框。

## CI 失败时的输出模板

`validate-test.sh` 失败后，`report.md` 输出：

```
❌ tests/order/checkout.spec.ts › 提交订单成功
   traceId: e2e-abc123-1700000000
   trace:   playwright-report/data/abc.zip → npx playwright show-trace
   sentry:  https://sentry.internal/?query=e2e-abc123
   video:   test-results/checkout-提交订单成功/video.webm
```

让人不用思考下一步去哪看。

## 失败定位流程（5 分钟）

1. 看 `report.md` 给的 trace 链接 → `npx playwright show-trace <zip>`
2. trace 里看红色失败步 → 看 Network 标签那一刻的请求
3. 复制请求的 `x-trace-id` → 粘到 sentry/grafana 搜
4. 后端日志直接跳到根因

90% 的 E2E 失败这套流程能在 5 分钟内定位。剩下 10%（环境差异、flaky）走 `references/flaky.md`。

## 神级原则

> "可观测性不是日志多就行，是失败时下一步该做什么不需要思考。"

写测试时永远问：**这条用例挂了，我能在 5 分钟内告诉同事根因吗？** 答不出来就缺可观测性。
