# 本机 Claude Code / Codex 前缀测量

B 类对象不问用户要数字，按本卡自己量。下面的数字和行为是本机某个时点的实测，CLI 升级后可能变化。引用前先跑一次命令拿当前值，不要直接照抄卡里的数。

## 1. 真实前缀：读会话 jsonl 的原始 usage

不要用 `/context` 的分类数字定位前缀构成。2026-09-18 实测，`/context` 自报 27.3k，同一会话 jsonl 首轮三项相加为 68,785，漏报约六成。它只统计自定义资产，不含工具 schema、内置系统提示和环境注入。

```bash
# 会话文件：~/.claude/projects/<slug>/<sessionId>.jsonl，slug 是工作目录把 / 换成 -
f=$(ls -t ~/.claude/projects/<slug>/*.jsonl | head -1)
jq -c 'select(.type=="assistant" and .message.usage!=null)
  | {id:.message.id, in:.message.usage.input_tokens,
     cw:.message.usage.cache_creation_input_tokens,
     cr:.message.usage.cache_read_input_tokens}' "$f" | awk '!seen[$0]++' | head
```

- 每轮前缀 = `in + cw + cr`。首轮的值近似等于固定前缀。
- 同一条 assistant 消息会因为分块输出写多行，usage 完全相同。按 `message.id` 去重，否则轮数和总量都会翻倍。
- `cr` 占比高说明缓存命中良好。`cw` 持续很大时先看轮间隔，再下"缓存在重建"的结论：间隔都在 5 分钟内时，缓存不会过期，这些写入是对话增量。

多会话汇总（看平均前缀和长会话占比）：

```bash
for f in ~/.claude/projects/<slug>/*.jsonl; do
  jq -r 'select(.type=="assistant" and .message.usage!=null)
    | [.message.id, .message.usage.input_tokens + .message.usage.cache_creation_input_tokens + .message.usage.cache_read_input_tokens] | @tsv' "$f" \
  | awk '!seen[$1]++ {n++; s+=$2; if($2>200000) big++} END {if(n) printf "%s\t轮=%d\t均前缀=%.0f\t>200k轮=%d\n", FILENAME, n, s/n, big}' FILENAME="$f"
done
```

账单层面的分布（input、cache write、cache read、output 各多少，缓存命中率）可以用 `npx ccusage@latest --json`。本机未全局安装 ccusage，走 npx。

## 2. 归因：差分探针

想知道某一块配置（agents、某个 MCP、output style、rules）占多少前缀，用复制配置后逐块剥离的方法：

```bash
cp -R ~/.claude /tmp/cc-probe            # 只复制一次，之后在副本上剥离
# 副本里必须保留 settings.json 的 apiKeyHelper，本机认证靠它，缺了报 Not logged in
CLAUDE_CONFIG_DIR=/tmp/cc-probe claude -p "hi" --output-format json --model haiku > /tmp/probe-base.json
# 删掉或改名副本里的某一块，再跑一次，比较两次 usage 三项之和的差值
```

- 模型用短名 `haiku`，全名在本机网关会报 400。
- 噪声约 ±155 token。小于这个量级的差值不能当作效果。
- 方法可信度已验证：去掉 agents 实测差 833，`/context` 报 806。
- **探针测不出两类东西**：skill 清单（headless 不注入）和 MEMORY.md（headless 不加载对应 slug）。这两项按字符数除以约 4（英文）或约 1.5 到 2（中文）推算，或者在新开的交互会话里看首轮 usage，并标为"推算"。

## 3. 本机已知的前缀构成与杠杆

| 构成项 | 是否每轮都付 | 已知杠杆 | 证据 |
|---|---|---|---|
| 内置系统提示 | 是，稳定可缓存 | 无法改动。自定义内容里与它重复的部分可删（见 attention-noise.md 的"与内置重复"） | 结构固定 |
| 工具 schema | 是 | `settings.json` 的 `permissions.deny` 会把工具 schema 移出前缀，不只是拦调用。实测 deny 5 个工具后前缀从 33,440 降到 29,996，与 `--disallowedTools` 一致。`--tools` 是白名单，漏写即丢能力，非法名静默忽略，所以黑名单更安全 | 2026-09-18 实测 |
| deferred 工具（ToolSearch 按需拉取 schema 的 MCP 等） | 只有名字常驻 | 不算出血点，别花力气砍 | 机制 |
| CLAUDE.md、rules、output style | 是，稳定可缓存 | 内容稳定就走缓存价。砍它主要是为了降噪，省钱效果有限 | ccusage 实测缓存命中 94% |
| skill 清单 | 是 | 预算为窗口 token 数 × 4 × 1%（单位是字符）。超预算时低使用分数的 skill 只剩名字。可用 `skillOverrides` 设 `name-only` 或 `off` 腾预算，但它对 plugin 来源无效 | CLI 源码与 jsonl 的 `skill_listing` 附件 |
| MEMORY.md 索引 | 是 | 一行一条，详细内容放二级索引按需读 | 本机做法 |
| 会话历史 | 每轮全量重读，随长度线性增长 | 阶段收尾时 `/clear` 或开新会话。整读大文件改为按行段读。大输出先裁剪再进上下文 | 实测 52% 的支出发生在 200k 以上的轮次 |

测 skill 清单的实际显示：

```bash
# 内容本身是多行文本，取最后一条附件要在 jq 里做，不能接 tail
jq -rs 'map(select(.type=="attachment" and .attachment.type=="skill_listing")) | last | .attachment.content' "$f" > /tmp/skill-listing.txt
wc -m /tmp/skill-listing.txt
grep -cE '^- [^ :]+(:[^ ]+)?$' /tmp/skill-listing.txt   # 只剩名字的条目数
```

## 4. 成本换算

- 固定前缀每 1k token 约合 $25.7 每月。这是按 Opus 5 官方费率（cache read $0.50/M，5 分钟 cache write $6.25/M）和 2026-09 前后 14 天 21,798 轮推算的。本机走网关，实际计费口径未验证，只用于排序。
- 缓存价格结构：read 为 base 的 0.1 倍，write 为 1.25 倍（5 分钟 TTL）或 2 倍（1 小时 TTL）。具体费率以 `claude-api` skill 或官方文档为准。
- 1 小时 TTL 只在同一前缀的请求间隔落在 5 到 60 分钟之间时可能划算。粗判是：超过 5 分钟的轮间隔要占约 60% 以上才值得改。配置项为 `promptCacheTtl`，本机走网关能否生效未验证，改之前先看一次请求的 `ephemeral_1h_input_tokens` 是否非 0。

## 5. Codex

Codex 的会话记录在 `~/.codex/sessions/<年>/<月>/<日>/rollout-*.jsonl`，系统提示里的 Skill roots 依次是 `~/.codex/skills`、`~/.agents/skills`、`~/.codex/skills/.system`。usage 字段名与 Claude Code 不同，先用 `jq 'keys'` 看一条记录的实际结构再写提取命令，不要套用上面的字段名。
