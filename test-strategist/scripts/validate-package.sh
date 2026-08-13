#!/usr/bin/env bash
# 策略包门禁校验。把 test-strategist 的六条铁律里能机器查的部分变成硬闸门。
# 用法：validate-package.sh <策略包.yaml>
# 退出码：0 通过 / 1 有问题 / 2 用法或环境错误
set -euo pipefail

usage() {
  cat <<'EOF'
用法：validate-package.sh <策略包.yaml>

校验项（任一不过即失败）：
  1. 顶层必需字段：scope / input_kind / risks / not_covered
  2. 每条风险必填：risk_id / evidence / failure_mode / impact / priority / disposition
  3. risk_id 格式 R-NN 且唯一
  4. priority ∈ {P0,P1,P2,P3}；disposition ∈ {test,monitor,design-fix,explore,accept} 的组合；
     confidence ∈ {high,medium,low}
  5. 证据封顶：evidence 为 assumption-no-evidence 时不得为 P0/P1，且 confidence 不得为 high
  6. P0/P1 必须有 validation_obligation 及其 precondition/observable/oracle（纯 accept 除外）
  7. disposition 含 accept 必须有 owner
  8. oracle 不得命中弱判据黑名单（不报错 / 返回200 / 正常显示 / 与预期一致 ...）
  9. 全文不得命中空话黑名单（加强测试 / 确保稳定 / 全面覆盖 / 后续跟进 ...）
 10. not_covered 至少一条且每条有 reason

环境依赖：python3 + PyYAML。
EOF
}

case "${1:-}" in
  ""|-h|--help) usage; [ -z "${1:-}" ] && exit 2 || exit 0 ;;
esac

FILE="$1"
[ -f "$FILE" ] || { echo "❌ 文件不存在：$FILE" >&2; exit 2; }

python3 - "$FILE" <<'PY'
import sys, re

try:
    import yaml
except ImportError:
    print("❌ 缺少 PyYAML：pip3 install pyyaml", file=sys.stderr)
    sys.exit(2)

path = sys.argv[1]
raw = open(path, encoding="utf-8").read()

try:
    doc = yaml.safe_load(raw)
except yaml.YAMLError as e:
    print(f"❌ YAML 解析失败：{e}\n", file=sys.stderr)
    print("策略包里的 oracle / failure_mode 常含符号字面量，最常见的两个坑：", file=sys.stderr)
    print('  1. 值里出现「冒号+空格」（如 lessConfig: undefined、Tests: N passed）→ 被当成嵌套映射', file=sys.stderr)
    print("  2. 值以符号开头（如 \">-\"、'<0.01'、|、*、&）→ 被当成 YAML 语法", file=sys.stderr)
    print("\n最省心的写法：这类值一律改用 block scalar", file=sys.stderr)
    print("    oracle: |", file=sys.stderr)
    print('      输出中 "<" 之后首字符不是 "+"，Tests: N passed 也可以直接写', file=sys.stderr)
    sys.exit(2)

if not isinstance(doc, dict):
    print("❌ 顶层不是对象", file=sys.stderr)
    sys.exit(2)

problems = []
def bad(msg): problems.append(msg)

# --- 空话黑名单（全文）---
FLUFF = [
    "加强测试", "确保稳定", "充分考虑", "全面覆盖", "提升质量", "加强关注",
    "后续跟进", "视情况而定", "适当增加", "进一步完善", "保证质量", "做好测试",
]
for word in FLUFF:
    if word in raw:
        bad(f"[空话] 全文命中禁用表述「{word}」——换成具体的、可判定的描述")

# --- 弱判据黑名单（只查 oracle 字段）---
WEAK_ORACLE = [
    "功能正常", "正常显示", "正常工作", "不报错", "没有报错", "无异常",
    "与预期一致", "符合预期", "响应时间可接受", "性能良好", "体验流畅",
    "覆盖率", "运行通过", "测试通过",
]

VALID_PRIORITY = {"P0", "P1", "P2", "P3"}
VALID_DISPOSITION = {"test", "monitor", "design-fix", "explore", "accept"}
VALID_CONFIDENCE = {"high", "medium", "low"}

# --- 顶层必需字段 ---
for key in ("scope", "input_kind", "risks", "not_covered"):
    if not doc.get(key):
        bad(f"[结构] 缺顶层字段 `{key}`" + ("（不覆盖范围必须显式写出）" if key == "not_covered" else ""))

mode = doc.get("mode", "full")
if mode == "full":
    for key in ("evidence_summary", "counter_review"):
        if not doc.get(key):
            bad(f"[结构] full 模式缺 `{key}`（quick 模式才可省略）")

