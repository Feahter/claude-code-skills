#!/usr/bin/env python3
import unittest
from pathlib import Path

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
            "F1 命令/脚本自身报错",
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


class VerificationSignalTests(unittest.TestCase):
    def test_pure_git_claim_does_not_require_test_signal(self):
        self.assertFalse(scan._needs_verify("已提交并推送"))

    def test_fix_claim_requires_test_signal(self):
        self.assertTrue(scan._needs_verify("问题已修复并提交"))


if __name__ == "__main__":
    unittest.main()
