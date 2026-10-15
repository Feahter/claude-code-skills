#!/usr/bin/python3
"""grade_workflow.py 的单测。夹具写在 /tmp/rsi-t5/fixtures/ 下。
运行: /usr/bin/python3 test_grade_workflow.py
"""
import json
import os
import shutil
import subprocess
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
GRADER = os.path.join(HERE, "grade_workflow.py")
FIX = "/tmp/rsi-t5/fixtures"

GOOD_SPEC = """# ADD-DRY-RUN: 给 CLI 加 --dry-run

## 需求摘要
给 `cli.py` 加 `--dry-run`，只打印将执行的动作，不写盘。

## 输入输出
- **入口**：`python cli.py sync --dry-run`
- **输入**：布尔开关
- **输出**：打印动作列表，退出码 0

## 排除范围（不做什么）
> 硬要求。
- 不修改 `sync` 子命令的现有参数签名
- 不引入第三方依赖

## 验收口径
- [ ] `python -m unittest` 全绿

## 依赖与风险
- **风险等级**：LOW
"""

GOOD_PLAN = """# ADD-DRY-RUN: 实现计划

**Goal:** 加 --dry-run

---

## A. 技术决策

### 决策 1: 用 argparse 的 store_true
- **选什么**：store_true

---

## B. 任务拆分

### Task 1: 加参数

**Files:**
- Modify: `cli.py`

- [ ] Step 1: 写失败测试
- [ ] Step 2: 实现

---

## C. 排除范围回引

- 不修改 `sync` 子命令的现有参数签名

---

## D. 验证证据

### 单元测试
```bash
$ python -m unittest
OK (3 tests)
```
"""


