# Eval：怎么判断这个 skill 值不值得留

本机有过一次教训：一套 5343 行的自建元认知管线，跑了很久产出 0 条，最后整体退役，根因是**有触发入口但没有执行路径**。这份 eval 存在的唯一目的，是让 test-strategist 的生死由数字决定，而不是由「看起来很专业」决定。

## 判定口径

对照组是**不用本 skill，直接把同一份输入交给 `playbook`**。只比下面四个数，别比「产出了多少条风险」——那个数越大越可疑。

| 指标 | 怎么算 | 及格线 |
|---|---|---|
| **高影响风险命中率** | 事后已知的真问题中，本 skill 事前识别出的比例 | 明显高于对照组，否则没有存在价值 |
| **无证据风险比例** | `evidence` 为 `assumption-no-evidence` 的风险 / 总风险 | < 30%。超了说明在编，该回去读代码 |
| **义务可执行比例** | 工程师判定「照这条能直接写出测试」的义务 / 总义务 | > 80% |
| **额外耗时** | 本 skill 这一步花的时间 | 与它省下的返工不成比例时，退回 quick 模式或退役 |

**退役条件**：连续若干个真实任务里，命中率不高于对照组，或产物没有被下游采纳（没有测试回填 `risk_id`、没有 `design-fix` 被执行）。这时候正确动作是砍掉或缩小范围，**不是加长 prompt**。

## 样例现状

诚实说明：真正的 golden eval 需要「历史 diff + 已知逃逸缺陷」的配对数据，这类数据只能从真实事故记录里来，无法凭空造。当前只有种子样例，**规模不足以做统计意义上的对照**。

| 文件 | 性质 | 用途 |
|---|---|---|
| `golden/example-package.yaml` | 构造样例（退款重试场景） | 字段填写的标准形态参考 |
| `golden/case-001-shared-utils-lessconfig.yaml` | **真实实测产物** | 回归基线 |

### case-001 的实测记录（2026-08-11）

输入：`shared-utils` commit `3a34a63`（NumberFormatter 支持 lessConfig 极小值处理）。

走完六步后实测发现，并用 jest 实跑验证：

```
[percent + lessConfig]       => "<+1.00%"      ← 双符号
[percent + lessConfig (neg)] => ">-+1.00%"     ← 三重符号
[sign:"always" + lessConfig] => "<+0.01"
```

另外查出 `package.json` 的 `scripts.test` 是 `tsc -noEmit`，装了 jest 30 但默认测试命令不执行任何断言，而该包被主项目 `main-app` 依赖。

同时**排除了三条我一开始怀疑但证据不支持的风险**：`lessBoundary` 为 0 / 负数 / NaN 时分支都不触发（实测走原逻辑），递归已用 `lessConfig: undefined` 剥掉不会无限递归。这三条被丢掉而不是留在报告里凑数——这正是 `evidence-discipline.md` 要求的动作，也是这条样例作为基线的价值所在。

**回归用法**：流程或方法卡改动后，用同一个 commit 重跑，至少应仍然识别出 R-01（符号拼接）与 R-04（测试命令不执行断言）。如果重跑后识别不出，说明改动弄坏了什么。

## 怎么积累真实样例

每次真实使用后，把产物存进 `golden/`，命名 `case-NNN-<项目>-<主题>.yaml`，并在文件头注明输入（仓库 + commit / 需求文档 / 事故编号）。

**最有价值的样例是逃逸缺陷**：线上出了问题，拿出事前那次变更的 diff，看本 skill 当时能不能识别出来。这类样例一条胜过十条构造样例，因为它有客观的正确答案。

积累到 10 条以上真实样例时，才有条件做顾问建议的盲测对照。在那之前，这份 eval 只能做回归检查，不能证明价值——**这个限制要在汇报时说清楚，不要拿两条种子样例声称验证了效果**。

## 跑门禁

```bash
bash ~/.claude/skills/test-strategist/scripts/validate-package.sh <策略包.yaml>
```

批量检查所有样例：

```bash
for f in ~/.claude/skills/test-strategist/evals/golden/*.yaml; do
  echo "--- $(basename "$f")"
  bash ~/.claude/skills/test-strategist/scripts/validate-package.sh "$f"
done
```
