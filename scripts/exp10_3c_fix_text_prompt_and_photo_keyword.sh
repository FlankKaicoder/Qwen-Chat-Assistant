#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="/home/cat/ai/qwen3vl2b"
cd "$PROJECT_DIR"

OUT_DIR="${1:-output/exp10_3c_fix_text_prompt_and_photo_keyword_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT_DIR/before"

CONFIG_FILE="config/default.yaml"
SESSION_FILE="voice_assistant/controlled_session.py"
LOG="$OUT_DIR/run.log"

exec > >(tee "$LOG") 2>&1

restore_files() {
    cp -a "$OUT_DIR/before/default.yaml" "$CONFIG_FILE"
    cp -a "$OUT_DIR/before/controlled_session.py" "$SESSION_FILE"
}

echo "============================================================"
echo " Experiment 10.3c: Fix text prompt and photo keyword"
echo "============================================================"
echo "time    : $(date '+%Y-%m-%d %H:%M:%S')"
echo "out_dir : $OUT_DIR"
echo

echo "==================== 1. backup ===================="

cp -a "$CONFIG_FILE" "$OUT_DIR/before/default.yaml"
cp -a "$SESSION_FILE" "$OUT_DIR/before/controlled_session.py"

echo "[OK] backups saved"
echo

echo "==================== 2. patch ===================="

set +e

.venv/bin/python - <<'PY'
from pathlib import Path
import re


def replace_once(
    text: str,
    old: str,
    new: str,
    label: str,
) -> str:
    count = text.count(old)

    if count != 1:
        raise RuntimeError(
            f"{label}: expected one match, found {count}"
        )

    print(f"[PATCH] {label}")
    return text.replace(old, new, 1)


# ---------------------------------------------------------
# 1. 删除 photo_keywords 中过宽的“字”
# ---------------------------------------------------------

config_path = Path("config/default.yaml")
config_text = config_path.read_text(encoding="utf-8")

pattern = re.compile(r"(?m)^[ \t]*-[ \t]*字[ \t]*\n")
matches = pattern.findall(config_text)

if len(matches) != 1:
    raise RuntimeError(
        "Expected exactly one standalone photo keyword '字', "
        f"found {len(matches)}"
    )

config_text = pattern.sub("", config_text, count=1)
config_path.write_text(config_text, encoding="utf-8")

print("[PATCH] removed standalone photo keyword: 字")


# ---------------------------------------------------------
# 2. 修正普通文本 concise prompt
# ---------------------------------------------------------

session_path = Path("voice_assistant/controlled_session.py")
session_text = session_path.read_text(encoding="utf-8")

old_prompt = '''                prompt_text = (
                    "你是运行在RK3588设备上的本地中文语音助手，"
                    "能够进行普通问答和摄像头画面描述。"
                    "请根据用户问题直接给出最终答案，"
                    "不要解释分析过程，"
                    "不要使用标题、列表或分点，"
                    "使用一到两句自然中文，"
                    f"尽量控制在{answer_max_chars}个汉字以内。\\n"
                    f"用户问题：{recognized_text}"
                )
'''

new_prompt = '''                prompt_text = (
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

session_text = replace_once(
    session_text,
    old_prompt,
    new_prompt,
    "replace restrictive text prompt",
)

session_path.write_text(
    session_text,
    encoding="utf-8",
)

print("[OK] source files updated")
PY

PATCH_RC=$?

set -e

echo "patch_return_code: $PATCH_RC"
echo

if [ "$PATCH_RC" -ne 0 ]; then
    restore_files
    echo "[RESULT] Experiment 10.3c PATCH_FAILED_AND_RESTORED"
    exit 1
fi

echo "==================== 3. compile ===================="

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
echo

if [ "$COMPILE_RC" -ne 0 ]; then
    restore_files
    echo "[RESULT] Experiment 10.3c COMPILE_FAILED_AND_RESTORED"
    exit 1
fi

echo "==================== 4. intent regression test ===================="

set +e

.venv/bin/python - <<'PY' \
    > "$OUT_DIR/intent_regression_test.txt" \
    2>&1

from voice_assistant.config import load_config
from voice_assistant.intent import IntentRouter

cfg = load_config("config/default.yaml")
router = IntentRouter.from_config(cfg)

keywords = cfg["intent"]["photo_keywords"]

print("photo_keyword_count:", len(keywords))
print("single_character_keywords:")
for keyword in keywords:
    if len(keyword) == 1:
        print(repr(keyword))

print()
print("'字' in keywords:", "字" in keywords)

cases = [
    ("你是谁", False),
    ("这几个字是什么意思", False),
    ("帮我写几个汉字", False),
    ("拍照看一下画面", True),
    ("看一下镜头", True),
]

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

INTENT_RC=$?

set -e

cat "$OUT_DIR/intent_regression_test.txt"
echo "intent_test_return_code: $INTENT_RC"
echo

if [ "$INTENT_RC" -ne 0 ]; then
    restore_files
    echo "[RESULT] Experiment 10.3c INTENT_TEST_FAILED_AND_RESTORED"
    exit 1
fi

echo "==================== 5. diffs ===================="

diff -u \
    "$OUT_DIR/before/default.yaml" \
    "$CONFIG_FILE" \
    > "$OUT_DIR/default_yaml.diff" || true

diff -u \
    "$OUT_DIR/before/controlled_session.py" \
    "$SESSION_FILE" \
    > "$OUT_DIR/controlled_session.diff" || true

cat "$OUT_DIR/default_yaml.diff"
cat "$OUT_DIR/controlled_session.diff"
echo

echo "==================== 6. summary ===================="

{
    echo "out_dir                  : $OUT_DIR"
    echo "patch_return_code        : $PATCH_RC"
    echo "compile_return_code      : $COMPILE_RC"
    echo "intent_test_return_code  : $INTENT_RC"
    echo "standalone_word_remaining: $(grep -Ec '^[[:space:]]*-[[:space:]]*字[[:space:]]*$' "$CONFIG_FILE" || true)"
} | tee "$OUT_DIR/summary.txt"

echo

if [ "$PATCH_RC" -eq 0 ] \
  && [ "$COMPILE_RC" -eq 0 ] \
  && [ "$INTENT_RC" -eq 0 ]; then

    echo "[RESULT] Experiment 10.3c PATCH PASSED."
    echo "[NEXT] Run two-case direct text semantic validation."
else
    echo "[RESULT] Experiment 10.3c FAILED_OR_NEEDS_CHECK."
    exit 1
fi
