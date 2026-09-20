#!/usr/bin/env python3
"""扫描 ~/.claude/projects/**/*.jsonl，提取协作效率信号，输出 JSON 摘要.

用法:
    python3 scan.py [--days N] [--output PATH] [--cwd-filter SUBSTR]

输出 JSON 包含：
- global: 总览指标
- projects_top10: 按会话墙钟跨度排序的项目维度
- tool_fail_breakdown / tool_fail_examples: 工具失败明细
- duplicate_read_top: 同会话重复 Read 热点
- correction_examples: 用户纠正关键词命中样本（已过滤系统注入）
- rollback_examples: 回滚信号样本
- unverified_examples: 完成声明无验证样本
- serial_explore_runs: 探索类工具串行长链统计
"""
import argparse
import difflib
import json
import re
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path.home() / ".claude" / "projects"

# 用户纠正信号。这里只保留较明确的表达，结果仍需抽样核验。
CORRECTION_PATTERNS = [
    r"我没让你", r"别这样", r"(?<!对)不对", r"错了", r"停(一下|下)",
    r"你猜的", r"瞎(说|猜|改)", r"先别", r"不是这个",
    r"撤回", r"回滚", r"改回去", r"不要主动", r"不要再(这样|做|改|继续|去)",
    r"为什么你(要|还|又|没|不)", r"谁让你", r"你还没(读|看|确认)", r"没让你提交",
    r"读完.{0,12}再(改|说|回答|动手|继续)", r"(改|做)错了",
    r"你这(里|个|次).{0,20}(错了|不对|有问题|不该|不要)", r"不要(擅自|自动)",
    r"(?:^|\n)\s*(please\s+)?stop(?!\s+hook\b)\b",
    r"\b(don'?t|nope)\b",
    r"\b(wrong|incorrect|that'?s not right)\b",
]
COR_RE = re.compile("|".join(CORRECTION_PATTERNS), re.IGNORECASE)

ROLLBACK_RE = re.compile(
    r"走错|方向(不对|错)|改乱了|越改越|重来|回到[原最]|之前的版本|"
    r"revert|rollback|start over",
    re.IGNORECASE,
)

# 必须排除的系统注入前缀。isMeta 没打标的那部分(压缩续接/slash command/
# task-notification 等)只能靠这里的正则,见 is_real_user_text。
SYSTEM_INJECTION_PATTERNS = [
    r"^This session is being continued",
    r"^<SUBAGENT-STOP>",
    r"^Stop hook feedback",
    r"^The user just ran /",
    r"^## Context Usage",
    r"^Base directory for this skill",
    r"^<system-reminder>",
    r"^<command-name>",
    r"^<local-command",
    r"^Caveat:",
    r"<bash-input>",
    r"^\[Request interrupted",
    r"^Tool .* not available",
    r"^A session-scoped Stop hook",
    r"^Another Claude session sent a message:",
    r"^<teammate-message",
    r"^Ran \d+ .* hooks",
    r"^<task-notification>",
]
SYS_RE = re.compile("|".join(SYSTEM_INJECTION_PATTERNS), re.MULTILINE)

VERIFY_RE = re.compile(
    r"tsc|typecheck|pytest|jest|npm test|yarn test|pnpm test|cargo test|go test|build|eslint|biome",
    re.IGNORECASE,
)

CLAIM_RE = re.compile(
    r"已(完成|修好|搞定|跑通|修复|实现|提交|推送)|应该(可以|能|没问题)|看起来(对|正确|没问题)|"
    r"\b(should work|looks good|all set|done|fixed|complete)\b",
    re.IGNORECASE,
)

GIT_CLAIM_RE = re.compile(r"已(提交|推送)|\bcommit\b|\bpush\b", re.IGNORECASE)


def _needs_verify(text):
    # git 提交/推送类声明的「验证」是命令执行成功,不该要求 typecheck/test;
    # 去掉 git 措辞后若不再命中完成声明,视为纯 git 动作,豁免验证检查。
    if GIT_CLAIM_RE.search(text) and not CLAIM_RE.search(GIT_CLAIM_RE.sub("", text)):
        return False
    return True


