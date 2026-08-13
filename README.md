# claude-code-skills

个人 Claude Code skills 备份库。每个子目录是一个独立 skill，包含 `SKILL.md` 与可选的 `scripts/` `assets/` 资产。

## 安装方法

```bash
# 把目标 skill 软链到 ~/.claude/skills/ 即可
ln -s "$(pwd)/<skill-name>" ~/.claude/skills/<skill-name>
```

或直接复制：

```bash
cp -R <skill-name> ~/.claude/skills/
```

## 已收录

| Skill | 用途 |
|---|---|
| [loss-analysis](./loss-analysis) | 复盘 Claude Code 历史会话的效率问题，扫描会话日志提取工具失败 / 用户纠正 / 重复读取 / 上下文压缩等指标，生成带证据与数据口径的 HTML 报告 |
| [playbook](./playbook) | 前端自动化测试全层引擎（单元 / 集成 / E2E），编排测试用例的生成与执行 |
| [auto-orchestrate](./auto-orchestrate) | 多任务编排器：独立 lane 并行、有依赖同 lane 串行，每个工作单元独立审查后汇入 integration 分支，不自动合入目标分支 |
| [craft](./craft) | 单个编码任务的自包含质量闭环：侦察 → 极简实现 → 内联清理 → 自审分流 → 风险验证 → 提交与证据，是 `auto-orchestrate` 的下游执行单元 |
| [e2e-test-quality](./e2e-test-quality) | 审核 E2E 测试代码与用例质量：工程层 / 用例层判断标准、反模式清单、100 分量化评分卡、覆盖度评估 |
| [enforce-workflow-schema](./enforce-workflow-schema) | 把"开始做需求"落到 `.workflow/<task-id>/` 标准目录，强制 spec + plan 与验证证据 |
| [think-rigorously](./think-rigorously) | 把推理 / 分析 / 选型转成证据驱动的结构化思考：先写假设 → 找证伪 → 用代码或数据 ground 判断 |
| [tame-frontend](./tame-frontend) | 资深前端架构师视角的决策辅助：架构设计、状态分层、渲染策略选型、复杂度治理 |
| [prompt-optimizer](./prompt-optimizer) | 优化 prompt 的触发、结构与文风，覆盖 skill description / agent prompt / CLAUDE.md / Output Style / command-hook / Anthropic API prompt，可只审计也可直接改文件 |
| [metacognition-recall](./metacognition-recall) | 按需从项目记忆库语义召回与当前任务相关的技术事实、偏差、历史决策 |
| [metacognition-reflect](./metacognition-reflect) | 对当前会话做元认知复盘，把关键判断 / 纠正 / 验证事件结构化入队并合并到记忆库 |
| [cr-master](./cr-master) | 资深工程师视角审查本地 git 变更（工作区 / 暂存区 / commit / 分支对比），P0-P3 分级输出 SOLID / 安全 / 竞态 / 错误处理 / 性能 / 边界条件中文报告 |
| [rxjs-master](./rxjs-master) | RxJS / Observable 响应式编程专家：操作符选型、订阅管理与内存泄漏、错误处理与重试、marble 测试、性能调优、Promise 互转、Angular Signals / React hooks 互操作 |
| [code-to-product-knowledge](./code-to-product-knowledge) | 从代码逻辑反向沉淀产品认知文档，产出 know-what 风格的产品行为 / 规则 / 边界 / 设计意图，代码读不出的盲区停下来逆问用户 |
| [test-strategist](./test-strategist) | 测试策略师：把需求 / 变更 / 事故转成有证据的风险台账与可执行验证义务（含 oracle、处置决定、优先级），产出 schema 校验过的策略包交给 `playbook` 落地 |
| [goal-plan](./goal-plan) | 把一句话想法写成 agent 能独立跑完的目标任务书：先实测再提问，产出含实测数字、白名单地界、防作弊验收与断点续跑的 brief |
| [clean-stale-branches](./clean-stale-branches) | 按 `user.email` 过滤，清理 N 天外的本地与远端分支：已合并的先安全删，未合并的列清单待确认，远端删除二次确认，支持 dry-run 与 reflog 恢复 |
| [night-run](./night-run) | macOS 全局防睡眠开关，用一条后台 caffeinate 让长任务不被系统睡眠冻结，与会话解耦 |

## Skill 之间的配合

- `auto-orchestrate` 是父编排器，把任务拆成 lane 后以 `owner: craft` 派发；`craft` 负责单个工作单元的实现与自证。两者建议成对安装，单独装 `auto-orchestrate` 会让派发目标悬空。
- 测试三角：`test-strategist` 决定**测什么**（风险与优先级），`playbook` 决定**怎么测**（分层、写法、稳定性），`e2e-test-quality` 决定**测得好不好**（打分与验收）。三者互相按绝对路径引用对方的 references 做单一事实源，建议整套安装；只装其中一个可用，但跨 skill 的引用会指向不存在的路径。
- `metacognition-reflect` 写入记忆，`metacognition-recall` 按需召回，共享同一套脚本。

## 额外依赖

`metacognition-recall` / `metacognition-reflect` 依赖一套 shell/python 脚本，已随 `metacognition-reflect/scripts/metacog/` 一并收录。两个 skill 共享这套脚本，按 SKILL.md 中的运行路径需安装到固定位置：

```bash
cp -R metacognition-reflect/scripts/metacog ~/.claude/scripts/metacog
```

脚本默认按当前项目 cwd 推导记忆目录；如需固定目标，设 `METACOG_DEFAULT_MEMDIR` 环境变量。自动入队（SessionEnd hook）的接法见 `metacognition-reflect/scripts/metacog/probe/README.md`。

> 备注：本仓库收录的 `metacog` 脚本与本地 `~/.claude/scripts/metacog` 已出现分叉（双方各有独占文件，共有文件内容也不同），尚未确认哪一侧是当前在用版本。同步前请先逐个比对，不要直接覆盖。

`test-strategist` 的并行执行器 `~/.claude/agents/custom/test-risk-scanner.md` 是本机 agent 定义，不在本仓库内。缺它不影响主流程——它只用于「一次扫多个互不依赖的模块」和「对已产出策略包做反方复核」两种场景，单模块分析本来就应该由主会话直接走 skill。

## 脱敏说明

仓库版本对公司项目名做了占位替换，与本地实际运行版本存在预期内的差异，同步时不要反向覆盖：

- `enforce-workflow-schema` / `tame-frontend`：项目名与领域 skill 名替换为 `your-app` / `<domain-feature>` / `<chain-integration>`，Jira 前缀替换为 `PROJ-`。
- `loss-analysis/scripts/test_scan.py`：测试用例里的仓库名替换为 `demo-app`。
- `test-strategist/evals/`：实测样例中的内部包名与主项目替换为 `@scope/utils` / `shared-utils` / `main-app`，技术细节（函数名、选项名、行号）原样保留，替换后门禁脚本仍通过。
