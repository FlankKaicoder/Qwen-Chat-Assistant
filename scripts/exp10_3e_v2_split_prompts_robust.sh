#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="/home/cat/ai/qwen3vl2b"
cd "$PROJECT_DIR"

OUT_DIR="${1:-output/exp10_3e_v2_split_prompts_robust_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT_DIR/before"

SOURCE="voice_assistant/controlled_session.py"
CONFIG="config/default.yaml"
LOG="$OUT_DIR/run.log"

exec > >(tee "$LOG") 2>&1

restore_files() {
    cp -a "$OUT_DIR/before/controlled_session.py" "$SOURCE"
    cp -a "$OUT_DIR/before/default.yaml" "$CONFIG"
}

echo "============================================================"
echo " Experiment 10.3e-v2: Robust prompt split patch"
echo "============================================================"
echo "out_dir: $OUT_DIR"
echo

echo "==================== 1. backup ===================="

cp -a "$SOURCE" "$OUT_DIR/before/controlled_session.py"
cp -a "$CONFIG" "$OUT_DIR/before/default.yaml"

echo "[OK] backups saved"
echo

echo "==================== 2. current concise block ===================="

.venv/bin/python - <<'PY' | tee "$OUT_DIR/current_block.txt"
from pathlib import Path

text = Path(
    "voice_assistant/controlled_session.py"
).read_text(encoding="utf-8")

start_marker = '        if args.answer_mode == "concise":'
end_marker = '        if request_max_new_tokens is None:'

start = text.find(start_marker)
end = text.find(end_marker, start)

if start < 0 or end < 0:
    raise SystemExit(
        "Cannot locate concise answer block"
    )

print(text[start:end])
PY

echo
echo "==================== 3. patch ===================="

set +e

.venv/bin/python - <<'PY'
from pathlib import Path
import re


source_path = Path(
    "voice_assistant/controlled_session.py"
)
config_path = Path("config/default.yaml")

text = source_path.read_text(encoding="utf-8")
config_text = config_path.read_text(encoding="utf-8")


# ---------------------------------------------------------
# 1. 添加 Prompt 构造函数
# ---------------------------------------------------------

helper_marker = '''def _format_optional_float(value: Any) -> str:
'''

helper_code = '''def _is_identity_question(text: str) -> bool:
    normalized = "".join(text.strip().split())

    identity_phrases = (
        "你是谁",
        "你是什么",
        "你叫什么",
        "介绍一下你自己",
        "介绍你自己",
        "你能做什么",
        "你的功能",
    )

    return any(
        phrase in normalized
        for phrase in identity_phrases
    )


def _build_concise_text_prompt(
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
        "请直接回答下面的用户问题。"
        "除非用户明确询问，否则不要介绍你的身份、"
        "运行平台或功能。"
        "不要因为问题与RK3588无关而拒绝回答。"
        "不要复述提示内容，"
        "不要解释分析过程，"
        "不要使用标题、列表或分点，"
        "只输出一到两句自然中文结论，"
        f"尽量控制在{answer_max_chars}个汉字以内。\\n"
        f"用户问题：{recognized_text}"
    )


'''

if "def _build_concise_text_prompt(" not in text:
    if helper_marker not in text:
        raise RuntimeError(
            "Cannot find helper insertion marker"
        )

    text = text.replace(
        helper_marker,
        helper_code + helper_marker,
        1,
    )

    print("[PATCH] prompt helper functions added")
else:
    print("[SKIP] prompt helper functions already exist")


# ---------------------------------------------------------
# 2. 稳健定位 concise 模式中的非视觉 else 分支
# ---------------------------------------------------------

start_marker = '        if args.answer_mode == "concise":'
end_marker = '        if request_max_new_tokens is None:'

start = text.find(start_marker)
end = text.find(end_marker, start)

if start < 0:
    raise RuntimeError(
        "Cannot find concise mode start marker"
    )

if end < 0:
    raise RuntimeError(
        "Cannot find concise mode end marker"
    )

segment = text[start:end]

visual_else_marker = "            else:\n"
else_position = segment.rfind(visual_else_marker)

if else_position < 0:
    raise RuntimeError(
        "Cannot find non-visual prompt else branch"
    )

branch_start = (
    else_position + len(visual_else_marker)
)

old_general_branch = segment[branch_start:]

print("----- old general prompt branch -----")
print(old_general_branch)

new_general_branch = '''                prompt_text = _build_concise_text_prompt(
                    recognized_text,
                    answer_max_chars,
                )

'''

new_segment = (
    segment[:branch_start]
    + new_general_branch
)

text = (
    text[:start]
    + new_segment
    + text[end:]
)

print("[PATCH] general concise prompt branch replaced")


# ---------------------------------------------------------
# 3. 删除过宽的单字拍照关键词“字”
# ---------------------------------------------------------

word_pattern = re.compile(
    r"(?m)^[ \\t]*-[ \\t]*字[ \\t]*\\n"
)

word_count = len(word_pattern.findall(config_text))

if word_count > 1:
    raise RuntimeError(
        f"Unexpected standalone keyword count: {word_count}"
    )

if word_count == 1:
    config_text = word_pattern.sub(
        "",
        config_text,
        count=1,
    )
    print("[PATCH] removed standalone photo keyword: 字")