def is_correction(text, has_prior_assistant):
    """纠正必须发生在 assistant 已经回应之后，首条问题不算返工."""
    return bool(has_prior_assistant and COR_RE.search(text))


def find_tool_use(records, idx, tool_id, window=30):
    """从 idx 往前找发起这条 tool_result 的 tool_use.

    窗口内每一条 assistant 记录都要查:tool_result 对应的 tool_use 未必在最近
    那条 assistant 里,并行调用和中间插入的记录会把两者隔开(实测间距 2-13 条)。
    找到第一条 assistant 就停会漏掉约 4% 的失败归类,窗口取 10 也不够。
    """
    for back_idx in range(idx - 1, max(-1, idx - window), -1):
        prev = records[back_idx][1]
        if prev.get("type") != "assistant":
            continue
        for tc in get_tool_calls(prev.get("message", {})):
            if tc.get("id") == tool_id:
                return tc
    return None


def result_text(block):
    """tool_result 的 content 可能是字符串,也可能是 text block 列表."""
    t = block.get("content", "")
    if isinstance(t, list):
        t = " ".join(x.get("text", "") for x in t if isinstance(x, dict))
    return str(t)


# --- 工具失败的签名分桶 ---
# 桶名前缀含义:A=门禁与环境限制, B=工具用法错, C=shell 用法错, D=超时中断,
# E=正常语义的非零退出(误报), F=命令自身报错。归因时先扣掉 A 和 E 两类。
# 判定按下面的书写顺序短路,保证互不重叠——尤其别用 startswith("Exit code 1")
# 兜底,它会把 143/128/129 一起吃进去导致重复计数。
BUILD_TOOL_RE = re.compile(
    r"\b(yarn|npm|npx|pnpm|vitest|jest|pytest|tsc|eslint|playwright|cargo|make)\b"
)
SEARCH_CMD_RE = re.compile(r"\b(grep|rg|ug|diff)\b")


def fail_bucket(err, cmd):
    """把一条工具失败归到互不重叠的类别。

    只看错误文本和命令,不看工具名——同一类问题(权限门、参数校验)会出现在
    不同工具上。返回的桶名带前缀,方便在报告里按性质分组。
    """
    e = err or ""
    c = cmd or ""
    # A 门禁与环境:不是缺陷,是机制在正常工作或外部能力缺失
    if "Blocked: sleep" in e:
        return "A1 harness 拦截 sleep 前台轮询"
    if "auto mode classifier" in e:
        return "A2 auto mode 分类器拦截"
    if ("doesn't want to proceed" in e or "has been denied" in e
            or "haven't granted it yet" in e):
        return "A3 用户/权限门拒绝"
    if "isolated in the worktree" in e:
        return "A4 worktree 隔离拦截"
    if ("deny rule" in e or "denied by your permission settings" in e
            or "Access denied" in e):
        return "A5 permission deny 配置命中"
    if "claude.ai login" in e:
        return "A6 Artifact 需要 claude.ai 登录"
    if ("is not supported for this model" in e or "not indexed" in e
            or "channel_not_found" in e or "has been closed" in e
            or "temporarily unavailable" in e):
        return "A7 外部服务/网关能力缺失"
    # B 工具用法
    if "InputValidationError" in e:
        return "B1 工具参数校验失败"
    if "String to replace not found" in e or "replace_all is false" in e:
        return "B2 Edit 目标串不匹配"
    if "has not been read yet" in e:
        return "B3 未先 Read 就写"
    # C shell 用法
    if re.search(r"\(eval\):cd:|cd:\d+: no such file or directory", e):
        return "C1 cd 相对路径失败"
    if ("bad substitution" in e or "no matches found" in e
            or "read-only variable" in e):
        return "C2 zsh 方言不兼容"
    if "command not found" in e or re.match(r"Exit code 127\b", e.strip()):
        return "C3 命令不存在"
    # D 超时与中断
    if re.match(r"Exit code 143\b", e.strip()):
        return "D1 命令被超时杀掉(143)"
    if re.match(r"Exit code (129|128)\b", e.strip()):
        return "D2 退出码 128/129"
    # E 正常语义的非零退出 / F 真报错
    if re.match(r"Exit code (1|2)\b", e.strip()):
        # 检索比较类命令无匹配时非零是正常语义。但命令里出现构建或测试工具时
        # 不能这么算,那种非零是真实失败(实测 `yarn typecheck` 报 TS2307 被误
        # 归进来过),所以要显式排除,也不要拿 \btest\b 当检索特征——它会匹配
        # `yarn test`、路径名和项目名。
        if (SEARCH_CMD_RE.search(c) and not BUILD_TOOL_RE.search(c)
                and len(e.strip().split("\n")) <= 2):
            return "E1 检索/比较类无匹配(正常语义)"
        if "File does not exist" in e or "No such file or directory" in e:
            return "E2 路径不存在(多为探测)"
        return "F1 命令/脚本自身报错"
    return "F2 其他"


