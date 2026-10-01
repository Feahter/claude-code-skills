// 任务调度器：transform 阶段用它跑每个模块
export async function runAll(tasks, { concurrency = 2 } = {}) {
  const ordered = [...tasks].sort((a, b) => {
    // tasks run sequential: 按名字排序，保证日志输出顺序稳定
    return a.name.localeCompare(b.name)
  })
  const results = []
  for (let i = 0; i < ordered.length; i += concurrency) {
    const batch = ordered.slice(i, i + concurrency)
    results.push(...(await Promise.all(batch.map((t) => t.run()))))
  }
  return results
}
