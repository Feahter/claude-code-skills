#!/usr/bin/env python3
"""
把反思员输出的 JSON diff 应用到数据层。

用法：
    apply_reflection.py <memdir> <reflection_json_path>

memdir 应指向 ~/.claude/projects/<slug>/memory
reflection_json_path 是 reflect.sh 从 headless claude 拿到的 JSON 输出文件。

幂等原则：重复 apply 相同 diff 不会重复新增（按 id 去重）。
"""

from __future__ import annotations

import json
import os
import re
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def today() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


def read_jsonl(path: Path) -> list[dict]:
    if not path.exists():
        return []
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return out


def write_jsonl(path: Path, rows: list[dict]) -> None:
    path.write_text(
        "\n".join(json.dumps(r, ensure_ascii=False) for r in rows) + ("\n" if rows else ""),
        encoding="utf-8",
    )


def ensure_ids(rows: list[dict], existing: list[dict], prefix: str) -> None:
    existing_ids = {r.get("id") for r in existing if r.get("id")}
    date = today().replace("-", "")
    counter = 1
    for r in rows:
        if not r.get("id") or r["id"] in existing_ids:
            while True:
                cand = f"{prefix}_{date}_{counter:03d}"
                counter += 1
                if cand not in existing_ids:
                    r["id"] = cand
                    existing_ids.add(cand)
                    break


def apply_tech_facts(diff: dict, memdir: Path) -> dict:
    path = memdir / "metacognition" / "tech_facts.jsonl"
    archive_dir = memdir / "metacognition" / "_archive" / datetime.now().strftime("%Y-%m")
    existing = read_jsonl(path)
    existing_by_id = {r["id"]: r for r in existing if "id" in r}

    new_facts = diff.get("new_tech_facts") or []
    ensure_ids(new_facts, existing, "t")

    added = 0
    superseded = 0
    for f in new_facts:
        # 防重：字面 claim + scope + topic 相同则跳过
        dup = any(
            e for e in existing
            if e.get("claim") == f.get("claim")
            and e.get("scope") == f.get("scope")
            and e.get("topic") == f.get("topic")
        )
        if dup:
            continue
        # 处理 supersedes
        sup_id = f.get("supersedes")
        if sup_id and sup_id in existing_by_id:
            existing_by_id[sup_id]["superseded_by"] = f["id"]
            superseded += 1
        existing.append(f)
        existing_by_id[f["id"]] = f
        added += 1

    # 归档
    archives = diff.get("tech_fact_archives") or []
    archived = 0
    if archives:
        archive_dir.mkdir(parents=True, exist_ok=True)
        archive_file = archive_dir / "tech_facts_archive.jsonl"
        to_archive = [r for r in existing if r.get("id") in archives]
        if to_archive:
            with archive_file.open("a", encoding="utf-8") as af:
                for r in to_archive:
                    r.setdefault("archived_at", today())
                    af.write(json.dumps(r, ensure_ascii=False) + "\n")
            existing = [r for r in existing if r.get("id") not in archives]
            archived = len(to_archive)

    write_jsonl(path, existing)
    return {"tech_facts_added": added, "tech_facts_superseded": superseded, "tech_facts_archived": archived}


def apply_judgments(diff: dict, memdir: Path) -> dict:
    path = memdir / "metacognition" / "judgments.jsonl"
    existing = read_jsonl(path)
    new_j = diff.get("new_judgments") or []
    ensure_ids(new_j, existing, "j")
    existing_ids = {r["id"] for r in existing}
    added = 0
    for j in new_j:
        if j["id"] in existing_ids:
            continue
        j.setdefault("ts", now_iso())
        existing.append(j)
        existing_ids.add(j["id"])
        added += 1
    write_jsonl(path, existing)
    return {"judgments_added": added}


def apply_biases(diff: dict, memdir: Path) -> dict:
    """
    biases.md 用 markdown 维护，不按 JSON 存储。这里用区段解析/重写。
    支持 action: create / increment / demote / archive。
    """
    path = memdir / "metacognition" / "biases.md"
    archive_dir = memdir / "metacognition" / "_archive" / datetime.now().strftime("%Y-%m")
    content = path.read_text(encoding="utf-8") if path.exists() else ""

    updates = diff.get("bias_updates") or []
    if not updates:
        return {"biases_changed": 0}

    # 简化的存储格式：每条 bias 作为 "### @@BIAS@@ <id> | <status>\n- **pattern**: ...\n- ..." 块
    # 为了降低实现复杂度，这里用一个附加的 biases.jsonl 作为 source-of-truth，
    # 然后在 .md 中把它渲染出来。第一次运行会从已有 .md 解析（允许为空）。
    jsonl_path = memdir / "metacognition" / "_biases_store.jsonl"
    store: list[dict] = read_jsonl(jsonl_path)
    store_by_pattern = {b["pattern"]: b for b in store}

    changed = 0
    archived = 0
    today_s = today()

    for u in updates:
        action = u.get("action")
        pattern = u.get("pattern")
        if not action or not pattern:
            continue
        if action == "create":
            if pattern in store_by_pattern:
                b = store_by_pattern[pattern]
                b["hit_count"] = int(b.get("hit_count", 0)) + 1
                b["last_seen"] = today_s
                if u.get("counter"):
                    b["counter"] = u["counter"]
                ev = set(b.get("evidence_judgment_ids") or []) | set(u.get("evidence_judgment_ids") or [])
                b["evidence_judgment_ids"] = sorted(ev)
                b["status"] = "active"
            else:
                nb = {
                    "pattern": pattern,
                    "category": u.get("category", "其它"),
                    "status": "active",
                    "hit_count": 1,
                    "first_seen": today_s,
                    "last_seen": today_s,
                    "counter": u.get("counter", ""),
                    "evidence_judgment_ids": u.get("evidence_judgment_ids") or [],
                }
                store.append(nb)
                store_by_pattern[pattern] = nb
            changed += 1
        elif action == "increment":
            b = store_by_pattern.get(pattern)
            if not b:
                continue
            b["hit_count"] = int(b.get("hit_count", 0)) + 1
            b["last_seen"] = today_s
            b["status"] = "active"
            ev = set(b.get("evidence_judgment_ids") or []) | set(u.get("evidence_judgment_ids") or [])
            b["evidence_judgment_ids"] = sorted(ev)
            changed += 1
        elif action == "demote":
            b = store_by_pattern.get(pattern)
            if not b:
                continue
            cur = b.get("status", "active")
            b["status"] = {"active": "watching", "watching": "dormant", "dormant": "dormant"}.get(cur, "watching")
            changed += 1
        elif action == "archive":
            b = store_by_pattern.pop(pattern, None)
            if b:
                archive_dir.mkdir(parents=True, exist_ok=True)
                with (archive_dir / "biases_archive.jsonl").open("a", encoding="utf-8") as af:
                    b["archived_at"] = today_s
                    af.write(json.dumps(b, ensure_ascii=False) + "\n")
                store = [x for x in store if x.get("pattern") != pattern]
                archived += 1
                changed += 1

    # 硬上限 15 条 active
    actives = [b for b in store if b.get("status") == "active"]
    if len(actives) > 15:
        actives_sorted = sorted(actives, key=lambda x: int(x.get("hit_count", 0)), reverse=True)
        keep = {id(b) for b in actives_sorted[:15]}
        for b in actives:
            if id(b) not in keep:
                b["status"] = "watching"

    write_jsonl(jsonl_path, store)
    render_biases_md(path, store)
    return {"biases_changed": changed, "biases_archived": archived}