else:
    print("[SKIP] standalone photo keyword 字 already absent")


source_path.write_text(
    text,
    encoding="utf-8",
)

config_path.write_text(
    config_text,
    encoding="utf-8",
)

print("[OK] files written")
PY

PATCH_RC=$?

set -e

echo
echo "patch_return_code: $PATCH_RC"

if [ "$PATCH_RC" -ne 0 ]; then
    restore_files

    echo "[RESULT] Experiment 10.3e-v2 PATCH_FAILED_AND_RESTORED"
    exit 1
fi

echo
echo "==================== 4. compile ===================="

set +e

.venv/bin/python -m py_compile \
    voice_assistant/controlled_session.py \
    voice_assistant/orchestrator.py \
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
    restore_files

    echo "[RESULT] Experiment 10.3e-v2 COMPILE_FAILED_AND_RESTORED"
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
    actual_identity = _is_identity_question(question)

    prompt = _build_concise_text_prompt(
        question,
        80,
    )

    print("=" * 60)
    print("question:", question)
    print("expected_identity:", expected_identity)
    print("actual_identity:", actual_identity)
    print("prompt:")
    print(prompt)

    if actual_identity != expected_identity:
        failed += 1

    if not expected_identity:
        if question not in prompt:
            print("[FAIL] general prompt lost user question")
            failed += 1

        if "说明你是运行在RK3588" in prompt:
            print("[FAIL] general prompt contains identity instruction")
            failed += 1

print()
print("failed_count:", failed)

if failed:
    raise SystemExit(1)

print("[OK] prompt split unit test passed")
PY

PROMPT_TEST_RC=$?

set -e

cat "$OUT_DIR/prompt_unit_test.txt"
echo "prompt_test_return_code: $PROMPT_TEST_RC"

if [ "$PROMPT_TEST_RC" -ne 0 ]; then
    restore_files

    echo "[RESULT] Experiment 10.3e-v2 PROMPT_TEST_FAILED_AND_RESTORED"
    exit 1
fi

echo
echo "==================== 6. intent keyword regression ===================="

set +e

.venv/bin/python - <<'PY' \
    > "$OUT_DIR/intent_test.txt" \
    2>&1

from voice_assistant.config import load_config
from voice_assistant.intent import IntentRouter

cfg = load_config("config/default.yaml")
router = IntentRouter.from_config(cfg)

keywords = cfg["intent"]["photo_keywords"]

print("'字' in photo_keywords:", "字" in keywords)

cases = (
    ("你是谁", False),
    ("一加一等于几", False),
    ("这几个字是什么意思", False),
    ("拍照看一下画面", True),
    ("看一下镜头", True),
)

failed = 0

for text, expected in cases:
    actual = router.analyze(text).need_photo
    ok = actual == expected

    print(
        f"text={text!r}, "
        f"expected={expected}, "
        f"actual={actual}, "
        f"ok={ok}"
    )

    if not ok:
        failed += 1

if "字" in keywords:
    failed += 1

print("failed_count:", failed)

if failed:
    raise SystemExit(1)

print("[OK] photo intent regression test passed")
PY

INTENT_TEST_RC=$?

set -e

cat "$OUT_DIR/intent_test.txt"
echo "intent_test_return_code: $INTENT_TEST_RC"

if [ "$INTENT_TEST_RC" -ne 0 ]; then
    restore_files

    echo "[RESULT] Experiment 10.3e-v2 INTENT_TEST_FAILED_AND_RESTORED"
    exit 1
fi

echo
echo "==================== 7. diff ===================="

diff -u \
    "$OUT_DIR/before/controlled_session.py" \
    "$SOURCE" \
    > "$OUT_DIR/controlled_session.diff" || true

diff -u \
    "$OUT_DIR/before/default.yaml" \
    "$CONFIG" \
    > "$OUT_DIR/default_yaml.diff" || true

cat "$OUT_DIR/controlled_session.diff"
cat "$OUT_DIR/default_yaml.diff"

echo
echo "==================== 8. summary ===================="

{
    echo "out_dir                : $OUT_DIR"
    echo "patch_return_code      : $PATCH_RC"
    echo "compile_return_code    : $COMPILE_RC"
    echo "prompt_test_return_code: $PROMPT_TEST_RC"
    echo "intent_test_return_code: $INTENT_TEST_RC"
    echo "helper_definition_count: $(grep -c 'def _build_concise_text_prompt' "$SOURCE" || true)"
    echo "helper_call_count      : $(grep -c 'prompt_text = _build_concise_text_prompt' "$SOURCE" || true)"
    echo "word_keyword_remaining : $(grep -Ec '^[[:space:]]*-[[:space:]]*字[[:space:]]*$' "$CONFIG" || true)"
} | tee "$OUT_DIR/summary.txt"

echo

if [ "$PATCH_RC" -eq 0 ] \
  && [ "$COMPILE_RC" -eq 0 ] \
  && [ "$PROMPT_TEST_RC" -eq 0 ] \
  && [ "$INTENT_TEST_RC" -eq 0 ]; then

    echo "[RESULT] Experiment 10.3e-v2 PATCH PASSED."
    echo "[NEXT] Rerun two-case text semantic validation."
else
    echo "[RESULT] Experiment 10.3e-v2 FAILED_OR_NEEDS_CHECK."
    exit 1
fi
