from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, Optional, Sequence, Tuple


PhraseEntry = Tuple[str, str]
PhraseTable = Tuple[PhraseEntry, ...]


@dataclass(frozen=True)
class Intent:
    """Result returned by IntentRouter."""

    need_photo: bool
    qwen_text: str

    # The following fields improve debugging while remaining backward
    # compatible with code that only reads need_photo and qwen_text.
    matched_rule: str = ""
    matched_phrases: Tuple[str, ...] = ()


class IntentRouter:
    """Route ordinary text requests and camera-based visual requests.

    The legacy implementation treated every configured keyword as an
    independent camera trigger. Generic words such as "描述", "几个" and
    "有什么" therefore caused false camera activations.

    The formal policy is intentionally conservative:

    1. Explicit capture commands always trigger the camera.
    2. Exact short visual commands trigger the camera.
    3. A visual action combined with a visual context triggers the camera.
    4. Generic query words alone never trigger the camera.
    5. Text-oriented contexts such as code and algorithms suppress an
       otherwise ambiguous visual action/context match.
    """

    DEFAULT_EXPLICIT_CAPTURE_PHRASES = (
        "拍照",
        "拍一张",
        "照一张",
        "拍个照",
        "拍一下",
        "拍下来",
        "拍张图",
        "拍张照片",
        "拍一张照片",
        "拍个照片",
        "拍个图片",
    )

    DEFAULT_DIRECT_VISUAL_COMMANDS = (
        "看镜头",
        "看画面",
        "看摄像头",
        "看图片",
        "看照片",
        "看图像",
        "看看镜头",
        "看看画面",
    )

    DEFAULT_VISUAL_CONTEXT_PHRASES = (
        "摄像头",
        "当前摄像头",
        "镜头",
        "镜头里",
        "画面",
        "当前画面",
        "实时画面",
        "画面里",
        "照片",
        "照片里",
        "图片",
        "图片里",
        "图像",
        "眼前",
        "当前视野",
        "视野里",
        "现在看到",
        "当前看到",
    )

    DEFAULT_VISUAL_ACTION_PHRASES = (
        "看一下",
        "看看",
        "看一看",
        "帮我看",
        "帮我看看",
        "看下",
        "看一眼",
        "你看",
        "描述一下",
        "描述",
        "识别一下",
        "识别",
        "辨认",
        "读一下",
        "念一下",
        "有什么",
        "有哪些",
        "多少个",
        "几个",
        "颜色",
        "文字",
    )

    DEFAULT_TEXT_CONTEXT_BLOCKERS = (
        "代码",
        "源码",
        "算法",
        "原理",
        "教程",
        "格式",
        "文件",
        "模型",
        "论文",
        "程序",
        "编程",
        "数据结构",
    )

    def __init__(
        self,
        photo_keywords: Sequence[str],
        image_prefix_trigger: str,
        image_prefix: str,
        *,
        explicit_capture_phrases: Sequence[str] = (),
        direct_visual_commands: Sequence[str] = (),
        visual_context_phrases: Sequence[str] = (),
        visual_action_phrases: Sequence[str] = (),
        text_context_blockers: Sequence[str] = (),
    ):
        # Retained for compatibility and configuration inspection.
        # It is no longer used as a broad any-keyword trigger.
        self.photo_keywords = tuple(photo_keywords)

        self.image_prefix_trigger = str(
            image_prefix_trigger or ""
        )
        self.image_prefix = str(image_prefix or "")

        self._explicit_capture_phrases = self._prepare_phrases(
            explicit_capture_phrases
            or self.DEFAULT_EXPLICIT_CAPTURE_PHRASES
        )
        self._direct_visual_commands = self._prepare_phrases(
            direct_visual_commands
            or self.DEFAULT_DIRECT_VISUAL_COMMANDS
        )
        self._visual_context_phrases = self._prepare_phrases(
            visual_context_phrases
            or self.DEFAULT_VISUAL_CONTEXT_PHRASES
        )
        self._visual_action_phrases = self._prepare_phrases(
            visual_action_phrases
            or self.DEFAULT_VISUAL_ACTION_PHRASES
        )
        self._text_context_blockers = self._prepare_phrases(
            text_context_blockers
            or self.DEFAULT_TEXT_CONTEXT_BLOCKERS
        )

    @classmethod
    def from_config(
        cls,
        config: dict,
    ) -> "IntentRouter":
        intent = config["intent"]

        return cls(
            photo_keywords=intent.get(
                "photo_keywords",
                [],
            ),
            image_prefix_trigger=intent.get(
                "image_prefix_trigger",
                "图片",
            ),
            image_prefix=intent.get(
                "image_prefix",
                "<图片>",
            ),
            explicit_capture_phrases=intent.get(
                "explicit_capture_phrases",
                cls.DEFAULT_EXPLICIT_CAPTURE_PHRASES,
            ),
            direct_visual_commands=intent.get(
                "direct_visual_commands",
                cls.DEFAULT_DIRECT_VISUAL_COMMANDS,
            ),
            visual_context_phrases=intent.get(
                "visual_context_phrases",
                cls.DEFAULT_VISUAL_CONTEXT_PHRASES,
            ),
            visual_action_phrases=intent.get(
                "visual_action_phrases",
                cls.DEFAULT_VISUAL_ACTION_PHRASES,
            ),
            text_context_blockers=intent.get(
                "text_context_blockers",
                cls.DEFAULT_TEXT_CONTEXT_BLOCKERS,
            ),
        )

    @staticmethod
    def _normalize_text(
        text: object,
    ) -> str:
        return "".join(
            str(text or "")
            .strip()
            .lower()
            .split()
        )

    @classmethod
    def _prepare_phrases(
        cls,
        phrases: Iterable[str],
    ) -> PhraseTable:
        result = []
        seen = set()

        for phrase in phrases:
            original = str(phrase or "").strip()
            normalized = cls._normalize_text(original)

            if not normalized:
                continue

            if normalized in seen:
                continue

            seen.add(normalized)
            result.append(
                (
                    normalized,
                    original,
                )
            )

        return tuple(result)

    @staticmethod
    def _first_substring_match(
        normalized_text: str,
        phrase_table: PhraseTable,
    ) -> Optional[str]:
        for normalized_phrase, original_phrase in phrase_table:
            if normalized_phrase in normalized_text:
                return original_phrase

        return None

    @staticmethod
    def _exact_match(
        normalized_text: str,
        phrase_table: PhraseTable,
    ) -> Optional[str]:
        for normalized_phrase, original_phrase in phrase_table:
            if normalized_text == normalized_phrase:
                return original_phrase

        return None

    def analyze(
        self,
        text: str,
    ) -> Intent:
        cleaned_text = str(text or "").strip()
        normalized_text = self._normalize_text(
            cleaned_text
        )

        if not normalized_text:
            return Intent(
                need_photo=False,
                qwen_text=cleaned_text,
                matched_rule="empty_text",
            )

        explicit_match = self._first_substring_match(
            normalized_text,
            self._explicit_capture_phrases,
        )

        direct_match = self._exact_match(
            normalized_text,
            self._direct_visual_commands,
        )

        context_match = self._first_substring_match(
            normalized_text,
            self._visual_context_phrases,
        )

        action_match = self._first_substring_match(
            normalized_text,
            self._visual_action_phrases,
        )

        blocker_match = self._first_substring_match(
            normalized_text,
            self._text_context_blockers,
        )

        need_photo = False
        matched_rule = ""
        matched_phrases = ()

        if explicit_match:
            need_photo = True
            matched_rule = "explicit_capture"
            matched_phrases = (explicit_match,)

        elif direct_match:
            need_photo = True
            matched_rule = "direct_visual_command"
            matched_phrases = (direct_match,)

        elif (
            context_match
            and action_match
            and not blocker_match
        ):
            need_photo = True
            matched_rule = "visual_action_and_context"
            matched_phrases = (
                action_match,
                context_match,
            )

        elif (
            context_match
            and action_match
            and blocker_match
        ):
            matched_rule = "blocked_text_context"
            matched_phrases = (
                action_match,
                context_match,
                blocker_match,
            )

        qwen_text = cleaned_text

        normalized_prefix_trigger = self._normalize_text(
            self.image_prefix_trigger
        )

        # Preserve the original image-prefix behavior only for requests
        # that have already been classified as visual.
        if (
            need_photo
            and normalized_prefix_trigger
            and normalized_prefix_trigger
            in normalized_text
            and self.image_prefix
            and not cleaned_text.startswith(
                self.image_prefix
            )
        ):
            qwen_text = (
                f"{self.image_prefix}{cleaned_text}"
            )

        return Intent(
            need_photo=need_photo,
            qwen_text=qwen_text,
            matched_rule=matched_rule,
            matched_phrases=matched_phrases,
        )
