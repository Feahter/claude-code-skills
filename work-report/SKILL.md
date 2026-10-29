---
name: work-report
description: 生成每日或每周工作报告草稿，日报可自动发到 Slack。扫描本地各仓库本人的 commit（默认排除 acme-agent、cc-taskboard），用 headless claude 归纳成给主管和团队看的概要，格式为纯数字编号加每条一句话加句末状态标注。日报扫当天、发到「#team-web-前端」当天的「每日工作任务统计」thread，launchd 工作日 17:30 触发；周报以本周日报草稿为主线、全周 commit 补漏，先出一段按工作量和时间跨度排序的本周主线总结、再列不设上限的工作明细，只落本地草稿由人工过目再发，launchd 周五 17:40 触发。触发场景：要求出今天的日报或本周的周报（中英文同理）；手动补跑一次定时任务；报告没发出去要排查；要调整定时、格式、排除仓库、发送目标。不适用于：月报、季度总结（用 quarterly-review）、他人的工作汇总、前端问题周报（那是 TeamBot 侧的 frontend-issue-weekly 系列，走 Confluence）。
---

# Work Report（每日与每周工作报告）

把本地仓库的 commit 素材归纳成贴合团队 Slack 格式的报告草稿。日报和周报共用一套采集、
归纳与发送管线，`period` 参数（`daily` / `weekly`）决定周期。

合并成一份的理由：三个主脚本里真正与周期有关的只有报告目录、模版结构、条数上限、状态词表和发送目标，
其余（作者匹配、三档合并状态、发版分支识别、超时熔断、失败回退、幂等与体积保险）完全共用。
拆成两套就要把下面各节记录的坑（合并状态判定、发版分支正则、stash 污染、超时熔断、失败回退）维护两遍，漂移的那一份会静默出错。

## 两个周期的差别

除下表之外的一切都相同。

| | 日报 | 周报 |
|---|---|---|
| 素材 | 窗口内本人 commit | 本周日报草稿（主线）+ 全周 commit（补漏） |
| 增量窗口起点 | 上一份日报的生成时刻 | 上一份周报的生成时刻 |
| 首次运行兜底窗口 | 当天 00:00 | 本周一 00:00 |
| 结构与条数 | 只有编号明细；单仓库 3-6 条，跨仓库每仓 3-4 条、全篇 ≤8 条 | 主线段 3-5 条 + 明细段不设上限 |
| 跟版状态词 | 【今日跟版】 | 【跟版中】 |
| commit body | 每条留 6 行 | 每条留 2 行（主线来自日报草稿，body 只做补漏提示，省体积换归纳速度） |
| 归纳超时 | 300 秒 | 900 秒（2026-09-15 实测 2 天素材 21 KB 耗 259 秒；2026-09-18 五天素材 63 KB 撞破 600 秒，加上主线段后输出更长） |
| 草稿目录 | `~/.claude/reports/daily/` | `~/.claude/reports/weekly/` |
| 发送 | 自动发 Slack thread | 默认不发，只落草稿 |
| 定时 | launchd 周一至周五 17:30 | launchd 周五 17:40 |

周报把日报草稿当主线而不是从 commit 重推，是因为草稿已经凝练过一次、合并状态也已判定；
commit 段留着补两种漏：某天没跑日报，以及日报每天限 3-6 条时被砍掉的次要工作。
归纳失败回退成原始素材的那些草稿不进周报素材（体积大、含文件名，且内容 commit 段已覆盖）。

## 产物格式

日报参照团队 thread 里其他人的实际写法：纯编号，一条一句话，不分层。

```
<仓库名>                    ← 仅跨 2+ 仓库时输出，单仓库省略
1. <功能模块>：<改动内容>【状态】
2. ...

*发送工具* <@U0CLAUDEXXX|Claude>
```

周报在明细之外多一段主线总结，2026-09-20 用户要求加的，两段都必须有：

```
*本周主线*

<主线名>（<时间跨度>，<提交次数>）：<整周做到哪一步，留下什么。没完的说清卡在哪。>

<第二条主线>……

*工作明细*

<仓库名>
1. <功能模块>：<改动内容>【状态】
2. ...

*发送工具* <@U0CLAUDEXXX|Claude>
```

