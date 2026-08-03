#!/usr/bin/env bash

set -u

PROJECT_DIR="/home/cat/ai/qwen3vl2b"
cd "$PROJECT_DIR" || exit 1

OUT_DIR="${1:-output/exp10_3e_v3_yaml_safe_prompt_split_$(date +%Y%m%d_%H%M%S)}"

SOURCE_FILE="voice_assistant/controlled_session.py"
CONFIG_FILE="config/default.yaml"

mkdir -p "$OUT_DIR/before"

LOG="$OUT_DIR/run.log"
exec > >(tee "$LOG") 2>&1

restore_files() {
    echo "[RESTORE] restoring source and configuration"

    cp -a \
        "$OUT_DIR/before/controlled_session.py" \
        "$SOURCE_FILE"

    cp -a \
        "$OUT_DIR/before/default.yaml" \
        "$CONFIG_FILE"
}

echo "============================================================"
echo " Experiment 10.3e-v3"
echo " YAML-safe keyword cleanup and prompt split"
echo "============================================================"
echo "time    : $(date '+%Y-%m-%d %H:%M:%S')"
echo "out_dir : $OUT_DIR"
echo

echo "==================== 1. backup ===================="

cp -a \
    "$SOURCE_FILE" \
    "$OUT_DIR/before/controlled_session.py"

cp -a \
    "$CONFIG_FILE" \
    "$OUT_DIR/before/default.yaml"

echo "[OK] backups created"
echo

echo "==================== 2. inspect original keywords ===================="

set +e

.venv/bin/python - <<'PY' \
    > "$OUT_DIR/photo_keywords_before.txt" \
    2>&1

from pathlib import Path
import yaml

path = Path("config/default.yaml")
data = yaml.safe_load(
    path.read_text(encoding="utf-8")
)

keywords = data["intent"]["photo_keywords"]

print("photo_keywords_type:", type(keywords).__name__)
print("photo_keyword_count:", len(keywords))
print("'字' in photo_keywords:", "字" in keywords)
print()

for index, keyword in enumerate(keywords):
    print(
        f"{index:02d}: "
        f"value={keyword!r}, "
        f"length={len(str(keyword))}"
    )
PY

INSPECT_RC=$?

set -e

cat "$OUT_DIR/photo_keywords_before.txt"
echo "inspect_return_code: $INSPECT_RC"

if [ "$INSPECT_RC" -ne 0 ]; then
    echo "[RESULT] Experiment 10.3e-v3 CONFIG_INSPECTION_FAILED."
    exit 1
fi

echo
echo "==================== 3. patch source and YAML ===================="

set +e

.venv/bin/python - <<'PY'
from pathlib import Path
import json
import re
import yaml


source_path = Path(
    "voice_assistant/controlled_session.py"
)

config_path = Path(
    "config/default.yaml"
)


# ============================================================
# Part A: controlled_session.py
# ============================================================

source_text = source_path.read_text(
    encoding="utf-8"
)

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

if "def _build_concise_text_prompt(" not in source_text:
    if helper_marker not in source_text:
        raise RuntimeError(
            "Cannot find helper insertion marker"
        )

    source_text = source_text.replace(
        helper_marker,
        helper_code + helper_marker,
        1,
    )

    print("[PATCH] added prompt builder functions")
else:
    print("[SKIP] prompt builder functions already exist")


concise_start_marker = (
    '        if args.answer_mode == "concise":'
)

concise_end_marker = (
    "        if request_max_new_tokens is None:"
)

concise_start = source_text.find(
    concise_start_marker
)

concise_end = source_text.find(
    concise_end_marker,
    concise_start,
)

if concise_start < 0:
    raise RuntimeError(
        "Cannot find concise answer-mode block"
    )

if concise_end < 0:
    raise RuntimeError(
        "Cannot find concise block end marker"
    )

concise_segment = source_text[
    concise_start:concise_end
]

helper_call = '''                prompt_text = _build_concise_text_prompt(
                    recognized_text,
                    answer_max_chars,
                )

'''

if (
    "prompt_text = _build_concise_text_prompt("
    not in concise_segment
):
    else_marker = "            else:\n"

    else_position = concise_segment.rfind(
        else_marker
    )

    if else_position < 0:
        raise RuntimeError(
            "Cannot locate non-visual concise else branch"
        )

    branch_start = (
        else_position + len(else_marker)
    )

    old_general_branch = concise_segment[
        branch_start:
    ]

    print("----- replacing old general branch -----")
    print(old_general_branch)

    new_concise_segment = (
        concise_segment[:branch_start]
        + helper_call
    )

    source_text = (
        source_text[:concise_start]
        + new_concise_segment
        + source_text[concise_end:]
    )

    print("[PATCH] replaced general concise prompt")
else:
    print("[SKIP] general concise prompt already uses helper")


# ============================================================
# Part B: config/default.yaml
# ============================================================

config_text = config_path.read_text(
    encoding="utf-8"
)

config_data = yaml.safe_load(
    config_text
)

