# CI 集成：分片 + 缓存 + artifact

## GitHub Actions（标准模板）

完整 yml 见 `examples/github-actions.yml`。核心段：

```yaml
strategy:
  fail-fast: false
  matrix:
    shard: [1, 2, 3, 4]
steps:
  - uses: actions/checkout@v4
  - uses: actions/setup-node@v4
    with: { node-version: 20, cache: 'pnpm' }
  - run: pnpm install --frozen-lockfile
  - name: 装浏览器（缓存）
    uses: actions/cache@v4
    with:
      path: ~/.cache/ms-playwright
      key: pw-${{ hashFiles('**/pnpm-lock.yaml') }}
  - run: pnpm exec playwright install --with-deps chromium
  - run: pnpm exec playwright test --shard=${{ matrix.shard }}/4
  - if: always()
    uses: actions/upload-artifact@v4
    with:
      name: playwright-report-${{ matrix.shard }}
      path: playwright-report/
```

## 分片策略

| 用例数 | 分片 |
|---|---|
| < 20 | 不分片（开销 > 收益） |
| 20-100 | 2-4 shards |
| 100-300 | 4-8 shards |
| > 300 | 8+ shards，考虑跨 OS 矩阵 |

公式：`总时长 / shard 数 ≈ 单 shard 时长`，目标 5-8 分钟/shard。

## 缓存清单

| 缓存 | key |
|---|---|
| node_modules | `pnpm-lock.yaml` hash |
| ~/.cache/ms-playwright | `pnpm-lock.yaml` hash（浏览器版本跟着 @playwright/test 走） |
| Next/Vite build cache | `.next/cache` / `node_modules/.vite` |

浏览器装一次省 1-2 分钟，强烈推荐。

## storageState 在 CI 复用

`global-setup.ts` 跑一次登录后存到 `.auth/user.json`，所有 shard 内的用例都用——但**注意 storageState 不跨 shard 共享**（每 shard 独立 job）。

如果 setup 很慢（> 30s），考虑：
1. 抽出 `auth-job`，跑完上传 artifact
2. 各 test shard download artifact 后放到 `.auth/`
3. config 直接指向

```yaml
needs: auth-setup
- uses: actions/download-artifact@v4
  with: { name: auth-state, path: tests/.auth/ }
```

## artifact 上传策略

| artifact | 上传条件 | 留存时间 |
|---|---|---|
| `playwright-report` | 失败时 | 7 天 |
| `test-results/*/trace.zip` | 失败时 | 7 天 |
| `test-results/*/video.webm` | 失败时 | 3 天 |
| screenshot 基线对比 | always | 30 天（基线图） |

```yaml
- if: always()
  uses: actions/upload-artifact@v4
  with:
    name: playwright-report-${{ matrix.shard }}
    path: |
      playwright-report/
      test-results/
    retention-days: 7
```

## merge report（多 shard 合并）

```yaml
merge-reports:
  if: always()
  needs: test
  runs-on: ubuntu-latest
  steps:
    - uses: actions/download-artifact@v4
      with:
        path: all-blob-reports
        pattern: blob-report-*
        merge-multiple: true
    - run: pnpm exec playwright merge-reports --reporter html ./all-blob-reports
    - uses: actions/upload-artifact@v4
      with:
        name: html-report
        path: playwright-report
```

需要 config 改 reporter：`reporter: [['blob']]`（CI 模式）。

## GitLab CI / Jenkins

GitLab：
```yaml
test:e2e:
  parallel: 4
  script:
    - pnpm exec playwright test --shard=${CI_NODE_INDEX}/${CI_NODE_TOTAL}
  artifacts:
    when: always
    paths: [playwright-report/, test-results/]
    expire_in: 1 week
```

Jenkins：用 Pipeline parallel 步骤，原理同上。详细模板按需检索官方文档。

## 失败时只 fail，不阻塞

```yaml
strategy:
  fail-fast: false  # 一片挂不影响其他片
```

让所有 shard 跑完，能更全面看失败模式（是单点还是普遍问题）。
