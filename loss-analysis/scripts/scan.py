#!/usr/bin/env python3
"""扫描 ~/.claude/projects/**/*.jsonl，提取低效率/返工信号，输出 JSON 摘要.

用法:
    python3 scan.py [--days N] [--output PATH] [--cwd-filter SUBSTR]

输出 JSON 包含：
- global: 总览指标
- projects_top10: 按时长排序的项目维度
- tool_fail_breakdown / tool_fail_examples: 工具失败明细
- duplicate_read_top: 同会话重复 Read 热点
- correction_examples: 真用户纠正样本（已过滤系统注入）
- rollback_examples: 回滚信号样本
- unverified_examples: 完成声明无验证样本
- serial_explore_runs: 探索类工具串行长链统计
"""
import argparse
import json
import re
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path.home() / ".claude" / "projects"

# 真用户纠正信号（已剔除系统注入污染）
CORRECTION_PATTERNS = [
    r"我没让你", r"别这样", r"不对", r"错了", r"停[一下]",
    r"你猜的", r"瞎(说|猜|改)", r"先别", r"不是这个",
    r"撤回", r"回滚", r"改回去", r"不要主动", r"不要[再去]",
    r"为什么(你|要)", r"谁让你", r"还没(读|看|确认)", r"没让你提交",
    r"读完(再|后)", r"先(读|看|查)", r"(改|做)错了",
    r"你这", r"不要[擅自自动]",
    r"\b(stop|wait|don'?t|nope)\b",
    r"\b(wrong|incorrect|that'?s not right)\b",
]
COR_RE = re.compile("|".join(CORRECTION_PATTERNS), re.IGNORECASE)

ROLLBACK_RE = re.compile(
    r"走错|方向(不对|错)|改乱了|越改越|重来|回到[原最]|之前的版本|"
    r"revert|rollback|start over",
    re.IGNORECASE,
)

# 必须排除的系统注入前缀
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


def is_real_user_text(msg):
    """过滤 tool_result 伪装、系统注入."""
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
HOME_PROJECTS_PREFIX = "-" + str(Path.home()).replace("/", "-") + "-projects-"


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
        "sessions": 0, "user_msgs": 0, "tool_calls": 0,
        "corrections": 0, "rollbacks": 0, "tool_failures": 0,
        "duplicate_reads": 0, "compactions": 0,
        "completion_no_verify": 0, "subagent_calls": 0,
        "duration_sec": 0.0,
    })
    global_stats = Counter()
    correction_examples, unverified_examples, rollback_examples = [], [], []
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
        ps["duration_sec"] += (last_ts - first_ts).total_seconds() if last_ts else 0
        global_stats["sessions"] += 1

        file_reads = defaultdict(list)
        last_assistant = {"text": "", "tools": []}
        explore_run = []  # (tool, ts)

        def flush_explore_run():
            if len(explore_run) >= 3:
                serial_runs.append({
                    "project": proj,
                    "length": len(explore_run),
                    "tools": [t[0] for t in explore_run],
                })

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
                            for back_idx in range(idx - 1, max(-1, idx - 10), -1):
                                prev = records[back_idx][1]
                                if prev.get("type") != "assistant":
                                    continue
                                for tc in get_tool_calls(prev.get("message", {})):
                                    if tc.get("id") == tool_id:
                                        name = tc.get("name", "?")
                                        tool_fail_breakdown[name] += 1
                                        if len(tool_fail_examples[name]) < 4:
                                            err_text = b.get("content", "")
                                            if isinstance(err_text, list):
                                                err_text = " ".join(
                                                    x.get("text", "") for x in err_text if isinstance(x, dict)
                                                )
                                            tool_fail_examples[name].append({
                                                "project": proj,
                                                "tool_input": str(tc.get("input"))[:300],
                                                "error": str(err_text)[:300],
                                            })
                                        break
                                break
                real, text = is_real_user_text(msg)
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

                ps["user_msgs"] += 1
                global_stats["user_msgs"] += 1
                if COR_RE.search(text):
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
                if len(tools) >= 2:
                    multi_tool += 1
                    flush_explore_run()
                    explore_run = []
                elif len(tools) == 1:
                    single_tool += 1
                    name = tools[0].get("name")
                    if name in EXPLORE_TOOLS:
                        explore_run.append((name, parse_ts(r.get("timestamp"))))
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
                        fp = t.get("input", {}).get("file_path", "")
                        if fp:
                            file_reads[fp].append(lineno)

                text = get_text(r.get("message", {}))
                if text and CLAIM_RE.search(text):
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
                    "project": proj, "file": fp, "count": len(lines),
                })

    proj_list = sorted(
        [(k, v) for k, v in proj_stats.items() if v["sessions"] > 0],
        key=lambda x: x[1]["duration_sec"], reverse=True,
    )
    duplicate_read_top.sort(key=lambda x: x["count"], reverse=True)

    serial_length_dist = Counter(r["length"] for r in serial_runs)
    serial_long = sum(1 for r in serial_runs if r["length"] >= 5)
    serial_total_calls = sum(r["length"] for r in serial_runs)

    out = {
        "scan_window_days": args.days,
        "scan_at": datetime.now(timezone.utc).isoformat(),
        "global": dict(global_stats),
        "single_tool_call_assistant": single_tool,
        "multi_tool_parallel": multi_tool,
        "parallel_ratio": round(
            multi_tool / (multi_tool + single_tool) if (multi_tool + single_tool) else 0, 4
        ),
        "serial_explore_runs": {
            "total_segments": len(serial_runs),
            "length_distribution": dict(sorted(serial_length_dist.items())),
            "long_segments_ge5": serial_long,
            "max_length": max((r["length"] for r in serial_runs), default=0),
            "total_calls_in_runs": serial_total_calls,
        },
        "projects_top10": [
            {
                "project": k,
                **v,
                "duration_h": round(v["duration_sec"] / 3600, 2),
            }
            for k, v in proj_list[:10]
        ],
        "tool_fail_breakdown": dict(tool_fail_breakdown.most_common()),
        "tool_fail_examples": dict(tool_fail_examples),
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
        "tool_calls": g.get("tool_calls", 0),
        "tool_fail_rate": round(g.get("tool_failures", 0) / g.get("tool_calls", 1) * 100, 2),
        "correction_rate": round(g.get("corrections", 0) / max(g.get("user_msgs", 1), 1) * 100, 2),
        "completion_no_verify": g.get("completion_no_verify", 0),
        "duplicate_reads": g.get("duplicate_reads", 0),
        "compactions": g.get("compactions", 0),
        "parallel_ratio_pct": round(out["parallel_ratio"] * 100, 2),
        "serial_long_segments": serial_long,
        "output_path": str(out_path),
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
