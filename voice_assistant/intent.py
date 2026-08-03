from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Intent:
    need_photo: bool
    qwen_text: str


class IntentRouter:
    def __init__(self, photo_keywords: list[str], image_prefix_trigger: str, image_prefix: str):
        self.photo_keywords = tuple(photo_keywords)
        self.image_prefix_trigger = image_prefix_trigger
        self.image_prefix = image_prefix

    @classmethod
    def from_config(cls, config: dict) -> "IntentRouter":
        intent = config["intent"]
        return cls(
            photo_keywords=intent["photo_keywords"],
            image_prefix_trigger=intent["image_prefix_trigger"],
            image_prefix=intent["image_prefix"],
        )

    def analyze(self, text: str) -> Intent:
        normalized = text.strip()
        need_photo = any(keyword in normalized for keyword in self.photo_keywords)
        if self.image_prefix_trigger in normalized and not normalized.startswith(self.image_prefix):
            normalized = f"{self.image_prefix}{normalized}"
        return Intent(need_photo=need_photo, qwen_text=normalized)


# ================================================================
# BEGIN EXP10 STRICT VISUAL INTENT POLICY
#
# The original implementation uses a broad substring keyword list.
# Generic terms such as "几个", "有什么" and "颜色" can therefore
# incorrectly trigger the camera during ordinary text questions.
#
# The final decision below follows a conservative command grammar:
#   1. An explicit photo-taking command triggers the camera.
#   2. An explicit visual context noun triggers the camera.
#   3. Generic query words alone never trigger the camera.
# ================================================================

from dataclasses import is_dataclass as _exp10_is_dataclass
from dataclasses import replace as _exp10_dataclass_replace
from types import SimpleNamespace as _Exp10SimpleNamespace


_EXP10_EXPLICIT_CAPTURE_PHRASES = (
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


_EXP10_VISUAL_CONTEXT_PHRASES = (
    "摄像头",
    "当前摄像头",
    "镜头",
    "画面",
    "当前画面",
    "实时画面",
    "照片",
    "图片",
    "图像",
    "眼前",
    "当前视野",
    "视野里",
    "镜头里",
    "画面里",
    "图片里",
    "照片里",
    "现在看到",
    "当前看到",
)


def _exp10_normalize_intent_text(text):
    return "".join(
        str(text or "")
        .strip()
        .lower()
        .split()
    )


def _exp10_is_strict_visual_request(text):
    normalized = _exp10_normalize_intent_text(text)

    if not normalized:
        return False

    if any(
        phrase.lower() in normalized
        for phrase in _EXP10_EXPLICIT_CAPTURE_PHRASES
    ):
        return True

    if any(
        phrase.lower() in normalized
        for phrase in _EXP10_VISUAL_CONTEXT_PHRASES
    ):
        return True

    return False


_exp10_legacy_analyze = IntentRouter.analyze


def _exp10_replace_intent_result(
    result,
    need_photo,
    original_text,
):
    qwen_text = getattr(
        result,
        "qwen_text",
        original_text,
    )

    # When the strict policy rejects a legacy false positive,
    # ensure the original user text is forwarded unchanged.
    if not need_photo:
        qwen_text = original_text

    if _exp10_is_dataclass(result):
        updates = {
            "need_photo": bool(need_photo),
        }

        if hasattr(result, "qwen_text"):
            updates["qwen_text"] = qwen_text

        return _exp10_dataclass_replace(
            result,
            **updates,
        )

    if hasattr(result, "_replace"):
        updates = {
            "need_photo": bool(need_photo),
        }

        if hasattr(result, "qwen_text"):
            updates["qwen_text"] = qwen_text

        return result._replace(**updates)

    try:
        result.need_photo = bool(need_photo)

        if hasattr(result, "qwen_text"):
            result.qwen_text = qwen_text

        return result
    except Exception:
        return _Exp10SimpleNamespace(
            need_photo=bool(need_photo),
            qwen_text=qwen_text,
        )


def _exp10_strict_analyze(self, text):
    legacy_result = _exp10_legacy_analyze(
        self,
        text,
    )

    strict_need_photo = (
        _exp10_is_strict_visual_request(text)
    )

    return _exp10_replace_intent_result(
        legacy_result,
        strict_need_photo,
        text,
    )


IntentRouter.analyze = _exp10_strict_analyze

# END EXP10 STRICT VISUAL INTENT POLICY