def write_case(name, spec=GOOD_SPEC, plan=GOOD_PLAN):
    d = os.path.join(FIX, name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    if spec is not None:
        with open(os.path.join(d, "spec.md"), "w", encoding="utf-8") as f:
            f.write(spec)
    if plan is not None:
        with open(os.path.join(d, "plan.md"), "w", encoding="utf-8") as f:
            f.write(plan)
    return d


def run(d, *flags):
    p = subprocess.run([sys.executable, GRADER, d, "--json"] + list(flags),
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                       universal_newlines=True)
    try:
        data = json.loads(p.stdout)
        checks = dict((c["id"], c["pass"]) for c in data["checks"])
    except ValueError:
        checks = {}
    return p.returncode, checks


def failed(checks):
    return sorted(k for k, v in checks.items() if not v)


class GradeWorkflowTest(unittest.TestCase):
    def test_good_passes(self):
        rc, ch = run(write_case("good"))
        self.assertEqual((rc, failed(ch)), (0, []))
        self.assertIn("spec.exclusions_nonempty", ch)  # 确认检查项真的被执行

    def test_good_with_evidence_passes(self):
        rc, ch = run(write_case("good_ev"), "--require-evidence")
        self.assertEqual((rc, failed(ch)), (0, []))
        self.assertIn("plan.evidence", ch)

    def test_missing_exclusions_section(self):
        spec = GOOD_SPEC.replace("## 排除范围（不做什么）", "## 其他说明")
        rc, ch = run(write_case("no_excl", spec=spec))
        self.assertEqual(rc, 1)
        self.assertEqual(failed(ch), ["spec.exclusions_nonempty"])

    def test_exclusions_only_placeholders(self):
        spec = GOOD_SPEC.replace(
            "- 不修改 `sync` 子命令的现有参数签名\n- 不引入第三方依赖",
            "- <例：不修改 X 模块的现有 API 签名>\n- <例：不引入新的第三方依赖>")
        rc, ch = run(write_case("ph_excl", spec=spec))
        self.assertEqual(rc, 1)
        self.assertIn("spec.exclusions_nonempty", failed(ch))
        self.assertIn("spec.no_template_placeholders", failed(ch))

    def test_exclusions_empty_section(self):
        spec = GOOD_SPEC.replace("- 不修改 `sync` 子命令的现有参数签名\n- 不引入第三方依赖\n", "")
        rc, ch = run(write_case("empty_excl", spec=spec))
        self.assertEqual((rc, failed(ch)), (1, ["spec.exclusions_nonempty"]))

    def test_spec_over_200_lines(self):
        spec = GOOD_SPEC + "\n".join("- 补充说明 %d" % i for i in range(200)) + "\n"
        rc, ch = run(write_case("long", spec=spec))
        self.assertEqual((rc, failed(ch)), (1, ["spec.max_lines"]))

    def test_spec_exactly_200_lines_ok(self):
        base = GOOD_SPEC.rstrip("\n").split("\n")
        spec = "\n".join(base + ["- 填充"] * (200 - len(base))) + "\n"
        self.assertEqual(len(spec.rstrip("\n").split("\n")), 200)
        rc, ch = run(write_case("l200", spec=spec))
        self.assertEqual((rc, failed(ch)), (0, []))

    def test_missing_D_section(self):
        plan = GOOD_PLAN.split("## D. 验证证据")[0]
        rc, ch = run(write_case("no_d", plan=plan))
        self.assertEqual((rc, failed(ch)), (1, ["plan.section.D"]))

    def test_evidence_pending_fails_only_with_flag(self):
        plan = GOOD_PLAN.split("## D. 验证证据")[0] + "## D. 验证证据\n\n（待填）\n"
        d = write_case("pending", plan=plan)
        rc, ch = run(d)
        self.assertEqual((rc, failed(ch)), (0, []))
        rc, ch = run(d, "--require-evidence")
        self.assertEqual((rc, failed(ch)), (1, ["plan.evidence"]))

    def test_evidence_template_block_fails(self):
        plan = GOOD_PLAN.split("### 单元测试")[0] + (
            "### 类型检查\n```bash\n$ yarn typecheck\n"
            "<贴最关键的 5-10 行；全绿则注明 \"0 errors\">\n```\n")
        rc, ch = run(write_case("tmpl_block", plan=plan), "--require-evidence")
        # 围栏代码块内的 <...> 不进占位符扫描 (真实代码里常有尖括号), 由 evidence 检查兜底
        self.assertEqual((rc, failed(ch)), (1, ["plan.evidence"]))

    def test_plan_without_checkbox(self):
        plan = GOOD_PLAN.replace("- [ ] Step 1: 写失败测试\n- [ ] Step 2: 实现\n", "- Step 1\n")
        rc, ch = run(write_case("no_cb", plan=plan))
        self.assertEqual((rc, failed(ch)), (1, ["plan.tasks_with_checkbox"]))

    def test_plan_C_empty(self):
        plan = GOOD_PLAN.replace("- 不修改 `sync` 子命令的现有参数签名\n\n---\n\n## D.", "\n---\n\n## D.")
        rc, ch = run(write_case("c_empty", plan=plan))
        self.assertEqual((rc, failed(ch)), (1, ["plan.exclusions_ref_nonempty"]))

    def test_leftover_placeholder_detected(self):
        spec = GOOD_SPEC.replace("# ADD-DRY-RUN: 给 CLI 加 --dry-run", "# <TASK-ID>: <一句话需求标题>")
        rc, ch = run(write_case("ph_title", spec=spec))
        self.assertEqual((rc, failed(ch)), (1, ["spec.no_template_placeholders"]))

    def test_heading_variants_accepted(self):
        spec = (GOOD_SPEC.replace("## 需求摘要", "## 1. 需求摘要")
                .replace("## 输入输出", "## 二、输入输出（含边界）"))
        plan = GOOD_PLAN.replace("## A. 技术决策", "## A 技术决策")
        rc, ch = run(write_case("variants", spec=spec, plan=plan))
        self.assertEqual((rc, failed(ch)), (0, []))

    def test_generic_type_not_placeholder(self):
        plan = GOOD_PLAN.replace("- **选什么**：store_true", "- **选什么**：Map<…> 的形状")
        rc, ch = run(write_case("generic", plan=plan))
        self.assertEqual((rc, failed(ch)), (0, []))

    def test_missing_dir_exit_2(self):
        rc, _ = run("/tmp/rsi-t5/fixtures/__not_exist__")
        self.assertEqual(rc, 2)

    def test_missing_file_exit_2(self):
        rc, _ = run(write_case("only_spec", plan=None))
        self.assertEqual(rc, 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
