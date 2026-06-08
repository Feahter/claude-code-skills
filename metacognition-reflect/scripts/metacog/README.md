# 元认知自动化 Harness

让 Claude Code 在 memory 层持续积累、反思、淘汰认知。全部本机运行，不依赖云端定时任务。

## 总体结构

```
~/.claude/scripts/metacog/
├── _lib.sh                   公共工具函数
├── probe/                    Phase 0 最小可行验证（必先跑）
│   ├── probe_session_start.sh
│   ├── probe_session_end.sh
│   ├── probe_headless.sh
│   └── README.md
├── select_relevant.sh        SessionStart hook：注入 top-N 元认知卡
├── quick_tag.sh              SessionEnd hook：扫 transcript 入队 pending
├── reflect.sh                每日批处理：调 headless claude 生成 diff
├── reflect_prompt.md         反思员的 system prompt
├── apply_reflection.py       把反思 JSON diff 应用到数据层（幂等）
├── enable.sh                 一键接入（加 hooks + load LaunchAgent）
├── disable.sh                一键停用（反向操作；不删数据）
└── README.md                 本文件

~/Library/LaunchAgents/com.fez.claude-metacog.plist   每天 03:00 跑 reflect.sh

~/.claude/skills/metacognition-reflect/SKILL.md       手动触发入口（/reflect 等）

~/.claude/projects/<slug>/memory/
├── MEMORY.md                 纯索引
├── project_*.md / feedback_*.md ...   普通记忆
└── metacognition/
    ├── judgments.jsonl       判断登记册（append-only）
    ├── tech_facts.jsonl      已验证事实（含 superseded 链）
    ├── biases.md             偏差登记册（由 _biases_store.jsonl 渲染）
    ├── _biases_store.jsonl   偏差数据源
    ├── decisions.md          重大决策复盘
    ├── pending_reflection/   SessionEnd 入队的待处理片段
    └── _archive/             归档
```

## 启动流程（必须按顺序）

### Step 1 — Phase 0 Probe

打开 `probe/README.md` 按说明跑 3 个 probe。**三个都 PASS 才进 Step 2**，任一 FAIL 先按 README 的退路调整 quick_tag.sh / select_relevant.sh。

把结果写到 `/tmp/metacog_phase0.md`：
```
probe1 SessionStart additionalContext: PASS / FAIL(退路=X)
probe2 SessionEnd: PASS / FAIL(退路=X)
probe3 headless claude: PASS / FAIL(退路=X)
```

### Step 2 — 启用

```bash
bash ~/.claude/scripts/metacog/enable.sh
```

脚本会：
- 备份 settings.json
- 追加 SessionStart / SessionEnd hook（保留现有 Stop / PostToolUse）
- load LaunchAgent

### Step 3 — 验证

1. **数据层 smoke**（已完成，参考当前 memory/metacognition/ 结构）
2. **SessionStart 注入** — 起新会话问："告诉我当前元认知提醒里有哪些条目"，应能看到 tech_facts 前 3 条
3. **SessionEnd 入队** — 会话中说"不对，你理解错了" → 退出后看 `ls memory/metacognition/pending_reflection/`
4. **手动反思** — `bash ~/.claude/scripts/metacog/reflect.sh` 看日志和数据层更新
5. **LaunchAgent** — `launchctl list | grep com.fez.claude-metacog` 应列出；日志 `/tmp/metacog_launchagent.{out,err}.log`

### Step 4 — 一周后校准

```bash
jq -s '
  map(select(.verified != null)) as $done |
  [$done[] | select(.confidence == "high")] as $hi |
  {
    total_done: ($done | length),
    high_done: ($hi | length),
    high_correct: ([$hi[] | select(.verified == true)] | length)
  }
' ~/.claude/projects/-Users-you-projects-your-app/memory/metacognition/judgments.jsonl
```

目标：`high_correct / high_done > 80%`。若 < 60%，说明自我评估系统性偏高——reflect_prompt.md 应加一条"过度自信"元偏差。

## 工作流回路

```
对话中 ─┬─ SessionStart hook → select_relevant.sh 注入静态 top-N
        │
        ├─ 任务进行中 按需主动触发 metacognition-recall skill
        │      └─ 拆主题 → 并发 Explore agent 查 tech_facts/biases/decisions
        │         → 聚合去重 → 600 字内注入当前工作流（只读）
        │
        ├─ (对话正常进行；structured judgment / correction 自然发生)
        │
        └─ SessionEnd hook → quick_tag.sh 扫 transcript → pending/<ts>.json

每天 03:00 LaunchAgent（或手动）：
    reflect.sh
      ├─ 聚合 pending
      ├─ 默认并发分桶：judgments 桶 / biases 桶 分别调 headless claude
      │    （METACOG_PARALLEL=0 回退单桶）
      ├─ 两份 diff JSON 串行喂给 apply_reflection.py（幂等）
      │    - 新 judgment append
      │    - 新 tech_fact 去重 + supersede
      │    - bias 合并 / 状态迁移 / 归档
      │    - 决策复盘 append
      └─ pending 移 _archive/
```

## 停用

```bash
bash ~/.claude/scripts/metacog/disable.sh
```

数据层保留；如需彻底清理，手动删 `~/.claude/scripts/metacog/` 和 `memory/metacognition/`。

## 核心设计原则

1. **失败不阻塞会话**：hook 脚本全部 trap ERR → echo "{}" 或 exit 0。元认知系统挂掉不会影响正常使用。
2. **数据追加为主**：judgments.jsonl / tech_facts.jsonl 都是 append-only；bias 合并走单一入口 apply_reflection.py，幂等。
3. **淘汰硬机制**：active bias cap 15、tech_fact 60 天未被引用可归档、bias 状态机 active→watching→dormant→archive。
4. **注入预算**：SessionStart additionalContext < 1200 字节（约 400 汉字），防稀释。
5. **单项目先行**：目前只在 your-app 项目 memory 下铺开；推广前先跑一周观察。

## 风险与预设退路

见 `~/.claude/plans/harness-skills-frolicking-wombat.md` 的风险表。关键兜底：
- SessionEnd 不可用 → 改挂 Stop hook + 记录 last_processed_message_id 去重
- headless claude 失败 → pending 保留，下一轮继续尝试
- bias 膨胀 → active cap 自动降级
