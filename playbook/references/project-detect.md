# 项目探测：脚本失效时的人工清单

`detect-project.sh` 失败时按下面手动填 `.playbook/project.json`。

## 探测维度与判定

| 字段 | 怎么判 |
|---|---|
| `framework` | 见下方"框架特征表" |
| `language` | `tsconfig.json` 存在 → ts；否则 js |
| `packageManager` | `pnpm-lock.yaml` → pnpm；`yarn.lock` → yarn；`bun.lockb` → bun；否则 npm |
| `hasPlaywright` | `package.json` 的 deps/devDeps 含 `@playwright/test` |
| `configPath` | glob `playwright.config.{ts,js,mjs,cjs}` 取第一个 |
| `testDir` | 读 config 里的 `testDir`，没读到则 glob `{tests,e2e,test}/**/*.spec.{ts,js}` 取最常见目录 |
| `baseURL` | 读 config 里的 `use.baseURL`；否则查 dev server 启动脚本 |
| `existingSelectors` | grep 已有 spec：`data-testid` / `getByRole` / `getByText` / `.css-class` 出现频次 |
| `uiLib` | deps 含 `antd` / `@mui/material` / `element-plus` / `naive-ui` / `vuetify` / `shadcn` 等 |

## 框架特征表

| Framework | 特征文件 / 依赖 |
|---|---|
| `next` | `next.config.{js,ts,mjs}` 或 dep 含 `next` |
| `nuxt` | `nuxt.config.{ts,js}` 或 dep 含 `nuxt` |
| `vite` | `vite.config.{ts,js}`，框架由 `@vitejs/plugin-react` / `@vitejs/plugin-vue` 二次判定 |
| `remix` | `remix.config.js` 或 dep 含 `@remix-run/*` |
| `cra` | dep 含 `react-scripts` |
| `astro` | `astro.config.{mjs,ts}` |
| `vue-cli` | dep 含 `@vue/cli-service` |
| `sveltekit` | dep 含 `@sveltejs/kit` |
| `unknown` | 都不命中 |

## dev server 启动方式（推 baseURL）

| 框架 | 默认端口 | 启动脚本 |
|---|---|---|
| next | 3000 | `next dev` |
| vite | 5173 | `vite` |
| nuxt | 3000 | `nuxt dev` |
| remix | 3000 | `remix dev` |
| cra | 3000 | `react-scripts start` |
| astro | 4321 | `astro dev` |
| sveltekit | 5173 | `vite dev` |

读不到 → 翻 `package.json` 的 scripts.dev / scripts.start 找端口。

## 兜底输出

判不出来就先填 `unknown`，然后停下问用户。**不要瞎猜**——错误的探测结果会让阶段 2 决策也错。