**完整的表达规范是 `generate.sh` 里的 `COMMON_STYLE`，那里是唯一事实源，本文档不复制。**
改口径改那一段，两个周期自动一致。要点：语序是「功能模块：改动内容」，模块在前、改动在后，
中间用中文冒号，模块名取 4 到 8 字的业务或环节短名，不拿仓库名充当；每条 30 字以内（含模块
前缀）；一条只讲一个动作；只写做了什么和结果，不写机制和原因；动词要具体（修了、删了、补了、
跑完），不用「优化」「完善」「梳理」这类看不出做了什么的词；状态只由句末方括号承担，句子里
不再重复。

凝练对照（改前取自 2026-09-09 那份写得过长的日报，问题都是把机制写进了句子；改后一并按
「模块在前」的语序写，两个维度各看一遍）：

| 改前 | 改后 |
|---|---|
| 修了 follow-icon 采集器间歇采到 0 行整次报废，补上等接口首批数据的闸门，接口失败拆成 7 种诊断信号 | follow-icon 采集器：修了间歇采不到数据 |
| 修掉详情页 tab 覆盖测出的 18 条实现偏差，含链价未就绪时渲染成 Infinity、代币数为 0 时饼图写进 NaN，18 条台账与对账数字一并对齐 | 详情页 tab：修掉测出的 18 条实现偏差 |
| 把被 Next 当页面收集的测试文件挪出路由目录，解开构建挂在收集页面数据阶段的故障 | 构建流程：修好测试文件放错目录导致的挂住 |
| 采集器样本量改成按平台各自计数，避免多数派铺满、少数派只采到 1 个就收工 | 采集器样本量：改成按平台各自计数 |

模块前缀带来两种新错法，2026-09-16 实测撞到，`COMMON_STYLE` 已各加一条挡住。一是为压短模块名
把范围丢掉：素材是「Arc 持有者/交易者余额按 native token 精度换算」，归纳写成
`Arc 链余额显示：修复余额被放大 1e12 倍的精度错误`，持有者和交易者这个范围没了，而范围属于
「做了什么」不是机制。二是把根因数据当成关键数字：`1e12 倍`是放大倍数，成果规模才算关键数字。
应写`Arc 链余额显示：修了持有者和交易者的精度错误`。

周报额外有三条日报没有的要求：

1. **同一件事连做几天必须合成一条，按整周终态写**。判断是不是同一件事看对象不看措辞——同一个
   模块、同一个采集器、同一批用例就是一件事。
2. **主线段按工作量和时间跨度综合排序**：先看提交次数与改动规模，再看覆盖几天，量大又跨天多的
   放最前面，两样都小的放最后。不按仓库排，也不按日期排。仓库分组的顺序同理。每条主线括号里带
   规模（覆盖几天、多少次提交），数不出来就不写，不要估。
3. **明细段不设条数上限**，本周所有有实质产出的工作都要列到，不因为篇幅砍掉；但同一件事、同一
   模块该合的还要合，不设上限不等于把 commit 逐条抄下来。

2026-09-18 那份周报是手工重排的样例：主线排成「测试基建 28 次提交 5 天 → 规范与上下文 16 次
5 天 → 测试仓修红与闸门 11 次 3 天 → 循环依赖 5 次 2 天 → 业务缺陷 2 次 2 天」，明细 34 条。

## 状态标注

按 commit 实际走到哪一步映射研发流程阶段，全部用中文状态词：

| 状态 | 判据 |
|---|---|
| 【已完成】 | commit 已在主干（collect.sh 探测 `main` / `master` / `develop`，用 `merge-base --is-ancestor` 判定） |
| 【今日跟版】日报 / 【跟版中】周报 | 没进主干，但已在发版分支（`acme-<MMDD>` / `release/*`）——活已经进了本次要发的版本，在等发布 |
| 【测试中】 | 没进发版分支，但已合到 `origin/pre`——在测，还没跟版。日报周报同一个词 |
| 【开发中】 | 只在特性分支，或素材显示还在改 |
| 【待提测】 | 素材明确提到待测试/待提测 |
| 【开发中】+卡点 | 素材提到在等他人，状态后紧跟一句，如「等待合并」「等待后端提供接口」 |
| 百分比 | 长周期任务素材里有进度线索，直接写 `70%` |

判定顺序从已发布往未发布走，命中即止，所以同时在主干和发版分支上的 commit 报【已完成】。
一条报告合并的多个 commit 状态不一致时取最靠后那档（已完成 → 跟版 → 测试中 → 开发中）。
周报跨整周，一件事周一在开发、周五已进主干，写【已完成】。
判断不了用【开发中】。宁可保守，不把没进主干的写成已完成，也不把只进了 pre 的写成跟版。