try:
    original_keywords = config_data[
        "intent"
    ][
        "photo_keywords"
    ]
except Exception as exc:
    raise RuntimeError(
        "Cannot load intent.photo_keywords"
    ) from exc

if not isinstance(original_keywords, list):
    raise RuntimeError(
        "intent.photo_keywords is not a list"
    )

removed_keywords = [
    keyword
    for keyword in original_keywords
    if str(keyword).strip() == "字"
]

new_keywords = [
    keyword
    for keyword in original_keywords
    if str(keyword).strip() != "字"
]

print(
    "original_keyword_count:",
    len(original_keywords),
)

print(
    "removed_keyword_count:",
    len(removed_keywords),
)

print(
    "new_keyword_count:",
    len(new_keywords),
)

if len(removed_keywords) != 1:
    raise RuntimeError(
        "Expected exactly one photo keyword '字', "
        f"found {len(removed_keywords)}"
    )


# 找到 photo_keywords 的 YAML 行。
config_lines = config_text.splitlines(
    keepends=True
)

key_index = None
key_indent = None

key_pattern = re.compile(
    r"^([ \t]*)photo_keywords[ \t]*:"
)

for index, line in enumerate(config_lines):
    match = key_pattern.match(line)

    if match:
        if key_index is not None:
            raise RuntimeError(
                "Multiple photo_keywords keys found"
            )

        key_index = index
        key_indent = match.group(1)

if key_index is None or key_indent is None:
    raise RuntimeError(
        "Cannot find photo_keywords YAML key"
    )

key_indent_width = len(
    key_indent.expandtabs(4)
)

key_line = config_lines[key_index]
key_value_tail = key_line.split(":", 1)[1].strip()


# 找到旧列表块的结束位置。
if key_value_tail:
    # 例如 photo_keywords: ["拍照", "字"]
    block_end = key_index + 1
else:
    # 例如：
    # photo_keywords:
    #   - "拍照"
    #   - "字"
    block_end = key_index + 1

    while block_end < len(config_lines):
        current_line = config_lines[block_end]
        stripped = current_line.strip()

        if not stripped:
            block_end += 1
            continue

        if current_line.lstrip().startswith("#"):
            block_end += 1
            continue

        current_indent_width = len(
            current_line
            .removesuffix("\n")
            .removesuffix("\r")
        ) - len(
            current_line.lstrip(" \t")
        )

        if current_indent_width <= key_indent_width:
            break

        block_end += 1


# 用统一的块列表格式重写。
new_keyword_lines = [
    f"{key_indent}photo_keywords:\n"
]

for keyword in new_keywords:
    # JSON 双引号字符串也是合法 YAML。
    encoded = json.dumps(
        str(keyword),
        ensure_ascii=False,
    )

    new_keyword_lines.append(
        f"{key_indent}  - {encoded}\n"
    )

config_lines[
    key_index:block_end
] = new_keyword_lines

new_config_text = "".join(config_lines)


# 写文件前再次解析验证。
new_config_data = yaml.safe_load(
    new_config_text
)

verified_keywords = new_config_data[
    "intent"
][
    "photo_keywords"
]

if "字" in verified_keywords:
    raise RuntimeError(
        "Keyword '字' still exists after rewrite"
    )

if len(verified_keywords) != len(new_keywords):
    raise RuntimeError(
        "Keyword count changed unexpectedly"
    )


source_path.write_text(
    source_text,
    encoding="utf-8",
)

config_path.write_text(
    new_config_text,
    encoding="utf-8",
)

print("[PATCH] rewrote photo_keywords YAML block")
print("[OK] source and configuration written")
PY

PATCH_RC=$?

set -e

echo
echo "patch_return_code: $PATCH_RC"

if [ "$PATCH_RC" -ne 0 ]; then
    restore_files

    echo \
      "[RESULT] Experiment 10.3e-v3 PATCH_FAILED_AND_RESTORED."

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

    echo \
      "[RESULT] Experiment 10.3e-v3 COMPILE_FAILED_AND_RESTORED."

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

failed_count = 0

for question, expected_identity in cases:
    actual_identity = _is_identity_question(
        question
    )

    prompt = _build_concise_text_prompt(
        question,
        80,
    )

    print("=" * 60)
    print("question:", question)
    print(
        "expected_identity:",
        expected_identity,
    )
    print(
        "actual_identity:",
        actual_identity,
    )
    print("prompt:")
    print(prompt)

    if actual_identity != expected_identity:
        failed_count += 1

    if not expected_identity:
        if question not in prompt:
            print(
                "[FAIL] user question missing "
                "from general prompt"
            )

            failed_count += 1

        if "说明你是运行在RK3588" in prompt:
            print(
                "[FAIL] general prompt still "
                "contains identity instruction"
            )

            failed_count += 1

print()
print("failed_count:", failed_count)

if failed_count:
    raise SystemExit(1)

print("[OK] prompt split unit test passed")
PY

PROMPT_TEST_RC=$?

set -e

cat "$OUT_DIR/prompt_unit_test.txt"

