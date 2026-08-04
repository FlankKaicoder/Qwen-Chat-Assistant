from __future__ import annotations

import unittest
from pathlib import Path
from unittest.mock import patch

from voice_assistant.config import load_config
from voice_assistant.orchestrator import VoiceAssistant


class FakeQwenRunner:
    """Record Qwen requests without starting the real demo."""

    def __init__(self):
        self.calls = []

    def ask(
        self,
        image_path,
        text,
        max_new_tokens=None,
    ):
        self.calls.append(
            {
                "mode": "ask",
                "image_path": Path(image_path),
                "text": str(text),
                "max_new_tokens": max_new_tokens,
            }
        )

        return "FAKE_QWEN_ANSWER"

    def ask_stream(
        self,
        image_path,
        text,
        on_sentence=None,
        max_new_tokens=None,
    ):
        self.calls.append(
            {
                "mode": "ask_stream",
                "image_path": Path(image_path),
                "text": str(text),
                "max_new_tokens": max_new_tokens,
            }
        )

        if callable(on_sentence):
            on_sentence("FAKE_QWEN_ANSWER")

        return "FAKE_QWEN_ANSWER"


class FakeStreamingTtsPlayer:
    """Prevent accidental real TTS playback during tests."""

    instances = []

    def __init__(self, config):
        self.config = config
        self.enqueued = []
        self.closed = False

        self.__class__.instances.append(self)

    def enqueue(self, text):
        self.enqueued.append(str(text))

    def close(self):
        self.closed = True


class OrchestratorIntentIntegrationTest(
    unittest.TestCase
):
    @classmethod
    def setUpClass(cls):
        cls.config = load_config(
            "config/default.yaml"
        )

    def setUp(self):
        FakeStreamingTtsPlayer.instances.clear()

        self.assistant = VoiceAssistant(
            self.config
        )

        self.fake_capture_paths = []
        self.fake_qwen = FakeQwenRunner()

        def fake_capture_photo():
            index = (
                len(self.fake_capture_paths)
                + 1
            )

            path = Path(
                f"/tmp/"
                f"exp11_fake_camera_{index}.jpg"
            )

            self.fake_capture_paths.append(path)
            return path

        # ask_qwen() calls self.capture_photo(), so patch that
        # exact instance method.
        self.capture_patcher = patch.object(
            self.assistant,
            "capture_photo",
            side_effect=fake_capture_photo,
        )

        self.capture_mock = (
            self.capture_patcher.start()
        )

        self.addCleanup(
            self.capture_patcher.stop
        )

        # ask_qwen() constructs QwenRunner(self.config) locally.
        # Patch the symbol where orchestrator.py looks it up.
        self.qwen_patcher = patch(
            "voice_assistant.orchestrator.QwenRunner",
            return_value=self.fake_qwen,
        )

        self.qwen_factory_mock = (
            self.qwen_patcher.start()
        )

        self.addCleanup(
            self.qwen_patcher.stop
        )

        # This should not be used because run_once tests explicitly
        # disable speak/play, but patch it as a hard safety barrier.
        self.tts_patcher = patch(
            "voice_assistant.orchestrator."
            "StreamingTtsPlayer",
            FakeStreamingTtsPlayer,
        )

        self.tts_patcher.start()

        self.addCleanup(
            self.tts_patcher.stop
        )

    def assert_single_qwen_call(self):
        self.assertEqual(
            len(self.fake_qwen.calls),
            1,
            msg=self.fake_qwen.calls,
        )

        self.qwen_factory_mock.assert_called_once_with(
            self.config
        )

        return self.fake_qwen.calls[0]

    def test_automatic_text_route_does_not_capture(
        self,
    ):
        text = "请解释图片格式有哪些"

        answer = self.assistant.ask_qwen(
            text,
            need_photo_override=None,
        )

        self.assertEqual(
            answer,
            "FAKE_QWEN_ANSWER",
        )

        self.assertEqual(
            self.capture_mock.call_count,
            0,
        )

        call = self.assert_single_qwen_call()

        self.assertEqual(
            call["image_path"],
            Path(
                self.config[
                    "paths"
                ][
                    "placeholder_image"
                ]
            ),
        )

        self.assertIn(
            text,
            call["text"],
        )

    def test_automatic_visual_route_captures_once(
        self,
    ):
        text = "识别图片中的文字"

        answer = self.assistant.ask_qwen(
            text,
            need_photo_override=None,
        )

        self.assertEqual(
            answer,
            "FAKE_QWEN_ANSWER",
        )

        self.assertEqual(
            self.capture_mock.call_count,
            1,
        )

        call = self.assert_single_qwen_call()

        self.assertEqual(
            call["image_path"],
            self.fake_capture_paths[0],
        )

        self.assertIn(
            text,
            call["text"],
        )

    def test_override_false_blocks_camera(
        self,
    ):
        text = "识别图片中的文字"

        answer = self.assistant.ask_qwen(
            text,
            need_photo_override=False,
        )

        self.assertEqual(
            answer,
            "FAKE_QWEN_ANSWER",
        )

        self.assertEqual(
            self.capture_mock.call_count,
            0,
        )

        call = self.assert_single_qwen_call()

        self.assertIn(
            text,
            call["text"],
        )

    def test_override_true_forces_camera(
        self,
    ):
        text = "一加一等于几"

        answer = self.assistant.ask_qwen(
            text,
            need_photo_override=True,
        )

        self.assertEqual(
            answer,
            "FAKE_QWEN_ANSWER",
        )

        self.assertEqual(
            self.capture_mock.call_count,
            1,
        )

        call = self.assert_single_qwen_call()

        self.assertEqual(
            call["image_path"],
            self.fake_capture_paths[0],
        )

        self.assertIn(
            text,
            call["text"],
        )

    def test_force_photo_overrides_false_route(
        self,
    ):
        text = "你是谁"

        answer = self.assistant.ask_qwen(
            text,
            force_photo=True,
            need_photo_override=False,
        )

        self.assertEqual(
            answer,
            "FAKE_QWEN_ANSWER",
        )

        self.assertEqual(
            self.capture_mock.call_count,
            1,
        )

        call = self.assert_single_qwen_call()

        self.assertEqual(
            call["image_path"],
            self.fake_capture_paths[0],
        )

    def test_run_once_override_false(
        self,
    ):
        answer = (
            self.assistant
            .run_once_from_text(
                "识别图片中的文字",
                speak=False,
                play=False,
                need_photo_override=False,
            )
        )

        self.assertEqual(
            answer,
            "FAKE_QWEN_ANSWER",
        )

        self.assertEqual(
            self.capture_mock.call_count,
            0,
        )

        self.assert_single_qwen_call()

        self.assertEqual(
            FakeStreamingTtsPlayer.instances,
            [],
        )

    def test_run_once_override_true(
        self,
    ):
        answer = (
            self.assistant
            .run_once_from_text(
                "一加一等于几",
                speak=False,
                play=False,
                need_photo_override=True,
            )
        )

        self.assertEqual(
            answer,
            "FAKE_QWEN_ANSWER",
        )

        self.assertEqual(
            self.capture_mock.call_count,
            1,
        )

        call = self.assert_single_qwen_call()

        self.assertEqual(
            call["image_path"],
            self.fake_capture_paths[0],
        )

        self.assertEqual(
            FakeStreamingTtsPlayer.instances,
            [],
        )


if __name__ == "__main__":
    unittest.main(
        verbosity=2
    )