# --- 逐条风险 ---
risks = doc.get("risks") or []
if not isinstance(risks, list):
    bad("[结构] `risks` 不是列表")
    risks = []

seen_ids = set()
for i, r in enumerate(risks):
    tag = f"risks[{i}]"
    if not isinstance(r, dict):
        bad(f"[结构] {tag} 不是对象"); continue
    rid = r.get("risk_id") or ""
    tag = f"{tag} ({rid or '无 id'})"

    for key in ("risk_id", "evidence", "failure_mode", "impact", "priority", "disposition"):
        if not r.get(key):
            bad(f"[必填] {tag} 缺 `{key}`")

    if rid:
        if not re.fullmatch(r"R-[A-Z]?\d{2,}", str(rid)):
            bad(f"[格式] {tag} risk_id 应形如 R-01；并行 agent 扫描可加单字母前缀区分来源，如 R-A01")
        if rid in seen_ids:
            bad(f"[唯一性] {tag} risk_id 重复")
        seen_ids.add(rid)

    prio = str(r.get("priority") or "")
    if prio and prio not in VALID_PRIORITY:
        bad(f"[取值] {tag} priority `{prio}` 不合法（P0-P3）")

    conf = str(r.get("confidence") or "")
    if conf and conf not in VALID_CONFIDENCE:
        bad(f"[取值] {tag} confidence `{conf}` 不合法（high/medium/low）")

    disp_raw = str(r.get("disposition") or "")
    parts = [p.strip() for p in re.split(r"-and-|,|\s+and\s+", disp_raw) if p.strip()]
    unknown = [p for p in parts if p not in VALID_DISPOSITION]
    if disp_raw and unknown:
        bad(f"[取值] {tag} disposition 含未知值 {unknown}（只能是 {sorted(VALID_DISPOSITION)} 的组合）")

    ev = str(r.get("evidence") or "")
    no_ev = ev.strip() == "assumption-no-evidence"

    # 证据封顶
    if no_ev and prio in ("P0", "P1"):
        bad(f"[证据封顶] {tag} evidence 是 assumption-no-evidence，优先级不得高于 P2（当前 {prio}）")
    if no_ev and str(r.get("confidence") or "") == "high":
        bad(f"[证据封顶] {tag} 无证据却标 confidence: high")

    # accept 必须有 owner
    if "accept" in parts and not r.get("owner"):
        bad(f"[处置] {tag} disposition 含 accept，必须写 owner（谁接受了这个风险）")

    # P0/P1 的验证义务
    ob = r.get("validation_obligation")
    only_accept = parts == ["accept"]
    if prio in ("P0", "P1") and not only_accept:
        if not isinstance(ob, dict):
            bad(f"[义务] {tag} 是 {prio}，必须有 validation_obligation")
        else:
            for key in ("precondition", "observable", "oracle"):
                if not ob.get(key):
                    bad(f"[义务] {tag} validation_obligation 缺 `{key}`")

    # oracle 弱判据
    if isinstance(ob, dict):
        oracle = str(ob.get("oracle") or "")
        for w in WEAK_ORACLE:
            if w in oracle:
                bad(f"[弱判据] {tag} oracle 含「{w}」——判不出真假，改成具体可判定的量（见 oracle-patterns.md）")
                break
        if oracle and len(oracle.strip()) < 6:
            bad(f"[弱判据] {tag} oracle 过短，写不出判据说明还没想清楚")

# --- not_covered ---
nc = doc.get("not_covered") or []
if isinstance(nc, list):
    for i, item in enumerate(nc):
        if not isinstance(item, dict) or not item.get("item") or not item.get("reason"):
            bad(f"[结构] not_covered[{i}] 需同时有 item 与 reason")
elif nc:
    bad("[结构] `not_covered` 不是列表")

# --- 输出 ---
n_risk = len(risks)
if problems:
    print(f"❌ 门禁未通过：{len(problems)} 个问题（{n_risk} 条风险）\n")
    for p in problems:
        print("  " + p)
    print("\n修完再交接。带病的策略包会把错误判断传导到下游测试。")
    sys.exit(1)

by_prio = {}
for r in risks:
    if isinstance(r, dict):
        by_prio[str(r.get("priority"))] = by_prio.get(str(r.get("priority")), 0) + 1
dist = " ".join(f"{k}:{v}" for k, v in sorted(by_prio.items()))
print(f"✅ 门禁通过：{n_risk} 条风险（{dist}），{len(nc)} 条不覆盖项，mode={mode}")
PY