**pre 不算发版分支**：collect.sh 把 `pre` 单列成测试分支一档，合到 pre 只说明在测（【测试中】），
进了发版分支才算跟版。判定顺序是主干 → 发版分支 → 测试分支 → 特性分支。

**发版分支的识别正则必须锚定完整分支名**：`^origin/(acme-[0-9]{4}|release/.+)$`。
main-app 走 feature → `acme-<MMDD>` → `master` 的流程，而该仓库另有 90 个把版本号或 `pre`
写进名字的特性分支（`feat/security-lp-check-tip-acme-0824`、`perf-tooltip-pre` 等）。
不锚定会把它们全吃成发版分支，一条还在自己分支上改的工作就被标成已跟版。

## 组件

| 组件 | 路径 | 作用 |
|---|---|---|
| 采集脚本 | `~/.claude/scripts/work-report/collect.sh [period]` | 先并行 `git fetch` 各仓 origin（限时，失败只告警），再扫描 `~/projects/*` 窗口内本人 commit（`--no-merges`）+ diffstat + body + 三档合并状态与该写的状态词；调 summarize.py 附规模统计段；明细按工作量排序；周报另附本周日报草稿段；无素材返回 exit 10 |
| 归纳主脚本 | `~/.claude/scripts/work-report/generate.sh [period]` | 采集 → `claude -p` 归纳 → 落草稿 + 系统通知；归纳失败回退原始素材；`WORK_REPORT_AUTOSEND=1` 时接着调 send.sh |
| 规模统计 | `~/.claude/scripts/work-report/summarize.py <data> <order> <period>` | 算每仓与每主题的提交数、新增行数、覆盖天数与状态分布，输出统计段；同时给出仓库工作量排序，决定明细分组顺序 |
| 草稿自检 | `~/.claude/scripts/work-report/lint-draft.py <draft> <period>` | 查两段结构、主线条数与规模、状态词是否串周期、每条是否 ≤30 字、署名；只报不改，结果写进草稿本地注脚 |
| 发送脚本 | `~/.claude/scripts/work-report/send.sh [period]` | 剥离草稿本地标记 → 定位当天 thread → `chat.postMessage` 发到 thread；带幂等、体积保险与失败通知；未配置发送目标时 exit 0 静默跳过 |
| 日报定时器 | `~/Library/LaunchAgents/com.fez.daily-report.plist` | 周一至周五 17:30 触发 `generate.sh daily`，环境变量带 `WORK_REPORT_AUTOSEND=1` |
| 周报定时器 | `~/Library/LaunchAgents/com.fez.weekly-report.plist` | 周五 17:40 触发 `generate.sh weekly`，不带 AUTOSEND（只落草稿） |

## 脚本与模型的分工

2026-09-20 起，凡是能机械判定的都由脚本做完，模型只负责归纳文字：

| 交给脚本 | 在哪 | 原来交给模型的后果 |
|---|---|---|
| 提交次数、覆盖天数、新增行数 | `summarize.py` 的规模统计段 | 从上百条记录里数，数字不可复核也不稳定 |
| 仓库分组顺序 | `collect.sh` 按工作量排好再输出明细 | 模型自行重排，或照抄日报里的顺序 |
| 合并状态 → 状态词 | `collect.sh` 每条 commit 直接给「报告写【X】」 | 「已在发版分支」被写成【已完成】，越级报完成 |
| 过滤 merge commit、收窄 body | `collect.sh` 的 `--no-merges` 与 `BODY_LINES` | 素材虚高四成，2026-09-18 撞破 600 秒超时 |
| 条数、字数、状态词串周期、缺段 | `lint-draft.py`，结果写进草稿注脚 | 人工过目时自己数，容易漏 |

留给模型的是真正需要判断的部分：把 commit 聚成主线、给模块起业务短名、判断同一件事该不该合并、
状态不一致时取哪一档。规模统计段里的「前缀」只是 commit scope，用来分组和数数，不是模块名。

周五两个定时器都会跑，间隔 10 分钟：日报 17:30 起跑、最长约 300 秒落草稿（超时回退原始素材），周报 17:40 采集时
必然能读到当天那份。改动任一时间要保持这个先后关系，否则周报会漏掉周五的工作。