echo \
  "prompt_test_return_code: $PROMPT_TEST_RC"

if [ "$PROMPT_TEST_RC" -ne 0 ]; then
    restore_files

    echo \
      "[RESULT] Experiment 10.3e-v3 PROMPT_TEST_FAILED_AND_RESTORED."

    exit 1
fi

echo
echo "==================== 6. intent regression ===================="

set +e

.venv/bin/python - <<'PY' \
    > "$OUT_DIR/intent_test.txt" \
    2>&1

from voice_assistant.config import load_config
from voice_assistant.intent import IntentRouter


cfg = load_config("config/default.yaml")
router = IntentRouter.from_config(cfg)

keywords = cfg["intent"]["photo_keywords"]

print(
    "photo_keyword_count:",
    len(keywords),
)

print(
    "'字' in photo_keywords:",
    "字" in keywords,
)

print("single_character_keywords:")

for keyword in keywords:
    if len(str(keyword)) == 1:
        print(repr(keyword))

cases = (
    ("你是谁", False),
    ("一加一等于几", False),
    ("这几个字是什么意思", False),
    ("帮我写几个汉字", False),
    ("拍照看一下画面", True),
    ("看一下镜头", True),
)

failed_count = 0

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
        failed_count += 1

if "字" in keywords:
    failed_count += 1

print(
    "failed_count:",
    failed_count,
)

if failed_count:
    raise SystemExit(1)

print(
    "[OK] photo intent regression test passed"
)
PY

INTENT_TEST_RC=$?

set -e

cat "$OUT_DIR/intent_test.txt"

echo \
  "intent_test_return_code: $INTENT_TEST_RC"

if [ "$INTENT_TEST_RC" -ne 0 ]; then
    restore_files

    echo \
      "[RESULT] Experiment 10.3e-v3 INTENT_TEST_FAILED_AND_RESTORED."

    exit 1
fi

echo
echo "==================== 7. inspect updated keywords ===================="

.venv/bin/python - <<'PY' \
    > "$OUT_DIR/photo_keywords_after.txt"

from pathlib import Path
import yaml

data = yaml.safe_load(
    Path("config/default.yaml").read_text(
        encoding="utf-8"
    )
)

keywords = data["intent"]["photo_keywords"]

print("photo_keyword_count:", len(keywords))
print("'字' in photo_keywords:", "字" in keywords)

for index, keyword in enumerate(keywords):
    print(
        f"{index:02d}: "
        f"value={keyword!r}, "
        f"length={len(str(keyword))}"
    )
PY

cat "$OUT_DIR/photo_keywords_after.txt"

echo
echo "==================== 8. diff ===================="

diff -u \
    "$OUT_DIR/before/controlled_session.py" \
    "$SOURCE_FILE" \
    > "$OUT_DIR/controlled_session.diff" || true

diff -u \
    "$OUT_DIR/before/default.yaml" \
    "$CONFIG_FILE" \
    > "$OUT_DIR/default_yaml.diff" || true

cat "$OUT_DIR/controlled_session.diff"
cat "$OUT_DIR/default_yaml.diff"

echo
echo "==================== 9. summary ===================="

HELPER_DEFINITION_COUNT=$(
    grep -c \
      "def _build_concise_text_prompt" \
      "$SOURCE_FILE" || true
)

HELPER_CALL_COUNT=$(
    grep -c \
      "prompt_text = _build_concise_text_prompt" \
      "$SOURCE_FILE" || true
)

WORD_REMAINING=$(
    .venv/bin/python - <<'PY'
from voice_assistant.config import load_config

cfg = load_config("config/default.yaml")

print(
    int(
        "字"
        in cfg["intent"]["photo_keywords"]
    )
)
PY
)

{
    echo "out_dir                 : $OUT_DIR"
    echo "inspect_return_code     : $INSPECT_RC"
    echo "patch_return_code       : $PATCH_RC"
    echo "compile_return_code     : $COMPILE_RC"
    echo "prompt_test_return_code : $PROMPT_TEST_RC"
    echo "intent_test_return_code : $INTENT_TEST_RC"
    echo "helper_definition_count : $HELPER_DEFINITION_COUNT"
    echo "helper_call_count       : $HELPER_CALL_COUNT"
    echo "word_keyword_remaining  : $WORD_REMAINING"
} | tee "$OUT_DIR/summary.txt"

echo

if [ "$PATCH_RC" -eq 0 ] \
  && [ "$COMPILE_RC" -eq 0 ] \
  && [ "$PROMPT_TEST_RC" -eq 0 ] \
  && [ "$INTENT_TEST_RC" -eq 0 ] \
  && [ "$WORD_REMAINING" -eq 0 ]; then

    echo \
      "[RESULT] Experiment 10.3e-v3 PATCH PASSED."

    echo \
      "[NEXT] Run real two-case semantic validation."
else
    echo \
      "[RESULT] Experiment 10.3e-v3 FAILED_OR_NEEDS_CHECK."

    exit 1
fi
