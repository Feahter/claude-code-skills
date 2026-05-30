# Flaky 测试排查决策树

## 定义

**flaky** = 同一份代码、同一份环境，跑 10 次至少 1 次失败。Validate 阶段跑 3 次能粗筛。

## 决策树

按顺序排查，**先 trace 后猜**：

```
失败用例
  ├─ 看 trace（trace-debug.md）
  ├─ 失败前最后一步是什么？
  │   ├─ 网络请求 → 跳到 [网络问题]
  │   ├─ 等元素 → 跳到 [时序问题]
  │   ├─ 断言 → 跳到 [断言问题]
  │   └─ 跨页跳转 → 跳到 [路由问题]
  └─ 失败时 DOM 长什么样？
      ├─ 元素不存在 → [时序问题]
      ├─ 元素被遮挡 → [遮挡问题]
      └─ 元素存在但断言挂 → [断言问题]
```

## 网络问题（最常见，~40%）

| 症状 | 解 |
|---|---|
| 接口慢，断言比响应早 | 用 `waitForResponse` 显式等 |
| 接口偶尔 500 | 在测试环境用 mock 替代 |
| 测试环境 DB 数据共享，并发污染 | 每个用例用独立数据（API 造唯一 ID） |
| 第三方接口（地图、CDN）抖动 | route 拦截后返固定数据 |

## 时序问题（~25%）

| 症状 | 解 |
|---|---|
| 元素从无到有，断言抢跑 | 用 `expect(locator).toBeVisible()` 自带重试 |
| 列表先渲染骨架后填数据 | 等"数据已显示"的具体内容，不等容器 |
| 路由切换动画期间点不到 | 等 URL 变化 + 关键元素可见，再交互 |
| 表单提交后立即查 URL | `await expect(page).toHaveURL(...)` |

**反模式**：上 `waitForTimeout(500)` 治标——validate-test.sh 会拦，必须改对的方案。

## 断言问题（~15%）

| 症状 | 解 |
|---|---|
| 用 `isVisible()` 当断言（不重试） | 改 `expect(locator).toBeVisible()` |
| 文本含动态内容（时间戳、ID） | 用正则或 `toContainText` |
| 多语言环境文本变 | 改 `getByRole({ name: ... })` 用 a11y name 或 testId |

## 路由问题（~10%）

| 症状 | 解 |
|---|---|
| SPA 路由，URL 变了但 DOM 还没切 | `expect(page).toHaveURL(...)` + 新页关键元素断言 |
| RSC / Streaming，部分内容延迟出现 | 等具体内容元素，不等容器 |

## 遮挡问题（~5%）

| 症状 | 解 |
|---|---|
| toast 盖在按钮上 | 等 toast 消失：`expect(toast).toBeHidden()` |
| Modal 关闭动画期间点穿 | 等 modal 完全 detached |
| sticky header 挡到目标 | scroll 到目标后再点：`locator.scrollIntoViewIfNeeded()` |

## 用例隔离问题（~5%）

| 症状 | 解 |
|---|---|
| 单跑过、批量挂 | 用例间共享 storageState 但有写操作互相覆盖 → 拆角色 / 用独立 storageState |
| 测试数据 ID 冲突 | 用 `Date.now()` / uuid 造唯一数据 |
| `beforeAll` 只跑一次但有副作用 | 改 `beforeEach` |

## 何时用 retries

`playwright.config.ts`：
```ts
retries: process.env.CI ? 2 : 0,
```

**CI 上保留 2 次重试**——第三方依赖抖动是真实存在的。但**本地必须 0**，否则会掩盖 flaky。

⚠️ retries 不是治 flaky 的方法，是兜底。flaky 必须修。

## 修完验证

```bash
# 跑 10 次确认稳定
for i in {1..10}; do npx playwright test <file> --reporter=line || break; done
```

10 次全过才算修好。