- 草稿输出：`~/.claude/reports/{daily,weekly}/<YYYY-MM-DD>.md`（周报用运行当天日期，通常是周五）
- 运行日志：`~/.claude/logs/work-report.log`（脚本内，行首带 `[daily]` / `[weekly]` 标签）、
  `{daily,weekly}-report.launchd.{out,err}.log`（launchd）
- 2026-09-15 合并之前的日报日志留在 `~/.claude/logs/daily-report.log`，不迁移

## 手动触发

```bash
# 生成日报草稿，不发送（手动跑默认不发，AUTOSEND 只在 launchd 环境开）
bash ~/.claude/scripts/work-report/generate.sh daily

# 只看采集到什么（含规模统计段），不调模型
bash ~/.claude/scripts/work-report/collect.sh weekly | less

# 只对已有草稿跑一遍格式自检
python3 ~/.claude/scripts/work-report/lint-draft.py ~/.claude/reports/weekly/2026-09-18.md weekly

# 生成周报草稿
bash ~/.claude/scripts/work-report/generate.sh weekly

# 只看素材采集结果，不调模型
bash ~/.claude/scripts/work-report/collect.sh weekly

# 预览日报草稿会被发成什么样、以及能否定位到今日 thread，不实际发送
WORK_REPORT_SEND_DRYRUN=1 bash ~/.claude/scripts/work-report/send.sh daily

# 手动发送当天日报草稿（已发过则幂等跳过）
bash ~/.claude/scripts/work-report/send.sh daily
```

周期参数省略时默认 `daily`。

## 自动发送（日报）

发送目标：`#team-web-前端`（`C0XXXXXXXXX`，私有频道），回复到 主管（`U0LEADXXXXX`）当天那条
「每日工作任务统计」thread 下——团队 12 人的日报都发在这个 thread 里，顶层消息在该群是
「有事找人」的语义，不要发顶层。

### token 配置（必需，否则发送环节必失败）

**当前状态（改动前先 `rg -n '^SLACK_TOKEN'` 该文件复核）：`~/.claude/.secrets/slack-daily-report.env` 里的
`SLACK_TOKEN=` 那行仍被注释着，即从未填入真 token，所以自动发送环节一直失败，
日报靠会话用 Slack MCP 人工兜底发出。要恢复全自动，得按下面申请并填入 token。**

**走 MCP 兜底时不要自带署名行**（2026-09-22 实测）：`slack_send_message` 会在正文末尾自动
追加 `*发送工具* <@U0CLAUDEXXX|Claude>`。把草稿原样贴过去会出现两行署名，而该 MCP 没有
编辑或删除消息的工具，发出去就改不了。兜底路径的正文到最后一条明细为止，署名交给 MCP。
另外粗体按标准 markdown 写 `**x**`（MCP 会转成 Slack 的 `*x*`），这点与 send.sh 直连
chat.postMessage 用原生 mrkdwn 不同。发送后写一个 `<报告目录>/.sent-<日期>` 手工补上幂等标记。

为什么不复用 Claude Code 的 Slack MCP（2026-08-24 实测，别再重试）：

| 运行环境 | 结果 |
|---|---|
| 交互 CC 会话里跑 `claude -p --allowedTools "mcp__plugin_slack_slack__*"`（sonnet/默认档） | **可用**，真读真发 |
| 同上但 `--model haiku` | 拿不到 MCP 工具，输出 `UNAVAILABLE` |
| 真实 launchd LaunchAgent（临时 plist + `RunAtLoad` 实测） | 报「Slack MCP 需要先授权，当前会话无法完成 OAuth 流程」 |

MCP 授权只在交互会话派生的进程里继承。补齐 launchd 缺的候选环境变量（`__CF_USER_TEXT_ENCODING` /
`ANTHROPIC_BASE_URL` / `NODE_EXTRA_CA_CERTS` / `COMMAND_MODE`）后仍然 `UNAVAILABLE`，所以这条路
对定时任务是死的，send.sh 用独立 token 直连 Slack Web API。

坑在于验证方式：在交互会话里测会通过，误以为 headless 可行；失败要等第一次定时触发才暴露。
要验只能用临时 plist 在真实 launchd 里跑。

把 token 写进 `~/.claude/.secrets/slack-daily-report.env`（权限 600）：

```
SLACK_TOKEN=xoxp-...
```

