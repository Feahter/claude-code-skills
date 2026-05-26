---
name: loss-analysis
description: 复盘 Claude Code 历史会话的时间损耗与低效率信号，扫描 ~/.claude/projects/**/*.jsonl 提取真用户纠正、工具失败、重复 Read、串行探索、未验证完成声明、自动压缩等指标，按"现象+原因+方案+成本"四段式生成深色主题 HTML 报告写入 ~/Documents/md/，并自动用默认浏览器打开预览。当用户说"复盘损耗 / 时间损耗 / 任务效率分析 / Claude 协作复盘 / 历史会话审计 / 帮我看看最近任务效率 / 我想知道哪些任务跑得慢 / Claude 哪里浪费时间 / 协作低效问题"等时主动触发。即使用户没明确说"复盘"，只要意图涉及评估自己与 Claude 历史协作的效率/质量/痛点，也应触发。不适用于：单次对话的当下问题排查（用 diagnose）、代码审查（用 code-review-expert）、本会话元认知复盘（用 metacognition-reflect）。
---

# 任务时间损耗复盘

把 Claude Code 的会话日志当作"协作录像"回看，定位那些用户不会主动报告但实际浪费时间的"水下"问题。

## 何时使用

触发关键词包括但不限于：

- "复盘损耗 / 时间损耗 / 任务效率分析"
- "Claude 协作复盘 / 历史会话审计"
- "帮我看看最近任务效率 / 哪里浪费时间 / 哪些低效"
- "我想知道 Claude 哪里跑得慢 / 哪些反复返工"

跟相邻 skill 区别：

- 排查当下某个 bug 或性能问题 → `diagnose`
- 评审本次代码改动 → `code-review-expert`
- 沉淀本次对话的经验/偏差 → `metacognition-reflect`
- 本 skill 关注**跨会话、跨天**的协作模式问题

## 主流程

整个流程分四步，主会话承担问询与报告生成，重活交给离线 python 脚本——**这是关键设计**：jsonl 日志体量大（30 天通常 50-100MB），不能直接读进上下文，必须通过脚本抽出 JSON 摘要再消化。

### 第 1 步：用 AskUserQuestion 收集 4 个前置参数

提一次问，4 题一起，避免反复打断用户。每题选项控制在 ≤4 个（AskUserQuestion 的硬约束）。

模板：

| 题目 | header | 选项 |
|---|---|---|
| 数据源 | 数据来源 | Claude 会话日志（推荐）/ 某个项目的 git 历史 / 自己整理的任务清单 / Claude 会话 + git 交叉对比 |
| 关注维度（多选） | 关注维度 | 工具调度低效 / 上下文与会话管理 / Claude 误判与返工 / 协作模式问题 |
| 时间窗 | 时间窗口 | 最近 7 天 / 最近 30 天（推荐）/ 全部历史 |
| 颗粒度 | 颗粒度 | Top-N 高损耗事件清单（推荐）/ 宏观分类统计 + 典型案例 / 两者都要 |

如果用户选了非 "Claude 会话日志"（比如 git 历史），本 skill 不适用，告诉用户走对应工具，结束。

### 第 2 步：跑扫描脚本

调用 `scripts/scan.py`，参数根据用户选择填：

```bash
python3 ~/.claude/skills/loss-analysis/scripts/scan.py --days 30 --output /tmp/claude-loss-analysis/raw.json
```

可选参数：

- `--days N`：时间窗（用户选 7 → 7；选全部 → 99999）
- `--output PATH`：JSON 输出路径，默认 `/tmp/claude-loss-analysis/raw.json`
- `--cwd-filter SUBSTR`：仅统计 path 含某子串的会话（比如只看某个项目）

脚本会同时打印一份 stdout 摘要（核心指标），并把详细 JSON 写到 output。**只读 stdout 摘要**作为是否需要展开 raw.json 的依据；详细数据在生成报告时按需读 raw.json 的对应字段。

