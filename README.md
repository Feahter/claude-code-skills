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
| [loss-analysis](./loss-analysis) | 复盘 Claude Code 历史会话的时间损耗与低效率信号，生成深色主题 HTML 报告 |
| [playbook](./playbook) | 前端自动化测试全层引擎（单元 / 集成 / E2E），编排测试用例的生成与执行 |
| [auto-orchestrate](./auto-orchestrate) | 把跨多文件的代码实现任务自动拆解、分发、收口，串起规划 / 并行 agent / worktree / 收尾全链路 |
| [enforce-workflow-schema](./enforce-workflow-schema) | 把"开始做需求"落到 `.workflow/<task-id>/` 标准目录，强制 spec + plan 与验证证据 |
| [think-rigorously](./think-rigorously) | 把推理 / 分析 / 选型转成证据驱动的结构化思考：先写假设 → 找证伪 → 用代码或数据 ground 判断 |
| [tame-frontend](./tame-frontend) | 资深前端架构师视角的决策辅助：架构设计、状态分层、渲染策略选型、复杂度治理 |
| [prompt-optimizer](./prompt-optimizer) | 优化 prompt 文本（Claude Code 资产或 API 调用），诊断 skill / CLAUDE.md / agent prompt 未生效问题 |
| [metacognition-recall](./metacognition-recall) | 按需从项目记忆库语义召回与当前任务相关的技术事实、偏差、历史决策 |
| [metacognition-reflect](./metacognition-reflect) | 对当前会话做元认知复盘，把关键判断 / 纠正 / 验证事件结构化入队并合并到记忆库 |
| [cr-master](./cr-master) | 资深工程师视角审查本地 git 变更（工作区 / 暂存区 / commit / 分支对比），P0-P3 分级输出 SOLID / 安全 / 竞态 / 错误处理 / 性能 / 边界条件中文报告 |

## 额外依赖

`metacognition-recall` / `metacognition-reflect` 依赖一套 shell/python 脚本，已随 `metacognition-reflect/scripts/metacog/` 一并收录。两个 skill 共享这套脚本，按 SKILL.md 中的运行路径需安装到固定位置：

```bash
cp -R metacognition-reflect/scripts/metacog ~/.claude/scripts/metacog
```

脚本默认按当前项目 cwd 推导记忆目录；如需固定目标，设 `METACOG_DEFAULT_MEMDIR` 环境变量。自动入队（SessionEnd hook）的接法见 `metacognition-reflect/scripts/metacog/probe/README.md`。
