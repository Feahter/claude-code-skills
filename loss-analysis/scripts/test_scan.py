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


class VerificationSignalTests(unittest.TestCase):
    def test_pure_git_claim_does_not_require_test_signal(self):
        self.assertFalse(scan._needs_verify("已提交并推送"))

    def test_fix_claim_requires_test_signal(self):
        self.assertTrue(scan._needs_verify("问题已修复并提交"))


if __name__ == "__main__":
    unittest.main()
