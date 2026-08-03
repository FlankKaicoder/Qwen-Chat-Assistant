#!/usr/bin/env bash

set -u

PROJECT_DIR="/home/cat/ai/qwen3vl2b"
cd "$PROJECT_DIR" || exit 1

OUT_DIR="${1:-output/exp10_3e_v4_strict_visual_intent_$(date +%Y%m%d_%H%M%S)}"
TARGET="voice_assistant/intent.py"
LOG="$OUT_DIR/run.log"

mkdir -p "$OUT_DIR"
exec > >(tee "$LOG") 2>&1

PATCH_RC=0
COMPILE_RC=1
TEST_RC=1
RESTORED=0

echo "============================================================"
echo " Experiment 10.3e-v4: Strict visual intent policy"
echo "============================================================"
echo "time    : $(date '+%Y-%m-%d %H:%M:%S')"
echo "out_dir : $OUT_DIR"
echo

echo "==================== 1. backup ===================="

cp -a \
  "$TARGET" \
  "$OUT_DIR/intent.py.before"

echo "[OK] backup created"
echo

echo "==================== 2. append strict policy ===================="

if grep -q \
  "BEGIN EXP10 STRICT VISUAL INTENT POLICY" \
  "$TARGET"; then

    echo "[SKIP] strict policy already exists"
else
    cat >> "$TARGET" <<'PYCODE'


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
PYCODE

    PATCH_RC=$?

    if [ "$PATCH_RC" -eq 0 ]; then
        echo "[PATCH] strict visual intent policy appended"
    fi
fi

echo "patch_return_code: $PATCH_RC"
echo

echo "==================== 3. compile ===================="

.venv/bin/python -m py_compile \
  voice_assistant/intent.py \
  voice_assistant/orchestrator.py \
  voice_assistant/controlled_session.py \
  > "$OUT_DIR/compile_stdout.txt" \
  2> "$OUT_DIR/compile_stderr.txt"

COMPILE_RC=$?

echo "compile_return_code: $COMPILE_RC"
cat "$OUT_DIR/compile_stdout.txt"
cat "$OUT_DIR/compile_stderr.txt"
echo

echo "==================== 4. regression test ===================="

if [ "$COMPILE_RC" -eq 0 ]; then
    .venv/bin/python - <<'PY' \
      > "$OUT_DIR/intent_regression_test.txt" \
      2>&1

import voice_assistant.intent as intent_module
from voice_assistant.config import load_config
from voice_assistant.intent import IntentRouter


cfg = load_config("config/default.yaml")
router = IntentRouter.from_config(cfg)

cases = (
    # Ordinary text questions: camera must remain off.
    ("你是谁", False),
    ("一加一等于几", False),
    ("这几个字是什么意思", False),
    ("帮我写几个汉字", False),
    ("红色是什么意思", False),
    ("这段文字有几个字", False),
    ("请描述一下线程池原理", False),
    ("这个问题有什么解决方法", False),

    # Explicit visual requests: camera must turn on.
    ("拍照看一下画面", True),
    ("帮我拍一张", True),
    ("看一下镜头", True),
    ("摄像头前面有什么", True),
    ("描述当前画面", True),
    ("识别图片中的文字", True),
    ("读一下照片里的文字", True),
)

failed_count = 0

for text, expected in cases:
    strict_result = router.analyze(text)

    legacy_result = (
        intent_module
        ._exp10_legacy_analyze(
            router,
            text,
        )
    )

    actual = bool(strict_result.need_photo)
    legacy = bool(legacy_result.need_photo)
    ok = actual == expected

    print(
        f"text={text!r}, "
        f"expected={expected}, "
        f"legacy={legacy}, "
        f"strict={actual}, "
        f"ok={ok}"
    )

    print(
        "  qwen_text:",
        repr(
            getattr(
                strict_result,
                "qwen_text",
                None,
            )
        ),
    )

    if not ok:
        failed_count += 1

print()
print("failed_count:", failed_count)

if failed_count:
    raise SystemExit(1)

print(
    "[OK] strict visual intent regression passed"
)
PY

    TEST_RC=$?
else
    TEST_RC=1

    echo \
      "compile failed; regression test skipped" \
      > "$OUT_DIR/intent_regression_test.txt"
fi

cat "$OUT_DIR/intent_regression_test.txt"
echo "intent_test_return_code: $TEST_RC"
echo

echo "==================== 5. diff ===================="

diff -u \
  "$OUT_DIR/intent.py.before" \
  "$TARGET" \
  > "$OUT_DIR/intent.diff" || true

cat "$OUT_DIR/intent.diff"
echo

echo "==================== 6. result ===================="

if [ "$PATCH_RC" -ne 0 ] \
  || [ "$COMPILE_RC" -ne 0 ] \
  || [ "$TEST_RC" -ne 0 ]; then

    cp -a \
      "$OUT_DIR/intent.py.before" \
      "$TARGET"

    RESTORED=1

    echo "[RESTORE] intent.py restored"
fi

{
    echo "out_dir                : $OUT_DIR"
    echo "patch_return_code      : $PATCH_RC"
    echo "compile_return_code    : $COMPILE_RC"
    echo "intent_test_return_code: $TEST_RC"
    echo "restored               : $RESTORED"
} | tee "$OUT_DIR/summary.txt"

echo

if [ "$PATCH_RC" -eq 0 ] \
  && [ "$COMPILE_RC" -eq 0 ] \
  && [ "$TEST_RC" -eq 0 ] \
  && [ "$RESTORED" -eq 0 ]; then

    echo \
      "[RESULT] Experiment 10.3e-v4 STRICT_INTENT_PASSED."

    echo \
      "[NEXT] Rerun exp10.3e-v3 to apply prompt split and remove 字."
else
    echo \
      "[RESULT] Experiment 10.3e-v4 FAILED_AND_RESTORED."

    exit 1
fi