要 **User token（`xoxp-`）**，不要 bot token（`xoxb-`）：user token 让消息以本人身份出现，
与团队惯例一致；bot token 会显示成机器人署名。所需 scopes：`chat:write`（发消息）、
`groups:history`（读私有频道历史以定位 thread）。

申请路径：api.slack.com/apps → Create New App → OAuth & Permissions → User Token Scopes
加上述两项 → Install to Workspace。该 workspace 对集成有管控，若安装被拦需找管理员。

### 护栏

| 护栏 | 行为 |
|---|---|
| 未配置目标不发 | channel 或 thread 标记为空时 exit 0 静默跳过（周报默认走这条） |
| 幂等 | 发送成功后写 `<报告目录>/.sent-<日期>`，同日同周期重复运行直接跳过 |
| 归纳失败不发 | 草稿是「归纳失败回退原始素材」版本时拒绝发送（含文件名、体积巨大），转人工 |
| 体积保险 | 正文超 4000 字节视为归纳跑偏，拒绝发送 |
| thread 缺失不乱发 | 找不到当天 thread 时重试 3 次（间隔 5 分钟），仍失败则**不发顶层消息**，弹通知转人工 |
| 署名规范化 | 剔除归纳产出里的 `发送工具` 行，统一补 `*发送工具* <@U0CLAUDEXXX\|Claude>` |
| 失败可见 | 任何失败都写日志 + 弹 Basso 声通知，不静默 |

日报内容零人工过目直接进主管群，风险落在归纳质量上（`claude -p` + sonnet）。上述护栏拦的是
「明显跑偏」，拦不住「说法不准但格式正常」。发现归纳质量问题时改 generate.sh 里的 prompt，
别在 send.sh 补特例。

## 周报的发送落点（未定）

团队没有个人工作周报的固定 thread 惯例（2026-09-15 搜过全 workspace，「周报」命中的都是
L3/L4 前端问题周报，属 TeamBot 侧的 `frontend-issue-weekly` 系列，走 Confluence，与本 skill 无关）。
所以周报默认只落草稿加系统通知，由人工过目再发。

确认落点后启用自动发送，两种配法：

```bash
# 发到某频道当天某条 thread 下（与日报同机制）
export WORK_REPORT_WEEKLY_CHANNEL=C...
export WORK_REPORT_WEEKLY_THREAD_MARKER='<thread 顶层消息里的特异文本>'
export WORK_REPORT_WEEKLY_THREAD_AUTHOR=U...   # 可选，留空则只按标记匹配
```

再在周报 plist 的 `EnvironmentVariables` 里加 `WORK_REPORT_AUTOSEND=1`。
扩大对外副作用范围（换频道、发顶层、@人、发别的群）前需重新确认。

## 设计约束（loop-safety 护栏，改动前先读）

- **日报对外发布已授权**：2026-08-24 用户显式选择「全自动发到群 thread，不经人工确认」。
  采集与归纳只读仓库，唯一的对外写入是 `chat.postMessage`。
- **周报对外发布未授权**：2026-09-15 用户选择「只落本地草稿，人工过目再发」。
- **双熔断**：`claude -p` 归纳有超时（日报 300s、周报 900s，`WORK_REPORT_TIMEOUT` 可调），
  超时回退原始素材，保证一定有产出。
- **静默跳过**：窗口内无 commit 时 exit 0 静默退出，不打扰。
- **可观测**：每次运行写日志，可事后复盘。

## 可调参数（环境变量）

前缀统一为 `WORK_REPORT_`。