### 第 3 步：消化 JSON 生成 HTML 报告

打开 `assets/report-template.html` 作为骨架（深色主题、自包含、所有样式内联，复制到任何浏览器都能直接看）。**直接替换 `{{xxx}}` 占位符**生成最终 HTML，不要改样式/结构。占位符未用到的整段（比如某指标没数据）直接删掉，不要留 `{{}}` 在最终页面里。

按用户在第 1 步勾选的"关注维度"决定章节去留：

- 工具调度低效 → 写"探索串行""重复 Read""工具失败"事件
- 上下文管理 → 写"压缩频率""会话过长"事件
- Claude 误判与返工 → 写"用户纠正""完成声明无验证""回滚信号"事件
- 协作模式 → 综合诊断 + 改动建议章节强化

按用户选择的颗粒度调整篇幅：

- "Top-N" → 重点写 5-10 个具体事件，每个事件按"现象 / 原因 / 方案 / 成本"四段，宏观数据缩到一张表
- "宏观分类" → 反过来：详尽的指标矩阵 + 每类挑 1-2 个代表案例
- "两者都要" → 全量

每个事件块用 `<div class="event">` 包裹，按严重度选 class：

- 默认（黄）：警示但非紧急
- `priority-high`（红）：高损耗事件，建议优先处理
- `priority-low`（绿）：已处于良好水位，作为正面案例

### 第 4 步：写文件 + 自动唤起浏览器预览

文件名固定格式 `YYYY-MM-DD-claude-task-loss-analysis.html`，写入 `~/Documents/md/`。

写完立刻执行（macOS）：

```bash
open ~/Documents/md/YYYY-MM-DD-claude-task-loss-analysis.html
```

`open <file>` 会用系统默认浏览器打开本地 HTML 文件，不依赖任何 server。Linux 等价命令是 `xdg-open`，Windows 是 `start`，但本 skill 默认环境是 macOS，直接用 `open` 即可。

写完后给用户一段简洁回执：

- 报告路径（已自动打开浏览器预览）
- 最值得改的 2-3 件事（不要重复报告全文，直接挑出最大杠杆项）
- 原始 JSON 路径，供用户后续按其他维度复看

## 报告核心原则

**事件四段式**：每个被点名的高损耗事件必须按这个结构写——

1. **现象**：可量化的具体数字 + 1-2 个真实样本（从 `correction_examples` / `unverified_examples` 等字段挑）
2. **原因**：根因分析，避免泛泛而谈"沟通不够"，要落到具体规则违反或习惯偏差
3. **方案**：具体到可执行级别，区分"流程改进"和"工具/hook 兜底"
4. **成本**：实现这个方案要花多少时间/精力，给用户判断优先级的依据

**忠诚于数据**：所有数字必须来自 raw.json，不要杜撰。如果某项指标为 0 或太低不值得专门写一节，直接合并到综合诊断里说一句即可。

**用户视角排序**：Top-N 列表按"时间损耗规模"排，不是按出现频次。比如 50 段串行长链虽然不如 154 次工具失败"次数多"，但累计等待时间反而更可观。

## 资产说明

```
loss-analysis/
├── SKILL.md
├── scripts/
│   └── scan.py              # 扫描脚本，参数化时间窗 / cwd 过滤
└── assets/
    └── report-template.html # 深色主题 HTML 报告骨架，自包含样式
```

`scripts/scan.py` 是核心。它已经处理好了几个容易踩的坑：

- 系统注入消息（`This session is being continued`、`<SUBAGENT-STOP>`、`Stop hook feedback` 等）会污染"用户纠正"信号，脚本会过滤
- tool_result 伪装成 user 消息，脚本也会识别
- 探索类工具串行段统计要排除被 tool_result 打断的情况

如果将来需要加新的指标维度，在 `scan.py` 里扩展 Counter 字段并在 `out` dict 里输出即可，主会话端只需相应更新模板。
