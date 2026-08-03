#!/usr/bin/env bash

set -u

PROJECT_DIR="/home/cat/ai/qwen3vl2b"
cd "$PROJECT_DIR" || exit 1

OUT_DIR="${1:-output/exp10_3h_apply_minimal_general_prompt_$(date +%Y%m%d_%H%M%S)}"
SOURCE="voice_assistant/controlled_session.py"

mkdir -p "$OUT_DIR"
LOG="$OUT_DIR/run.log"

exec > >(tee "$LOG") 2>&1

PATCH_RC=1
COMPILE_RC=1
UNIT_RC=1
RESTORED=0

echo "============================================================"
echo " Experiment 10.3h: Apply minimal general text prompt"
echo "============================================================"
echo "time    : $(date '+%Y-%m-%d %H:%M:%S')"
echo "out_dir : $OUT_DIR"
echo

echo "==================== 1. backup ===================="

cp -a "$SOURCE" "$OUT_DIR/controlled_session.py.before"

echo "[OK] backup created"
echo

echo "==================== 2. inspect current helper ===================="

.venv/bin/python - <<'PY' \
    | tee "$OUT_DIR/helper_before.txt"

from pathlib import Path

text = Path(
    "voice_assistant/controlled_session.py"
).read_text(encoding="utf-8")

start = text.find(
    "def _build_concise_text_prompt("
)

end = text.find(
    "\ndef ",
    start + 1,
)

if start < 0 or end < 0:
    raise SystemExit(
        "Cannot locate _build_concise_text_prompt"
    )

print(text[start:end])
PY

echo
echo "==================== 3. patch ===================="

set +e

.venv/bin/python - <<'PY'
from pathlib import Path


path = Path(
    "voice_assistant/controlled_session.py"
)

text = path.read_text(encoding="utf-8")

function_start = text.find(
    "def _build_concise_text_prompt("
)

function_end = text.find(
    "\ndef ",
    function_start + 1,
)

if function_start < 0 or function_end < 0:
    raise RuntimeError(
        "Cannot locate prompt builder function"
    )

old_function = text[
    function_start:function_end
]

new_function = '''def _build_concise_text_prompt(
    recognized_text: str,
    answer_max_chars: int,
) -> str:
    if _is_identity_question(recognized_text):
        return (
            "请直接回答用户的身份询问。"
            "说明你是运行在RK3588设备上的"
            "本地中文语音助手，"
            "可以进行普通问答和摄像头画面描述。"
            "不要声称你只能回答RK3588相关问题，"
            "不要使用标题、列表或分点，"
            "只输出一到两句自然中文，"
            f"尽量控制在{answer_max_chars}个汉字以内。"
        )

    return (
        "请简短回答这个问题："
        f"{recognized_text}"
    )

'''

if old_function == new_function.rstrip("\n"):
    print("[SKIP] minimal prompt already applied")
else:
    text = (
        text[:function_start]
        + new_function
        + text[function_end + 1:]
    )

    path.write_text(
        text,
        encoding="utf-8",
    )

    print("[PATCH] minimal general prompt applied")
PY

PATCH_RC=$?

set -e

echo "patch_return_code: $PATCH_RC"

if [ "$PATCH_RC" -ne 0 ]; then
    cp -a \
        "$OUT_DIR/controlled_session.py.before" \
        "$SOURCE"

    echo "[RESULT] Experiment 10.3h PATCH_FAILED_AND_RESTORED."
    exit 1
fi

echo
echo "==================== 4. compile ===================="

set +e

.venv/bin/python -m py_compile \
    voice_assistant/controlled_session.py \
    voice_assistant/orchestrator.py \
    voice_assistant/intent.py \
    voice_assistant/qwen_runner.py \
    voice_assistant/cli.py \
    > "$OUT_DIR/compile_stdout.txt" \
    2> "$OUT_DIR/compile_stderr.txt"

COMPILE_RC=$?

set -e

echo "compile_return_code: $COMPILE_RC"
cat "$OUT_DIR/compile_stdout.txt"
cat "$OUT_DIR/compile_stderr.txt"

if [ "$COMPILE_RC" -ne 0 ]; then
    cp -a \
        "$OUT_DIR/controlled_session.py.before" \
        "$SOURCE"

    RESTORED=1

    echo "[RESULT] Experiment 10.3h COMPILE_FAILED_AND_RESTORED."
    exit 1
fi

echo
echo "==================== 5. prompt unit test ===================="

set +e

.venv/bin/python - <<'PY' \
    > "$OUT_DIR/prompt_unit_test.txt" \
    2>&1

from voice_assistant.controlled_session import (
    _build_concise_text_prompt,
    _is_identity_question,
)


cases = (
    ("你是谁", True),
    ("一加一等于几", False),
    ("中国的首都是哪里", False),
)

failed = 0

for question, expected_identity in cases:
    identity = _is_identity_question(question)

    prompt = _build_concise_text_prompt(
        question,
        80,
    )

    print("=" * 60)
    print("question:", question)
    print("identity:", identity)
    print("prompt:", prompt)

    if identity != expected_identity:
        failed += 1

    if expected_identity:
        if "本地中文语音助手" not in prompt:
            print("[FAIL] identity description missing")
            failed += 1
    else:
        expected_prompt = (
            "请简短回答这个问题："
            + question
        )

        if prompt != expected_prompt:
            print("[FAIL] general prompt is not minimal")
            failed += 1

        forbidden_terms = (
            "RK3588",
            "运行平台",
            "语音助手",
            "摄像头",
            "不要",
            "除非",
        )

        matched = [
            term
            for term in forbidden_terms
            if term in prompt
        ]

        if matched:
            print(
                "[FAIL] distracting terms:",
                matched,
            )
            failed += 1

print()
print("failed_count:", failed)

if failed:
    raise SystemExit(1)

print("[OK] minimal prompt unit test passed")
PY

UNIT_RC=$?

set -e

cat "$OUT_DIR/prompt_unit_test.txt"
echo "prompt_unit_test_return_code: $UNIT_RC"

if [ "$UNIT_RC" -ne 0 ]; then
    cp -a \
        "$OUT_DIR/controlled_session.py.before" \
        "$SOURCE"

    RESTORED=1

    echo "[RESULT] Experiment 10.3h UNIT_TEST_FAILED_AND_RESTORED."
    exit 1
fi

echo
echo "==================== 6. diff ===================="

diff -u \
    "$OUT_DIR/controlled_session.py.before" \
    "$SOURCE" \
    > "$OUT_DIR/controlled_session.diff" || true

cat "$OUT_DIR/controlled_session.diff"

echo
echo "==================== 7. summary ===================="

{
    echo "out_dir                    : $OUT_DIR"
    echo "patch_return_code          : $PATCH_RC"
    echo "compile_return_code        : $COMPILE_RC"
    echo "prompt_unit_test_return_code: $UNIT_RC"
    echo "restored                   : $RESTORED"
    echo "minimal_prompt_count       : $(grep -c '请简短回答这个问题' "$SOURCE" || true)"
} | tee "$OUT_DIR/summary.txt"

echo

if [ "$PATCH_RC" -eq 0 ] \
  && [ "$COMPILE_RC" -eq 0 ] \
  && [ "$UNIT_RC" -eq 0 ] \
  && [ "$RESTORED" -eq 0 ]; then

    echo "[RESULT] Experiment 10.3h PATCH PASSED."
    echo "[NEXT] Run production-prompt semantic regression."
else
    echo "[RESULT] Experiment 10.3h FAILED_OR_NEEDS_CHECK."
    exit 1
fi