def render_biases_md(md_path: Path, store: list[dict]) -> None:
    header = (
        "# 偏差登记册\n\n"
        "由 apply_reflection.py 自动渲染。不要手动编辑本文件，要改请改 _biases_store.jsonl 或跑 reflect.sh。\n\n"
        "**状态机**: 🔴 active / 🟡 watching / ⚪ dormant\n"
        "**硬上限**: active ≤ 15 条\n\n---\n\n"
    )
    icon = {"active": "🔴 active", "watching": "🟡 watching", "dormant": "⚪ dormant"}

    by_cat: dict[str, list[dict]] = {}
    for b in store:
        by_cat.setdefault(b.get("category", "其它"), []).append(b)

    body_lines = []
    for cat, items in sorted(by_cat.items()):
        body_lines.append(f"## {cat}")
        items.sort(key=lambda x: (
            {"active": 0, "watching": 1, "dormant": 2}.get(x.get("status", "watching"), 3),
            -int(x.get("hit_count", 0)),
        ))
        cur_status = None
        for b in items:
            st = b.get("status", "watching")
            if st != cur_status:
                body_lines.append(f"\n### {icon.get(st, st)}")
                cur_status = st
            evs = ", ".join(b.get("evidence_judgment_ids") or []) or "(none)"
            body_lines.append(
                f"- **pattern**: {b.get('pattern','')}\n"
                f"  - hit_count: {b.get('hit_count',0)}\n"
                f"  - first_seen: {b.get('first_seen','')} / last_seen: {b.get('last_seen','')}\n"
                f"  - counter: {b.get('counter','') or '（待补）'}\n"
                f"  - evidence: {evs}"
            )
        body_lines.append("")
    md_path.write_text(header + "\n".join(body_lines) + "\n", encoding="utf-8")


def apply_decisions(diff: dict, memdir: Path) -> dict:
    text = (diff.get("decisions_append") or "").strip()
    if not text:
        return {"decisions_appended": 0}
    path = memdir / "metacognition" / "decisions.md"
    with path.open("a", encoding="utf-8") as f:
        f.write("\n\n---\n\n" + text + "\n")
    return {"decisions_appended": 1}


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: apply_reflection.py <memdir> <reflection_json>", file=sys.stderr)
        return 2
    memdir = Path(sys.argv[1]).expanduser()
    reflection_path = Path(sys.argv[2]).expanduser()
    if not memdir.is_dir():
        print(f"memdir not found: {memdir}", file=sys.stderr)
        return 2
    if not reflection_path.is_file():
        print(f"reflection json not found: {reflection_path}", file=sys.stderr)
        return 2

    raw = reflection_path.read_text(encoding="utf-8").strip()
    # 容忍 markdown 代码块围栏
    if raw.startswith("```"):
        raw = re.sub(r"^```[a-zA-Z]*\n", "", raw)
        raw = re.sub(r"\n```\s*$", "", raw)
    try:
        diff = json.loads(raw)
    except json.JSONDecodeError as e:
        print(f"reflection json invalid: {e}", file=sys.stderr)
        return 3

    metrics: dict[str, int] = {}
    metrics.update(apply_tech_facts(diff, memdir))
    metrics.update(apply_judgments(diff, memdir))
    metrics.update(apply_biases(diff, memdir))
    metrics.update(apply_decisions(diff, memdir))

    # 更新 MEMORY.md 的时间戳尾巴
    memory_idx = memdir / "MEMORY.md"
    if memory_idx.exists():
        body = memory_idx.read_text(encoding="utf-8")
        marker = "<!-- metacog_last_updated: "
        stamp = f"{marker}{today()} -->"
        if marker in body:
            body = re.sub(r"<!-- metacog_last_updated: .*? -->", stamp, body)
        else:
            body = body.rstrip() + f"\n\n{stamp}\n"
        memory_idx.write_text(body, encoding="utf-8")

    print(json.dumps({"ok": True, "metrics": metrics}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
