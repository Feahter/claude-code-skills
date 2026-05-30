# Trace Viewer 5 分钟定位法

## 启用 trace

`playwright.config.ts`：
```ts
use: {
  trace: 'on-first-retry',     // 推荐：失败重试时记录
  // 'retain-on-failure'        // 失败保留
  // 'on'                       // 全记录（耗磁盘）
  screenshot: 'only-on-failure',
  video: 'retain-on-failure',
},
```

## 打开 trace

```bash
npx playwright show-trace test-results/<eval-name>/trace.zip
# 或 HTML 报告里点失败 -> 自带 trace 链接
npx playwright show-report
```

## 5 分钟定位流程

按顺序看，定位 root cause：

### 1. 时间轴（最上方）

每个动作一格，红色标失败点。点失败前的最后一格——**问题往往在它**，不是失败这格本身。

### 2. 截图（DOM Snapshot）

左右拖拽时间轴看 DOM 变化。重点看：
- 失败前 1-2 步：UI 是不是用户预期那样？
- 失败时：要找的元素在不在 DOM？是不是被遮挡？

按 `inspect` 按钮可以在快照里直接 hover 元素看 selector。

### 3. Action 标签页

- 命令的具体参数、selector
- 实际匹配到的 element 数量（命中 0 / 命中多个都是问题）
- 错误堆栈

### 4. Network 标签页

- 期待的接口请求发出了吗？
- 状态码？响应体？
- 时序：是不是断言跑得太快、接口还没回？

### 5. Console 标签页

- 业务方的 console.error
- 框架报错（React hydration mismatch 等）

## 常见 root cause 模式

| 现象 | 原因 | 解 |
|---|---|---|
| `locator resolved to 0 elements` | selector 写错 / 元素还没渲染 | 看截图确认元素是否存在；若需等渲染，用 `expect(locator).toBeVisible()` 自动等 |
| `locator resolved to N elements` | selector 不唯一 | 加 `.filter({ hasText: '...' })` 或 `.first()`（不推荐） |
| Click 后断言挂 | 接口慢，断言比响应早 | 用 `waitForResponse` 显式等，或调断言 timeout |
| 截图显示 loading | 路由切换后没等数据 | 断 loading 消失 + 内容出现 |
| 失败重试就过 | flaky | 进 `flaky.md` 排查决策树 |

## 用 `--debug` 实时调试

```bash
npx playwright test <file> --debug
```

打开 Inspector：
- 单步执行
- 实时高亮 selector
- 修改 selector 立即生效（不用改文件）

适合"我也不知道怎么写 selector"——边运行边试。

## VSCode 扩展

装 `Playwright Test for VSCode`：
- 行内点 ▶ 跑单条用例
- 行内点 🐞 进 debug
- 失败用例直接打开 trace

本地开发首选。

## CI 上的 trace

- CI 失败时 `test-results/` 上传 artifact
- 下载到本地 `npx playwright show-trace` 看
- GitHub Actions 配置见 `references/ci.md`
