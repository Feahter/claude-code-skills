#!/usr/bin/env python3
import contextlib
import io
import json
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest import mock

import scan


class CorrectionSignalTests(unittest.TestCase):
    def test_clear_corrections_match(self):
        samples = [
            "不对，这里不应该改全局配置",
            "我没让你提交，先停一下",
            "为什么你又跳过测试了？",
            "你这个改法有问题",
            "please stop, that's not right",
        ]
        for text in samples:
            with self.subTest(text=text):
                self.assertRegex(text, scan.COR_RE)

    def test_neutral_instructions_do_not_match(self):
        samples = [
            "你这个方案不错，继续做",
            "先看看文件结构，再告诉我你的判断",
            "为什么要这样设计？",
            "你看这样对不对",
            "我还没读这份方案",
            "wait for the test process to finish",
            "Stop hook error: JSON validation failed",
            "读完这份文档后总结一下",
        ]
        for text in samples:
            with self.subTest(text=text):
                self.assertNotRegex(text, scan.COR_RE)

    def test_system_injection_is_not_real_user_text(self):
        real, _ = scan.is_real_user_text(
            {"content": "This session is being continued from a previous conversation"}
        )
        self.assertFalse(real)

    def test_stop_hook_injection_is_not_real_user_text(self):
        real, _ = scan.is_real_user_text(
            {"content": 'A session-scoped Stop hook is now active with condition: "继续任务"'}
        )
        self.assertFalse(real)

    def test_is_meta_flag_excludes_skill_body_injection(self):
        # skill 正文没有固定前缀可匹配，只能靠记录顶层的 isMeta 标记
        real, _ = scan.is_real_user_text(
            {"content": "Approach this as the design lead at a small studio, don't over-design"},
            is_meta=True,
        )
        self.assertFalse(real)

    def test_is_meta_flag_excludes_goal_checkin(self):
        real, _ = scan.is_real_user_text(
            {"content": "Goal check-in: «.workflow/foo/handoff.md» 这样不对，重新拆"},
            is_meta=True,
        )
        self.assertFalse(real)

    def test_same_text_without_meta_flag_is_real(self):
        # 反向：同一段文字不带 isMeta 时必须仍算真实用户消息，否则等于把用户输入误杀
        real, text = scan.is_real_user_text({"content": "这样不对，重新拆"})
        self.assertTrue(real)
        self.assertEqual(text, "这样不对，重新拆")

    def test_teammate_message_is_not_real_user_text(self):
        real, _ = scan.is_real_user_text(
            {"content": '<teammate-message teammate_id="worker">任务完成</teammate-message>'}
        )
        self.assertFalse(real)

    def test_project_name_strips_claude_path_prefix(self):
        encoded_home = str(Path.home()).replace("/", "-")
        path = Path("/tmp") / f"{encoded_home}-projects-demo-app" / "session.jsonl"
        self.assertEqual(scan.project_name(path), "demo-app")

    def test_initial_question_is_not_a_correction(self):
        self.assertFalse(scan.is_correction("参数设置得不对吗？", False))
        self.assertTrue(scan.is_correction("你的参数设置不对", True))


