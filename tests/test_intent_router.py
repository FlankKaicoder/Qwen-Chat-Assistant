from __future__ import annotations

import unittest

from voice_assistant.config import load_config
from voice_assistant.intent import IntentRouter


class IntentRouterTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        config = load_config(
            "config/default.yaml"
        )
        cls.router = IntentRouter.from_config(
            config
        )

    def test_visual_positive_cases(self):
        cases = (
            "拍照看一下画面",
            "帮我拍一张",
            "请拍一下",
            "拍张照片",
            "看一下镜头",
            "摄像头前面有什么",
            "描述当前画面",
            "识别图片中的文字",
            "看看实时画面",
            "当前视野里有哪些东西",
            "看镜头",
        )

        for text in cases:
            with self.subTest(text=text):
                result = self.router.analyze(
                    text
                )

                self.assertTrue(
                    result.need_photo,
                    msg=(
                        f"Expected visual request: "
                        f"{text!r}; result={result!r}"
                    ),
                )

                self.assertTrue(
                    result.matched_rule,
                    msg=(
                        "Visual result should record "
                        "a matched rule"
                    ),
                )

    def test_text_negative_cases(self):
        cases = (
            "你是谁",
            "一加一等于几",
            "这几个字是什么意思",
            "帮我写几个汉字",
            "请描述一下线程池原理",
            "这个问题有什么解决方法",
            "请识别一下这个算法的复杂度",
            "颜色空间转换的原理是什么",
            "图片格式有哪些",
            "请解释图像算法原理",
            "请帮我看看图片处理代码",
            "这个模型识别效果怎么样",
            "",
            "   ",
        )

        for text in cases:
            with self.subTest(text=text):
                result = self.router.analyze(
                    text
                )

                self.assertFalse(
                    result.need_photo,
                    msg=(
                        f"Expected text request: "
                        f"{text!r}; result={result!r}"
                    ),
                )

    def test_explicit_capture_overrides_text_blocker(self):
        result = self.router.analyze(
            "请拍照看看这段代码"
        )

        self.assertTrue(
            result.need_photo
        )
        self.assertEqual(
            result.matched_rule,
            "explicit_capture",
        )

    def test_image_prefix_added_only_for_visual_request(self):
        visual_result = self.router.analyze(
            "识别图片中的文字"
        )

        self.assertTrue(
            visual_result.need_photo
        )
        self.assertTrue(
            visual_result.qwen_text.startswith(
                "<图片>"
            )
        )

        text_result = self.router.analyze(
            "请解释图片格式"
        )

        self.assertFalse(
            text_result.need_photo
        )
        self.assertEqual(
            text_result.qwen_text,
            "请解释图片格式",
        )

    def test_whitespace_normalization(self):
        result = self.router.analyze(
            "  看 一下 镜头  "
        )

        self.assertTrue(
            result.need_photo
        )

    def test_backward_compatible_fields(self):
        result = self.router.analyze(
            "你是谁"
        )

        self.assertIsInstance(
            result.need_photo,
            bool,
        )
        self.assertIsInstance(
            result.qwen_text,
            str,
        )


if __name__ == "__main__":
    unittest.main(
        verbosity=2
    )
