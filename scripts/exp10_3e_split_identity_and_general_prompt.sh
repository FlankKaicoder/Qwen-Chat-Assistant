#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="/home/cat/ai/qwen3vl2b"
cd "$PROJECT_DIR"

OUT_DIR="${1:-output/exp10_3e_split_identity_and_general_prompt_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT_DIR"

SOURCE="voice_assistant/controlled_session.py"

cp -a "$SOURCE" "$OUT_DIR/controlled_session.py.before"

echo "============================================================"
echo " Experiment 10.3e: Split identity and general prompt"
echo "============================================================"
echo "out_dir: $OUT_DIR"
echo

.venv/bin/python - <<'PY'
from pathlib import Path

path = Path("voice_assistant/controlled_session.py")
text = path.read_text(encoding="utf-8")

# 在 _format_optional_float 前增加可复用的文本 Prompt 构造函数。
marker = '''def _format_optional_float(value: Any) -> str:
'''

helper = '''def _is_identity_question(text: str) -> bool:
    normalized = "".join(text.strip().split())

    keywords = (
        "你是谁",
        "你是什么",
        "你叫什么",
        "介绍一下你自己",
        "介绍你自己",
        "你能做什么",
        "你的功能",
    )

    return any(keyword in normalized for keyword in keywords)


def _build_concise_text_prompt(
    recognized_text: str,
    answer_max_chars: int,
) -> str:
    if _is_identity_question(recognized_text):
        return (
            "请用一到两句中文直接回答用户的身份询问。"
            "说明你是运行在RK3588设备上的本地中文语音助手，"
            "可以进行普通问答和摄像头画面描述。"
            "不要声称你只能回答RK3588相关问题，"
            "不要使用标题、列表或分点，"
            f"尽量控制在{answer_max_chars}个汉字以内。"
        )

    return (
        "请直接回答下面的用户问题。"
        "除非用户明确询问，否则不要介绍你的身份、"
        "运行平台或功能。"
        "不要因为问题与RK3588无关而拒绝回答。"
        "不要解释分析过程，"
        "不要使用标题、列表或分点，"
        "只输出一到两句自然中文结论，"
        f"尽量控制在{answer_max_chars}个汉字以内。\\n"
        f"用户问题：{recognized_text}"
    )


'''

if "_build_concise_text_prompt" not in text:
    if marker not in text:
        raise RuntimeError(
            "Cannot find helper insertion point"
        )

    text = text.replace(marker, helper + marker, 1)
    print("[PATCH] added prompt builder helpers")
else:
    print("[SKIP] prompt helpers already exist")


old_prompt = '''                prompt_text = (
                    "你是一个本地中文语音助手，"
                    "运行平台是RK3588。"
                    "RK3588只是运行平台，"
                    "不限制你回答问题的范围。"
                    "你可以正常回答日常常识、计算和一般问题，"
                    "也可以在需要时描述摄像头画面。"
                    "如果用户询问你是谁，"
                    "请明确说明你是本地中文语音助手。"
                    "请直接给出最终答案，"
                    "不要解释分析过程，"
                    "不要使用标题、列表或分点，"
                    "使用一到两句自然中文，"
                    f"尽量控制在{answer_max_chars}个汉字以内。\\n"
                    f"用户问题：{recognized_text}"
                )
'''

new_prompt = '''                prompt_text = _build_concise_text_prompt(
                    recognized_text,
                    answer_max_chars,
                )
'''

if old_prompt in text:
    text = text.replace(old_prompt, new_prompt, 1)
    print("[PATCH] replaced common text prompt")
elif new_prompt in text:
    print("[SKIP] common text prompt already replaced")
else:
    raise RuntimeError(
        "Cannot find the current common text prompt block"
    )

path.write_text(text, encoding="utf-8")
print("[OK] source updated")
PY

PATCH_RC=$?

set +e

.venv/bin/python -m py_compile \
    voice_assistant/controlled_session.py \
    voice_assistant/orchestrator.py \
    voice_assistant/qwen_runner.py \
    > "$OUT_DIR/compile_stdout.txt" \
    2> "$OUT_DIR/compile_stderr.txt"

COMPILE_RC=$?

set -e

echo "patch_return_code  : $PATCH_RC"
echo "compile_return_code: $COMPILE_RC"

cat "$OUT_DIR/compile_stderr.txt"

.venv/bin/python - <<'PY' \
    > "$OUT_DIR/prompt_unit_test.txt"

from voice_assistant.controlled_session import (
    _build_concise_text_prompt,
    _is_identity_question,
)

cases = (
    "你是谁",
    "一加一等于几",
    "中国的首都是哪里",
)

for question一等于几",
    "中国的首都是哪里",
)

for question in cases:
    print("=" * 60)
    print("question:", question)
    print(
        "identity:",
        _is_identity_question(question),
    )
    print(
        "prompt:",
        _build_concise_text_prompt(question, 80),
    )
PY

cat "$OUT_DIR/prompt_unit_test.txt"

diff -u \
    "$OUT_DIR/controlled_session.py.before" \
    "$SOURCE" \
    > "$OUT_DIR/controlled_session.diff" || true

{
    echo "out_dir            : $OUT_DIR"
    echo "patch_return_code  : $PATCH_RC"
    echo "compile_return_code: $COMPILE_RC"
    echo "helper_count       : $(grep -c 'def _build_concise_text_prompt' "$SOURCE" || true)"
    echo "call_count         : $(grep -c 'prompt_text = _build_concise_text_prompt' "$SOURCE" || true)"
} | tee "$OUT_DIR/summary.txt"

if [ "$PATCH_RC" -eq 0 ] \
  && [ "$COMPILE_RC" -eq 0 ] \
  && grep -q \
       "prompt_text = _build_concise_text_prompt" \
       "$SOURCE"; then

    echo "[RESULT] Experiment 10.3e PATCH PASSED."
else
    echo "[RESULT] Experiment 10.3e PATCH FAILED."
    exit 1
fi
