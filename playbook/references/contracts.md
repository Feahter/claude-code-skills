# 架构守护契约（可选）

普通测试验证"功能对不对"，架构契约测试验证"实现方式对不对"——防止技术债在测试绿灯下持续扩散。

**这是可选维度**，只在以下情况启用：
- 项目有性能 SLO（首屏 < 2s、bundle < 500KB）
- 项目有依赖白/黑名单（已迁移 lodash → es-toolkit、禁用某些第三方）
- 项目有安全要求（限制外部域名）

不要无脑给所有项目加，会变成另一种维护负担。

## 契约一：bundle 大小

```ts
import { test, expect } from '@playwright/test';

test('首页资源传输 < 500KB', async ({ page }) => {
  const transferSizes: Record<string, number> = {};
  page.on('response', async resp => {
    const len = Number(resp.headers()['content-length'] || 0);
    if (len) transferSizes[resp.url()] = len;
  });

  await page.goto('/', { waitUntil: 'networkidle' });

  const total = Object.values(transferSizes).reduce((a, b) => a + b, 0);
  expect(total).toBeLessThan(500 * 1024);
});
```

或者用 `bundlesize` / `size-limit` 在构建期管。E2E 这层只在"首屏请求总和"层面兜底。

## 契约二：外部域名白名单

```ts
test('首页只走允许的外部域', async ({ page }) => {
  const externalHosts = new Set<string>();
  page.on('request', req => {
    const u = new URL(req.url());
    if (!u.hostname.includes('localhost') &&
        !u.hostname.endsWith('.mycompany.com')) {
      externalHosts.add(u.hostname);
    }
  });

  await page.goto('/');

  const allowed = new Set(['cdn.jsdelivr.net', 'fonts.gstatic.com']);
  const unexpected = [...externalHosts].filter(h => !allowed.has(h));
  expect(unexpected).toEqual([]);  // 未授权域 → 失败
});
```

价值：防止有人偷偷加了第三方分析脚本 / 广告 SDK，靠人工 review 容易漏。

## 契约三：禁用依赖

```ts
test('打包产物不应包含 lodash', async ({ page }) => {
  const jsUrls: string[] = [];
  page.on('response', resp => {
    if (resp.url().endsWith('.js') && resp.status() === 200) {
      jsUrls.push(resp.url());
    }
  });

  await page.goto('/');

  for (const url of jsUrls) {
    const body = await page.request.get(url).then(r => r.text());
    // lodash 的特征字符串（按你们项目实际选）
    expect(body, `${url} 含 lodash`).not.toContain('var lodash');
  }
});
```

注意：现代打包会把变量名压缩，靠字符串匹配不太可靠。更靠谱的做法是 `eslint-plugin-import` 配 `no-restricted-paths` / `no-restricted-imports`，CI 跑 lint 拦。E2E 只在"打包产物层"做兜底。

## 契约四：核心页 a11y 零违规

```ts
import AxeBuilder from '@axe-core/playwright';

test('首页 a11y 零违规', async ({ page }) => {
  await page.goto('/');
  const results = await new AxeBuilder({ page })
    .withTags(['wcag2a', 'wcag2aa'])
    .analyze();
  expect(results.violations).toEqual([]);
});
```

需 `@axe-core/playwright` 依赖。a11y 违规多的页面可以用 `.disableRules(['color-contrast'])` 临时放过，逐步收紧。

## 契约五：性能预算（Core Web Vitals）

```ts
test('首页 LCP < 2.5s', async ({ page }) => {
  await page.goto('/');
  const lcp = await page.evaluate(() => new Promise<number>(resolve => {
    new PerformanceObserver(list => {
      const entries = list.getEntries();
      resolve(entries[entries.length - 1].startTime);
    }).observe({ type: 'largest-contentful-paint', buffered: true });
  }));
  expect(lcp).toBeLessThan(2500);
});
```

CI 上跑要注意机器性能波动，建议设宽松上限（如 3000ms）+ 看趋势，不要严卡。

## 何时不该上契约测试

- 项目还没稳定（每周大改）→ 契约会一直被动改，没价值
- 没有人持续维护 → 写完没人看，绿不绿都没人理
- 替代方案更好（lint/CI 工具）→ 优先用专门工具

契约测试的价值是 **"没人去守的边界，让 CI 自动守"**。守边界的工具如果已有（bundlesize / eslint），就别用 E2E 重复造。

## 在 playbook 里的位置

契约测试**不进默认 test-plan**，单独放 `tests/contracts/`：

```
tests/
├── e2e/         # 业务流程测试（核心）
├── contracts/   # 架构契约（可选）
└── visual/      # 视觉回归（可选）
```

CI 上可以独立 job 跑，失败不阻断主流程，只发 PR comment。
