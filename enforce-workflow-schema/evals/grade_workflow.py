#!/usr/bin/python3
"""确定性检查 .workflow/<task-id>/ 下 spec.md 与 plan.md 的结构。

用法: grade_workflow.py <dir> [--require-evidence] [--json]
退出码: 0 全部通过; 1 有检查失败; 2 目录或文件不存在。
只用标准库, 兼容 python 3.9。
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATE_DIR = os.path.join(os.path.dirname(HERE), "templates")
SPEC_MAX_LINES = 200
SPEC_SECTIONS = [
    ("需求摘要", "需求摘要"),
    ("输入输出", "输入输出"),
    ("排除范围", "排除范围"),
    ("验收口径", "验收口径"),
    ("依赖与风险", "依赖与风险"),
]
PLAN_SECTIONS = ["A", "B", "C", "D"]
# 前面紧跟标识符字符的 <...> 是泛型 (如 Map<…>), 不是占位符
ANGLE_RE = re.compile(r"(?<![A-Za-z0-9_])<[^<>\n]+>")
FENCE_RE = re.compile(r"^\s*```")


def read_lines(path):
    with open(path, encoding="utf-8") as f:
        return f.read().split("\n")


def placeholder_key(token):
    """把模板里的 <...> 变成匹配键: 带冒号的取到冒号, 否则取前 4 个字符。"""
    m = re.match(r"<[^：:]{0,3}[：:]", token)
    if m:
        return m.group(0)
    return token if len(token) <= 4 else token[:4]


def load_template_info():
    """从模板提取占位符键, 以及 plan 模板 D 区块代码块里的原样行。"""
    keys = set()
    d_code_lines = set()
    for name in ("spec.md", "plan.md"):
        path = os.path.join(TEMPLATE_DIR, name)
        if not os.path.isfile(path):
            continue
        lines = read_lines(path)
        in_fence = False
        in_d = False
        for ln in lines:
            if FENCE_RE.match(ln):
                in_fence = not in_fence
                continue
            if name == "plan.md" and not in_fence and re.match(r"^##\s", ln):
                in_d = bool(re.match(r"^##\s*D[\.\s、]", ln))
            if in_fence and in_d:
                d_code_lines.add(ln.strip())
            if not in_fence:
                for tok in ANGLE_RE.findall(ln):
                    if len(tok) > 2:
                        keys.add(placeholder_key(tok))
    return keys, d_code_lines


PLACEHOLDER_KEYS, TEMPLATE_D_LINES = load_template_info()


def has_placeholder(text):
    for tok in ANGLE_RE.findall(text):
        if placeholder_key(tok) in PLACEHOLDER_KEYS:
            return True
    return False


def split_sections(lines, level_re):
    """按二级标题切分, 返回 [(标题, 起始行号, 内容行列表)]; 忽略代码块内的标题。"""
    secs = []
    cur = None
    in_fence = False
    for i, ln in enumerate(lines):
        if FENCE_RE.match(ln):
            in_fence = not in_fence
        if not in_fence and level_re.match(ln):
            cur = [ln, i + 1, []]
            secs.append(cur)
        elif cur is not None:
            cur[2].append(ln)
    return secs


H2 = re.compile(r"^##\s+\S")  # 恰为二级标题, 不含 ###
H2 = re.compile(r"^##(?!#)\s*\S")


def find_spec_section(secs, kw):
    for title, _, body in secs:
        if kw in title:
            return body
    return None


def find_plan_section(secs, letter):
    pat = re.compile(r"^##\s*" + letter + r"(?:[\.\s、:：）)]|$)")
    for title, _, body in secs:
        if pat.match(title):
            return body
    return None


def list_items(body):
    items = []
    in_fence = False
    for ln in body:
        if FENCE_RE.match(ln):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        m = re.match(r"^\s*(?:[-*+]|\d+[\.)])\s+(.*\S)\s*$", ln)
        if m:
            items.append(m.group(1))
    return items


def real_items(body):
    out = []
    for it in list_items(body):
        stripped = re.sub(r"\[[ xX]\]\s*", "", it).strip()
        if not stripped or has_placeholder(stripped):
            continue
        if re.fullmatch(r"[（(]?(待填|无|TBD|todo)[）)]?", stripped, re.I):
            continue
        out.append(stripped)
    return out


def fenced_blocks(body):
    blocks = []
    cur = None
    for ln in body:
        if FENCE_RE.match(ln):
            if cur is None:
                cur = []
            else:
                blocks.append(cur)
                cur = None
        elif cur is not None:
            cur.append(ln)
    return blocks


def block_is_real_evidence(block):
    real = []
    for ln in block:
        s = ln.strip()
        if not s or has_placeholder(s) or s in TEMPLATE_D_LINES:
            continue
        if "待填" in s:
            return False
        real.append(s)
    return len(real) > 0


def scan_leftover(lines):
    hits = []
    in_fence = False
    for i, ln in enumerate(lines):
        if FENCE_RE.match(ln):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        for tok in ANGLE_RE.findall(ln):
            if placeholder_key(tok) in PLACEHOLDER_KEYS:
                hits.append("L%d %s" % (i + 1, tok[:30]))
    return hits


def grade(d, require_evidence):
    checks = []

    def add(cid, ok, detail):
        checks.append({"id": cid, "pass": bool(ok), "detail": detail})

    spec_lines = read_lines(os.path.join(d, "spec.md"))
    plan_lines = read_lines(os.path.join(d, "plan.md"))
    spec_secs = split_sections(spec_lines, H2)
    plan_secs = split_sections(plan_lines, H2)

    for cid, kw in SPEC_SECTIONS:
        if cid == "排除范围":
            continue  # 该区块是否存在由下面的 spec.exclusions_nonempty 单独判定, 避免两项互相掩护
        body = find_spec_section(spec_secs, kw)
        add("spec.section." + cid, body is not None,
            "found" if body is not None else "缺少含「%s」的二级标题" % kw)

    excl = find_spec_section(spec_secs, "排除范围")
    if excl is None:
        add("spec.exclusions_nonempty", False, "缺少含「排除范围」的二级标题")
    else:
        items = real_items(excl)
        add("spec.exclusions_nonempty", len(items) >= 1,
            "%d 条非占位条目" % len(items))

    n = len(spec_lines)
    if n and spec_lines[-1] == "":
        n -= 1
    add("spec.max_lines", n <= SPEC_MAX_LINES, "%d 行 (上限 %d)" % (n, SPEC_MAX_LINES))

    for letter in PLAN_SECTIONS:
        body = find_plan_section(plan_secs, letter)
        add("plan.section." + letter, body is not None,
            "found" if body is not None else "缺少「## %s.」区块" % letter)

    b = find_plan_section(plan_secs, "B")
    if b is None:
        add("plan.tasks_with_checkbox", False, "无 B 区块")
    else:
        task_re = re.compile(r"^#{3,4}\s*(?:Task\b|任务)", re.I)
        tasks = []
        cur = None
        in_fence = False
        for ln in b:
            if FENCE_RE.match(ln):
                in_fence = not in_fence
            if not in_fence and task_re.match(ln):
                cur = []
                tasks.append(cur)
            elif cur is not None:
                cur.append(ln)
        cb = re.compile(r"^\s*[-*]\s+\[[ xX]\]\s+\S")
        good = [t for t in tasks if any(cb.match(x) for x in t)]
        # 校准放宽: 历史 plan 常直接在 B 下列 `- [x] **T1** ...`, 没有 Task 标题
        loose_re = re.compile(
            r"^\s*[-*]\s+\[[ xX~]\]\s+\**(?:Task\s*)?[A-Za-z]{0,2}\d+")
        loose = [x for x in b if loose_re.match(x)]
        add("plan.tasks_with_checkbox", len(good) >= 1 or len(loose) >= 1,
            "%d 个 Task 标题, %d 个带 checkbox; 带编号的 checkbox 行 %d 条"
            % (len(tasks), len(good), len(loose)))

    c = find_plan_section(plan_secs, "C")
    if c is None:
        add("plan.exclusions_ref_nonempty", False, "无 C 区块")
    else:
        body = [x for x in c if x.strip() and not x.strip().startswith(">")
                and x.strip() != "---" and not has_placeholder(x)]
        add("plan.exclusions_ref_nonempty", len(body) >= 1, "%d 行有效内容" % len(body))

    left = scan_leftover(spec_lines)
    add("spec.no_template_placeholders", not left,
        "无残留" if not left else "; ".join(left[:5]))
    left = scan_leftover(plan_lines)
    add("plan.no_template_placeholders", not left,
        "无残留" if not left else "; ".join(left[:5]))

    if require_evidence:
        dsec = find_plan_section(plan_secs, "D")
        if dsec is None:
            add("plan.evidence", False, "无 D 区块")
        else:
            blocks = fenced_blocks(dsec)
            real = [bk for bk in blocks if block_is_real_evidence(bk)]
            # 校准放宽: 历史 D 区块常把命令写成行内 `cmd` 加结果文字, 不一定用围栏代码块
            inline = []
            in_fence = False
            for ln in dsec:
                if FENCE_RE.match(ln):
                    in_fence = not in_fence
                    continue
                st = ln.strip()
                if (not in_fence and not st.startswith(">") and "待填" not in st
                        and not has_placeholder(st) and re.search(r"`[^`\n]+`", st)):
                    inline.append(st)
            add("plan.evidence", len(real) >= 1 or len(inline) >= 1,
                "%d 个代码块, %d 个含真实内容; 含行内命令的行 %d 条"
                % (len(blocks), len(real), len(inline)))
    return checks


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    flags = set(a for a in argv if a.startswith("--"))
    unknown = flags - {"--require-evidence", "--json"}
    if len(args) != 1 or unknown:
        sys.stderr.write("用法: grade_workflow.py <dir> [--require-evidence] [--json]\n")
        return 2
    d = args[0]
    for name in ("spec.md", "plan.md"):
        if not os.path.isfile(os.path.join(d, name)):
            sys.stderr.write("缺少文件: %s\n" % os.path.join(d, name))
            return 2
    checks = grade(d, "--require-evidence" in flags)
    ok = all(c["pass"] for c in checks)
    if "--json" in flags:
        print(json.dumps({"dir": d, "pass": ok, "checks": checks}, ensure_ascii=False))
    else:
        for c in checks:
            print("%s %s: %s" % ("PASS" if c["pass"] else "FAIL", c["id"], c["detail"]))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
