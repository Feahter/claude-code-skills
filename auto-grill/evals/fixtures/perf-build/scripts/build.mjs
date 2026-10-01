import { readdir, readFile, writeFile, mkdir } from 'node:fs/promises'
import { createHash } from 'node:crypto'
import { runAll } from '../src/runner.mjs'

const useCache = process.argv.includes('--cache')
const concurrency = Number(process.env.BUILD_CONCURRENCY ?? 2)
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const t = () => performance.now()
const fmt = (ms) => (ms / 1000).toFixed(2) + 's'

const t0 = t()
// resolve：解析模块图，固定开销，与缓存无关
await sleep(2000)
const files = (await readdir(new URL('../src/modules/', import.meta.url))).filter((f) => f.endsWith('.mjs'))
const t1 = t()

// transform：逐模块转译，--cache 时按内容哈希复用 .cache/ 里的结果
await mkdir(new URL('../.cache/', import.meta.url), { recursive: true })
const tasks = files.map((name) => ({
  name,
  run: async () => {
    const src = await readFile(new URL(`../src/modules/${name}`, import.meta.url), 'utf8')
    const key = createHash('sha1').update(src).digest('hex')
    const cacheFile = new URL(`../.cache/${key}.json`, import.meta.url)
    if (useCache) {
      try { return JSON.parse(await readFile(cacheFile, 'utf8')) } catch {}
    }
    await sleep(400)
    const out = { name, code: src.toUpperCase() }
    if (useCache) await writeFile(cacheFile, JSON.stringify(out))
    return out
  },
}))
const outputs = await runAll(tasks, { concurrency })
const t2 = t()

// bundle：拼接产物，固定开销
await sleep(1500)
await mkdir(new URL('../dist/', import.meta.url), { recursive: true })
await writeFile(new URL('../dist/bundle.txt', import.meta.url), outputs.map((o) => o.code).join('\n'))
const t3 = t()

console.log(`[build] resolve   ${fmt(t1 - t0)}`)
console.log(`[build] transform ${fmt(t2 - t1)}  (modules=${files.length}, concurrency=${concurrency}, cache=${useCache})`)
console.log(`[build] bundle    ${fmt(t3 - t2)}`)
console.log(`[build] total     ${fmt(t3 - t0)}`)
