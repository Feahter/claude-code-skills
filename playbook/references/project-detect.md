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

## 单测底座（unitTesting）人工探测清单

脚本失效时，单测/集成层的承接判断靠这几项手动填 `project.json.unitTesting`：

| 字段 | 怎么判 |
|---|---|
| `hasVitest` / `hasJest` | deps/devDeps 含 `vitest` / `jest` |
| `unitRunner` | 同时有则 vitest 优先；都没有填 `none` |
| `unitConfigPath` | glob `vitest.config.{ts,js,mts,mjs}` / `jest.config.{ts,js,cjs,mjs}`；都没有但 `package.json` 有 `"jest"` 键 → `package.json#jest` |
| `hasTestingLibrary` / `testingLibFlavor` | deps 含 `@testing-library/react`(react) / `/vue`(vue) / `/dom`(dom) |
| `hasMSW` | deps 含 `msw` |
| `mswHandlersPath` | 看 `src/mocks/handlers.{ts,js}` / `mocks/handlers.{ts,js}` 是否存在（MSW 单一数据源） |
| `unitTestDir` | 找含 `*.test.{ts,tsx}` 的目录，**排除 E2E 目录**，优先 `src` |
| `coverageThresholdsConfigured` | config 内有 `thresholds` / `coverageThreshold` |

这些值决定阶段 2 的分层 backlog 怎么承接：`unitRunner === none` 说明项目还没单测底座，规划单测/集成前先 `scaffold-unit.sh` 搭建。

## 兜底输出

判不出来就先填 `unknown`，然后停下问用户。**不要瞎猜**——错误的探测结果会让阶段 2 决策也错。