| 变量 | 默认 | 说明 |
|---|---|---|
| `WORK_REPORT_PERIOD` | `daily` | 周期，等价于位置参数；位置参数优先 |
| `WORK_REPORT_PROJECTS_DIR` | `~/projects` | 扫描的仓库根目录 |
| `WORK_REPORT_EXCLUDE` | `acme-agent cc-taskboard` | 排除的仓库名，空格分隔（被排除的仓库也不 fetch） |
| `WORK_REPORT_FETCH_TIMEOUT` | `60` | 采集前 fetch 的整体限时秒数，超时的仓库按本地已有 refs 采集 |
| `WORK_REPORT_DIR` | 按周期取 daily/weekly 目录 | 覆盖草稿目录（同时决定增量窗口起点） |
| `WORK_REPORT_DAILY_DIR` | `~/.claude/reports/daily` | 周报聚合日报草稿的来源目录 |
| `WORK_REPORT_MODEL` | `sonnet` | 归纳用的模型短名（haiku 更省、opus 更细） |
| `WORK_REPORT_TIMEOUT` | 日报 300、周报 900 | 归纳超时秒数 |
| `WORK_REPORT_BODY_LIMIT` | 日报 4000、周报 6000 | send.sh 体积保险上限（超出拒发，防归纳跑偏） |
| `WORK_REPORT_AUTOSEND` | `0` | `1` 时 generate.sh 跑完自动调 send.sh；日报 plist 已设为 `1` |
| `WORK_REPORT_SEND_DRYRUN` | `0` | `1` 时 send.sh 只打印待发正文与 thread 定位结果，不发送、不写幂等标记 |
| `WORK_REPORT_CHANNEL` | `C0XXXXXXXXX` | 日报目标频道 |
| `WORK_REPORT_THREAD_AUTHOR` | `U0LEADXXXXX` | 日报 thread 发起人 |
| `WORK_REPORT_THREAD_MARKER` | `每日工作任务统计` | 日报 thread 的识别文本 |
| `WORK_REPORT_WEEKLY_CHANNEL` | 空 | 周报目标频道，留空即不发 |
| `WORK_REPORT_WEEKLY_THREAD_AUTHOR` | 空 | 周报 thread 发起人，留空则只按标记匹配 |
| `WORK_REPORT_WEEKLY_THREAD_MARKER` | 空 | 周报 thread 的识别文本，留空即不发 |
| `WORK_REPORT_SEND_RETRIES` | `3` | 找不到当天 thread 时的重试次数 |
| `WORK_REPORT_SEND_RETRY_GAP` | `300` | 重试间隔秒数 |

## 定时器管理

```bash
# 查看是否注册
launchctl list | grep -E 'daily-report|weekly-report'
# 改时间或配置后重载
launchctl unload ~/Library/LaunchAgents/com.fez.daily-report.plist
launchctl load   ~/Library/LaunchAgents/com.fez.daily-report.plist
# 临时停用
launchctl unload ~/Library/LaunchAgents/com.fez.weekly-report.plist
```

日报 plist 的 `StartCalendarInterval` 是**数组**（周一至周五各一条 `Weekday`/`Hour`/`Minute`），
不是单个 dict——改成每天触发就换回 dict 并去掉 `Weekday`。周报 plist 是单个 dict（`Weekday` 5）。
改完 `plutil -lint` 校验再重载。

注意 plist 里的 `PATH` 不含 `/opt/homebrew/bin`，脚本里别依赖 `jq` 等 homebrew 工具
（send.sh 只用 `/usr/bin` 下的 `python3` 和 `curl`）。

## 判据说明

「窗口内有修改」= 有本人（`git config user.name/email`）的 commit。当前实现以 commit 为准；
若某天只有未提交的工作区改动，不会触发（如需纳入未提交改动，改 collect.sh 加 `git status` 检测）。

增量窗口接续上一份同周期报告的生成时刻，不重不漏。两道并列过滤各管一件事：committer date
落在窗口内（保证接续），author date 不早于窗口起点当天 00:00（剔除 rebase / cherry-pick 把
陈旧工作刷成今天造成的重复汇报）。

**取 commit 用 `--branches --remotes`，不用 `--all`**：`--all` 含 `refs/stash`，会把 git stash
产生的「WIP on <branch>」「index on <branch>」两条 commit 当成工作产出采进素材，合并状态判成
「仅在特性分支」，归纳后变成一条【开发中】的假工作。2026-09-15 实测撞到，当时 main-app 有
125 条 stash、main-app-test 有 2 条，其中落在当天窗口内的 2 条进了素材。

**云端提交靠采集前 fetch 才能采到**：经 TeamBot 共享 agent（如 `agent-acme-frontend-dev`）在云端提的
MR，commit 的 author 是本人邮箱，committer 是 agent 或 `root@ip-*.compute.internal`，按 author
匹配本来就能命中，缺的是本地 refs。2026-10-12 实测：云端 16:26 推送的 FOMO 子 tab 提交，本地
19:12 才被别的工具 fetch 到，17:30 的日报漏采。而且漏了补不回来，因为下一份的窗口从这一份的
生成时刻接续。所以 collect.sh 每次先 fetch。仍漏的情况是 committer date 早于报告生成时刻、
推送却晚于它的提交。另外，以 agent 自身身份为 author 的提交（如 `agent-acme-qa-brain`、`TeamBot`）
无法归属到本人，不会采。