class FailBucketTests(unittest.TestCase):
    def test_search_command_no_match_is_normal_semantics(self):
        self.assertEqual(
            scan.fail_bucket("Exit code 1", "grep -n 'foo' src/bar.ts"),
            "E1 检索/比较类无匹配(正常语义)",
        )

    def test_search_piped_from_build_tool_is_real_failure(self):
        # 覆盖 BUILD_TOOL_RE 排除：命令里同时有 grep 和构建工具时，非零退出
        # 可能来自构建工具本身，不能算检索无匹配。去掉那个排除这条就会变红。
        self.assertEqual(
            scan.fail_bucket("Exit code 1", "yarn test 2>&1 | grep -c 'passed'"),
            "F1b 构建/测试命令非零",
        )

    def test_build_failure_with_type_error_is_not_script_error(self):
        # 测试失败的输出常带 TypeError。构建工具判定挪到脚本错误签名之后，
        # 这条就会变红（归成 F1a）。
        self.assertEqual(
            scan.fail_bucket("Exit code 1\nTypeError: x is undefined\n 3 failed", "yarn vitest run"),
            "F1b 构建/测试命令非零",
        )

    def test_interpreter_error_is_script_error(self):
        self.assertEqual(
            scan.fail_bucket("Exit code 1\nTraceback (most recent call last):\n  File \"<string>\"", "python3 -c 'import x'"),
            "F1a 脚本语法/运行时错误",
        )
        self.assertEqual(
            scan.fail_bucket("Exit code 2\nawk: syntax error at source line 1", "awk '{a[NR]=$1}' f"),
            "F1a 脚本语法/运行时错误",
        )

    def test_trailing_probe_failure_is_other_nonzero(self):
        # 多段命令前面已经有有效输出，只是末环非零。
        self.assertEqual(
            scan.fail_bucket("Exit code 2\ncheck-this: 非git\n/Users/x/.skill-lock.json", "for s in a b; do git -C $s rev-parse; done; ls x y"),
            "F1c 其他非零(多为多段命令末环)",
        )

    def test_test_in_path_is_not_a_search_feature(self):
        # 覆盖 SEARCH_CMD_RE 不含 test：`test` 会匹配仓库名 demo-web-test、
        # `yarn test` 和路径片段，把真实失败误判成正常语义。把 test 加回
        # SEARCH_CMD_RE 这条就会变红（归成 E1 而不是 E2）。
        self.assertEqual(
            scan.fail_bucket(
                "Exit code 1\nls: dist: No such file or directory",
                "cd /Users/me/projects/demo-web-test && ls dist",
            ),
            "E2 路径不存在(多为探测)",
        )

    def test_sigterm_not_swallowed_by_exit_code_1_branch(self):
        self.assertEqual(
            scan.fail_bucket("Exit code 143", "until grep -q done log; do sleep 5; done"),
            "D1 命令被超时杀掉(143)",
        )

    def test_buckets_do_not_overlap_on_gate_errors(self):
        self.assertEqual(
            scan.fail_bucket("<tool_use_error>Blocked: sleep 100 followed by: tail -5 x.log", "sleep 100; tail -5 x.log"),
            "A1 harness 拦截 sleep 前台轮询",
        )
        self.assertEqual(
            scan.fail_bucket("<tool_use_error>InputValidationError: command contains control characters", "node -e '...'"),
            "B1 工具参数校验失败",
        )


class RetryDetectionTests(unittest.TestCase):
    def _records(self, cmds):
        return [
            (i, {"type": "assistant", "message": {"content": [
                {"type": "tool_use", "name": "Bash", "id": f"t{i}", "input": {"command": c}}
            ]}})
            for i, c in enumerate(cmds)
        ]

    def test_next_bash_cmds_collects_following_commands(self):
        recs = self._records(["failed cmd", "retry cmd", "third cmd", "fourth cmd"])
        self.assertEqual(scan.next_bash_cmds(recs, 0), ["retry cmd", "third cmd", "fourth cmd"])

    def test_next_bash_cmds_empty_at_tail(self):
        self.assertEqual(scan.next_bash_cmds(self._records(["only"]), 0), [])

    def test_classify_retry(self):
        self.assertEqual(scan.classify_retry("ls /a/b", []), "no_followup")
        self.assertEqual(scan.classify_retry("ls /a/b", ["ls /a/b"]), "retry_near_identical")
        self.assertEqual(scan.classify_retry("ls /a/b", ["git status"]), "moved_on")