# 失败之后的下一步行为:相似度用来区分"原样重试"(真返工)和"换方向"(探到
# 边界就走,不是返工)。别把失败数直接当返工数,两者实测差 6 倍。
RETRY_NEAR_IDENTICAL = 0.85
RETRY_PARTIAL = 0.6


def norm_cmd(c):
    return re.sub(r"\s+", " ", c or "").strip()


def next_bash_cmds(records, idx, limit=3, window=40):
    """取 idx 之后最近的几条 Bash 命令,用于判断失败后是重试还是换方向."""
    out = []
    for j in range(idx + 1, min(len(records), idx + window)):
        r = records[j][1]
        if r.get("type") != "assistant":
            continue
        for tc in get_tool_calls(r.get("message", {})):
            if tc.get("name") == "Bash":
                out.append(norm_cmd((tc.get("input") or {}).get("command", "")))
        if len(out) >= limit:
            break
    return out[:limit]


EXPLORE_TOOLS = {"Read", "Grep", "Glob", "LS"}


def parse_ts(s):
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None


def get_text(msg):
    if not isinstance(msg, dict):
        return ""
    content = msg.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                parts.append(block.get("text", ""))
        return "\n".join(parts)
    return ""


def get_tool_calls(msg):
    if not isinstance(msg, dict):
        return []
    content = msg.get("content")
    if not isinstance(content, list):
        return []
    return [b for b in content if isinstance(b, dict) and b.get("type") == "tool_use"]


def is_real_user_text(msg, is_meta=False):
    """过滤 tool_result 伪装、系统注入.

    记录顶层的 isMeta=True 是 CLI 自己给注入内容打的标记(skill 正文、Stop hook
    feedback、Goal check-in、图片引用、coordinator 消息等),比文本前缀可靠,且对
    以后新增的注入类型自动生效。但它不覆盖压缩续接、slash command 和
    task-notification 这些没打标的注入,所以两个判据是 OR 关系,都要保留。
    """
    if is_meta:
        return False, ""
    content = msg.get("content")
    if isinstance(content, list):
        for b in content:
            if isinstance(b, dict) and b.get("type") == "tool_result":
                return False, ""
    text = get_text(msg)
    if not text or not text.strip():
        return False, ""
    if SYS_RE.search(text[:500]):
        return False, text
    return True, text


# Claude Code 把 cwd 转成项目目录名时把 `/` 替换为 `-`
# 所以 `~/projects/foo` 会变成 `-Users-<name>-projects-foo`，按当前用户 home 动态推导前缀
HOME_PROJECTS_PREFIX = str(Path.home()).replace("/", "-") + "-projects-"


def project_name(path):
    p = path.parent.name
    if "worktrees" in p:
        seg = p.split("-")
        if seg:
            return seg[-1] + "(worktree)"
    if p.startswith(HOME_PROJECTS_PREFIX):
        return p.replace(HOME_PROJECTS_PREFIX, "")
    return p[:60]