class VerificationSignalTests(unittest.TestCase):
    def test_pure_git_claim_does_not_require_test_signal(self):
        self.assertFalse(scan._needs_verify("已提交并推送"))

    def test_fix_claim_requires_test_signal(self):
        self.assertTrue(scan._needs_verify("问题已修复并提交"))

    def test_code_edit_detection(self):
        self.assertTrue(scan.is_code_edit({"name": "Edit", "input": {"file_path": "/x/a.tsx"}}))
        self.assertTrue(scan.is_code_edit({"name": "Write", "input": {"file_path": "/x/scan.py"}}))
        self.assertFalse(scan.is_code_edit({"name": "Write", "input": {"file_path": "/x/report.html"}}))
        self.assertFalse(scan.is_code_edit({"name": "Edit", "input": {"file_path": "/x/MEMORY.md"}}))
        self.assertFalse(scan.is_code_edit({"name": "Read", "input": {"file_path": "/x/a.ts"}}))

    def test_verify_re_covers_project_test_runners(self):
        for cmd in ["npx vitest run src", "npx playwright test e2e/", "python3 -m unittest -q", "python3 test_scan.py"]:
            with self.subTest(cmd=cmd):
                self.assertRegex(cmd, scan.VERIFY_RE)
        self.assertNotRegex("npx playwright show-report", scan.VERIFY_RE)

    def test_headless_session_detection(self):
        self.assertTrue(scan.is_headless_session([(0, {"type": "queue-operation"}), (1, {"entrypoint": "sdk-cli"})]))
        self.assertFalse(scan.is_headless_session([(0, {"entrypoint": "cli"})]))
        self.assertFalse(scan.is_headless_session([(0, {"type": "user"})]))


def _ts(i):
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", f".{i:03d}Z")


def _user(text, i, entrypoint="cli"):
    return {"type": "user", "entrypoint": entrypoint, "timestamp": _ts(i), "message": {"content": text}}


def _assistant(i, text=None, tool=None):
    content = []
    if text:
        content.append({"type": "text", "text": text})
    if tool:
        content.append({"type": "tool_use", "id": f"t{i}", **tool})
    return {"type": "assistant", "timestamp": _ts(i), "message": {"id": f"m{i}", "content": content}}


class ScanEndToEndTests(unittest.TestCase):
    """把三处过滤串起来跑一遍 main(),确认接线正确而不只是辅助函数正确。"""

    def _run(self, sessions):
        with tempfile.TemporaryDirectory() as root:
            proj = Path(root) / "-tmp-proj"
            proj.mkdir()
            for name, recs in sessions.items():
                (proj / f"{name}.jsonl").write_text("\n".join(json.dumps(r) for r in recs))
            out = Path(root) / "raw.json"
            argv = ["scan.py", "--days", "1", "--output", str(out)]
            with mock.patch.object(scan, "ROOT", Path(root)), mock.patch.object(sys, "argv", argv), \
                    contextlib.redirect_stdout(io.StringIO()):
                scan.main()
            return json.loads(out.read_text())

    def test_headless_prompt_not_counted_as_rollback(self):
        data = self._run({
            "interactive": [_user("改一下", 0), _assistant(1, "好的"), _user("方向不对，重来", 2)],
            "headless": [_user("你是帮我写每日工作日报的助手。不要自创样式，重来", 0, "sdk-cli"),
                         _assistant(1, "1. 做了什么【已完成】"), _user("重来", 2, "sdk-cli")],
        })
        g = data["global"]
        self.assertEqual(g["rollbacks"], 1)
        self.assertEqual(g["user_msgs"], 2)
        self.assertEqual(g["headless_msgs"], 2)

    def test_unverified_only_counts_turns_that_edited_code(self):
        edit = {"name": "Edit", "input": {"file_path": "/x/a.ts", "old_string": "a", "new_string": "b"}}
        data = self._run({"s": [
            _user("修个 bug", 0), _assistant(1, tool=edit), _assistant(2, "已修复"),
            _user("发日报", 3), _assistant(4, "日报已完成发送"),
        ]})
        self.assertEqual(data["global"]["completion_no_verify"], 1)
        self.assertEqual(data["unverified_examples"][0]["claim"], "已修复")

    def test_retry_examples_recorded(self):
        bash = {"name": "Bash", "input": {"command": "ls /nope"}}
        fail = {"type": "user", "timestamp": _ts(2), "message": {"content": [
            {"type": "tool_result", "tool_use_id": "t1", "is_error": True, "content": "Exit code 1"}]}}
        data = self._run({"s": [_user("看看", 0), _assistant(1, tool=bash), fail, _assistant(3, tool=bash)]})
        self.assertEqual(data["retry_after_fail"], {"retry_near_identical": 1})
        self.assertEqual(data["retry_examples"]["retry_near_identical"][0]["failed_cmd"], "ls /nope")


if __name__ == "__main__":
    unittest.main()