def iter_records(path):
    try:
        with open(path) as f:
            for i, line in enumerate(f):
                line = line.strip()
                if not line:
                    continue
                try:
                    yield i, json.loads(line)
                except json.JSONDecodeError:
                    continue
    except (OSError, UnicodeDecodeError):
        return


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=30, help="扫描最近 N 天，默认 30")
    ap.add_argument("--output", default="/tmp/claude-loss-analysis/raw.json")
    ap.add_argument("--cwd-filter", default=None,
                    help="只统计 cwd/path 包含该子串的会话（可选）")
    args = ap.parse_args()

    cutoff = datetime.now(timezone.utc) - timedelta(days=args.days)
    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    proj_stats = defaultdict(lambda: {
        "sessions": 0, "user_msgs": 0, "delegated_msgs": 0, "tool_calls": 0,
        "corrections": 0, "rollbacks": 0, "tool_failures": 0,
        "duplicate_reads": 0, "compactions": 0,
        "completion_no_verify": 0, "subagent_calls": 0,
        "session_span_sec": 0.0,
    })
    global_stats = Counter()
    correction_examples, unverified_examples, rollback_examples = [], [], []
    fail_buckets = Counter()
    fail_bucket_examples = defaultdict(list)
    retry_after_fail = Counter()
    monthly = defaultdict(lambda: {
        "sessions": 0, "tool_calls": 0, "failures": 0, "buckets": Counter(),
    })
    tool_fail_breakdown = Counter()
    tool_fail_examples = defaultdict(list)
    duplicate_read_top = []
    serial_runs = []
    single_tool, multi_tool = 0, 0

    for f in ROOT.rglob("*.jsonl"):
        if args.cwd_filter and args.cwd_filter not in str(f):
            continue
        try:
            mtime = datetime.fromtimestamp(f.stat().st_mtime, tz=timezone.utc)
            if mtime < cutoff - timedelta(days=2):
                continue
        except OSError:
            continue

        records = list(iter_records(f))
        if not records:
            continue
        is_subagent_session = f.parent.name == "subagents" or f.name.startswith("agent-")
        first_ts = last_ts = None
        for _, r in records:
            ts = parse_ts(r.get("timestamp"))
            if ts:
                if first_ts is None:
                    first_ts = ts
                last_ts = ts
        if first_ts is None or first_ts < cutoff:
            continue

        proj = project_name(f)
        ps = proj_stats[proj]
        ps["sessions"] += 1
        ps["session_span_sec"] += (last_ts - first_ts).total_seconds() if last_ts else 0
        global_stats["sessions"] += 1
        monthly[first_ts.strftime("%Y-%m")]["sessions"] += 1

        file_reads = defaultdict(list)
        last_assistant = {"text": "", "tools": []}
        explore_run = []  # (tool, ts)

        def flush_explore_run():
            if len(explore_run) >= 3:
                serial_runs.append({
                    "project": proj,
                    "session": f.name,
                    "length": len(explore_run),
                    "tools": [t[0] for t in explore_run],
                    "first_ts": explore_run[0][1],
                    "last_ts": explore_run[-1][1],
                    "dependency_review_required": True,
                })

        # 预扫:一次模型响应会被拆成多条共享 message.id 的 assistant 记录,
        # 且被 tool_result 夹断。按 message.id 归并才能还原「逻辑轮次」里真实的工具数。
        turn_tool_names = defaultdict(list)
        for _, rr in records:
            if rr.get("type") == "assistant":
                mid = rr.get("message", {}).get("id")
                if mid is not None:
                    turn_tool_names[mid].extend(
                        t.get("name") for t in get_tool_calls(rr.get("message", {}))
                    )
        seen_turn = set()

        for idx, (lineno, r) in enumerate(records):
            rtype = r.get("type")

            if rtype == "user":
                msg = r.get("message", {})
                content = msg.get("content")
                if isinstance(content, list):
                    for b in content:
                        if isinstance(b, dict) and b.get("type") == "tool_result" and b.get("is_error"):
                            global_stats["tool_failures"] += 1
                            ps["tool_failures"] += 1
                            tool_id = b.get("tool_use_id")
                            tc = find_tool_use(records, idx, tool_id)
                            err_text = result_text(b)
                            month = (r.get("timestamp") or "")[:7]
                            name, cmd = "(未回溯到调用)", ""
                            if tc is not None:
                                name = tc.get("name", "?")
                                tinput = tc.get("input")
                                cmd = (tinput or {}).get("command", "") if isinstance(tinput, dict) else ""
                                if len(tool_fail_examples[name]) < 4:
                                    tool_fail_examples[name].append({
                                        "project": proj,
                                        "tool_input": str(tinput)[:300],
                                        "error": err_text[:300],
                                    })
                            tool_fail_breakdown[name] += 1
                            bucket = fail_bucket(err_text, cmd)
                            fail_buckets[bucket] += 1
                            if month:
                                monthly[month]["failures"] += 1
                                monthly[month]["buckets"][bucket] += 1
                            if len(fail_bucket_examples[bucket]) < 3:
                                fail_bucket_examples[bucket].append({
                                    "project": proj,
                                    "ts": r.get("timestamp"),
                                    "tool": name,
                                    "cmd": cmd[:220],
                                    "error": err_text[:220],
                                })
                            if name == "Bash":
                                cands = next_bash_cmds(records, idx)
                                if not cands:
                                    retry_after_fail["no_followup"] += 1
                                else:
                                    sim = max(
                                        difflib.SequenceMatcher(
                                            None, norm_cmd(cmd)[:400], x[:400]
                                        ).ratio()
                                        for x in cands
                                    )
                                    if sim >= RETRY_NEAR_IDENTICAL:
                                        retry_after_fail["retry_near_identical"] += 1
                                    elif sim >= RETRY_PARTIAL:
                                        retry_after_fail["retry_partial"] += 1
                                    else:
                                        retry_after_fail["moved_on"] += 1
                real, text = is_real_user_text(msg, bool(r.get("isMeta")))
                if not real:
                    if isinstance(content, list) and any(
                        isinstance(b, dict) and b.get("type") == "tool_result" for b in content
                    ):
                        pass  # tool_result 不打断 explore_run
                    else:
                        flush_explore_run()
                        explore_run = []
                    continue
                # 真用户消息打断 explore run
                flush_explore_run()
                explore_run = []

                if is_subagent_session:
                    ps["delegated_msgs"] += 1
                    global_stats["delegated_msgs"] += 1
                    continue

                ps["user_msgs"] += 1
                global_stats["user_msgs"] += 1
                if is_correction(
                    text, bool(last_assistant["text"] or last_assistant["tools"])
                ):
                    ps["corrections"] += 1
                    global_stats["corrections"] += 1
                    if len(correction_examples) < 60:
                        correction_examples.append({
                            "project": proj,
                            "user_msg": text[:280],
                            "prev_assistant": last_assistant["text"][:280],
                            "prev_tools": [t.get("name") for t in last_assistant["tools"]][:6],
                            "ts": r.get("timestamp"),
                        })
                if ROLLBACK_RE.search(text):
                    ps["rollbacks"] += 1
                    global_stats["rollbacks"] += 1
                    if len(rollback_examples) < 30:
                        rollback_examples.append({
                            "project": proj,
                            "user_msg": text[:280],
                            "prev_assistant": last_assistant["text"][:280],
                        })

            elif rtype == "assistant":
                global_stats["assistant_msgs"] += 1
                tools = get_tool_calls(r.get("message", {}))
                if tools:
                    m = (r.get("timestamp") or "")[:7]
                    if m:
                        monthly[m]["tool_calls"] += len(tools)
                mid = r.get("message", {}).get("id")
                # 并行率/串行链按逻辑轮次(message.id)判定:同一轮被拆成的多条记录只算一次,
                # 工具数取预扫归并后的真实总数,避免把并行轮误判成一串单发。
                if mid is None:
                    turn_tools, first_seen = [t.get("name") for t in tools], True
                else:
                    first_seen = mid not in seen_turn
                    seen_turn.add(mid)
                    turn_tools = turn_tool_names.get(mid, [])
                if first_seen:
                    global_stats["assistant_turns"] += 1
                    if len(turn_tools) >= 2:
                        multi_tool += 1
                        flush_explore_run()
                        explore_run = []
                    elif len(turn_tools) == 1:
                        single_tool += 1
                        if turn_tools[0] in EXPLORE_TOOLS:
                            explore_run.append((turn_tools[0], parse_ts(r.get("timestamp"))))
                        else:
                            flush_explore_run()
                            explore_run = []
                    else:
                        flush_explore_run()
                        explore_run = []

                ps["tool_calls"] += len(tools)
                global_stats["tool_calls"] += len(tools)
                for t in tools:
                    if t.get("name") in ("Agent", "Task"):
                        ps["subagent_calls"] += 1
                        global_stats["subagent_calls"] += 1
                    if t.get("name") == "Read":
                        inp = t.get("input", {}) or {}
                        fp = inp.get("file_path", "")
                        # 只把整读计入重复读:带 offset/limit 的切片读是对大文件的合理分段,不算浪费
                        if fp and inp.get("offset") is None and inp.get("limit") is None:
                            file_reads[fp].append(lineno)

                text = get_text(r.get("message", {}))
                if text and CLAIM_RE.search(text) and _needs_verify(text):
                    verified = False
                    for j in range(max(0, idx - 12), min(len(records), idx + 12)):
                        nxt = records[j][1]
                        if nxt.get("type") == "assistant":
                            for tc in get_tool_calls(nxt.get("message", {})):
                                cmd = tc.get("input", {}).get("command", "")
                                if VERIFY_RE.search(cmd):
                                    verified = True
                                    break
                        if verified:
                            break
                    if not verified:
                        ps["completion_no_verify"] += 1
                        global_stats["completion_no_verify"] += 1
                        if len(unverified_examples) < 25:
                            unverified_examples.append({
                                "project": proj,
                                "claim": text[:300],
                                "ts": r.get("timestamp"),
                            })
                last_assistant = {"text": text, "tools": tools}

            elif rtype == "system":
                sub = r.get("subtype", "") or ""
                if "compact" in sub.lower():
                    ps["compactions"] += 1
                    global_stats["compactions"] += 1

        flush_explore_run()

        for fp, lines in file_reads.items():
            if len(lines) >= 3:
                ps["duplicate_reads"] += 1
                global_stats["duplicate_reads"] += 1
                duplicate_read_top.append({
                    "project": proj,
                    "session": f.name,
                    "file": fp,
                    "count": len(lines),
                    "context_review_required": True,
                })

    proj_list = sorted(
        [(k, v) for k, v in proj_stats.items() if v["sessions"] > 0],
        key=lambda x: x[1]["session_span_sec"], reverse=True,
    )
    duplicate_read_top.sort(key=lambda x: x["count"], reverse=True)

    serial_length_dist = Counter(r["length"] for r in serial_runs)
    serial_long = sum(1 for r in serial_runs if r["length"] >= 5)
    serial_total_calls = sum(r["length"] for r in serial_runs)

    multi_tool_turn_ratio = round(
        multi_tool / (multi_tool + single_tool) if (multi_tool + single_tool) else 0,
        4,
    )
    out = {
        "scan_window_days": args.days,
        "scan_at": datetime.now(timezone.utc).isoformat(),
        "metric_notes": {
            "session_span_h": (
                "会话首条到末条记录的墙钟跨度，包含等待、离开和挂机时间；"
                "不能解释为实际工作时长或时间损耗。"
            ),
            "corrections": "关键词命中数，已过滤系统注入，但仍需抽样核验误报。",
            "multi_tool_turn_ratio": (
                "有工具调用的逻辑轮次中，一轮调用两个及以上工具的比例；"
                "低比例不等于低效，顺序依赖任务本就需要串行。"
            ),
            "serial_explore_runs": (
                "连续单工具探索轮次的候选段；必须查看原会话后才能判断是否可并行。"
            ),
            "duplicate_reads": (
                "同会话整文件读取至少三次的候选项；文件修改、压缩或合理复查都可能导致重复。"
            ),
            "completion_no_verify": (
                "完成声明附近未识别到常见验证命令的规则命中；不等于一定没有验证。"
            ),
        },
        "global": dict(global_stats),
        "single_tool_turns": single_tool,
        "multi_tool_turns": multi_tool,
        "multi_tool_turn_ratio": multi_tool_turn_ratio,
        "parallel_ratio": multi_tool_turn_ratio,
        "serial_explore_runs": {
            "total_segments": len(serial_runs),
            "length_distribution": dict(sorted(serial_length_dist.items())),
            "long_segments_ge5": serial_long,
            "max_length": max((r["length"] for r in serial_runs), default=0),
            "total_calls_in_runs": serial_total_calls,
            "examples": sorted(
                serial_runs, key=lambda r: r["length"], reverse=True
            )[:20],
        },
        "projects_top10": [
            {
                "project": k,
                **v,
                "session_span_h": round(v["session_span_sec"] / 3600, 2),
            }
            for k, v in proj_list[:10]
        ],
        "tool_fail_breakdown": dict(tool_fail_breakdown.most_common()),
        "tool_fail_examples": dict(tool_fail_examples),
        "fail_buckets": dict(fail_buckets.most_common()),
        "fail_bucket_examples": dict(fail_bucket_examples),
        "retry_after_fail": dict(retry_after_fail),
        "monthly": [
            {
                "month": m,
                "sessions": v["sessions"],
                "tool_calls": v["tool_calls"],
                "failures": v["failures"],
                "fail_rate_pct": round(v["failures"] / v["tool_calls"] * 100, 2)
                if v["tool_calls"] else 0,
                # 按调用量归一化后才能跨月比较:某类要不要提建议看这个趋势,
                # 不看绝对数(绝对数最大的那类可能正在自行收敛)。
                "buckets_per_1k_calls": {
                    k: round(c / v["tool_calls"] * 1000, 2)
                    for k, c in v["buckets"].most_common()
                } if v["tool_calls"] else {},
            }
            for m, v in sorted(monthly.items())
        ],
        "duplicate_read_top": duplicate_read_top[:20],
        "correction_examples": correction_examples[:25],
        "rollback_examples": rollback_examples[:15],
        "unverified_examples": unverified_examples[:15],
    }
    out_path.write_text(json.dumps(out, ensure_ascii=False, indent=2, default=str))

    g = out["global"]
    summary = {
        "sessions": g.get("sessions", 0),
        "user_msgs": g.get("user_msgs", 0),
        "assistant_turns": g.get("assistant_turns", 0),
        "tool_calls": g.get("tool_calls", 0),
        "tool_fail_rate": round(g.get("tool_failures", 0) / g.get("tool_calls", 1) * 100, 2),
        "correction_rate": round(g.get("corrections", 0) / max(g.get("user_msgs", 1), 1) * 100, 2),
        "completion_no_verify": g.get("completion_no_verify", 0),
        "duplicate_reads": g.get("duplicate_reads", 0),
        "compactions": g.get("compactions", 0),
        "multi_tool_turn_ratio_pct": round(multi_tool_turn_ratio * 100, 2),
        "single_tool_turns": single_tool,
        "multi_tool_turns": multi_tool,
        "serial_long_segments": serial_long,
        "serial_max_length": max((r["length"] for r in serial_runs), default=0),
        "fail_buckets_top6": dict(fail_buckets.most_common(6)),
        "retry_after_fail": dict(retry_after_fail),
        "monthly_fail_rate_pct": {
            m["month"]: m["fail_rate_pct"] for m in out["monthly"]
        },
        "output_path": str(out_path),
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
