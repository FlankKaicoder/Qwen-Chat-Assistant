#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="/home/cat/ai/qwen3vl2b"
cd "$PROJECT_DIR"

OUT_DIR="${1:-output/exp10_3a_decouple_intent_and_prompt_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT_DIR/before/voice_assistant"

ORCHESTRATOR="voice_assistant/orchestrator.py"
CONTROLLED="voice_assistant/controlled_session.py"

LOG="$OUT_DIR/run.log"
exec > >(tee "$LOG") 2>&1

restore_sources() {
    cp -a \
        "$OUT_DIR/before/voice_assistant/orchestrator.py" \
        "$ORCHESTRATOR"

    cp -a \
        "$OUT_DIR/before/voice_assistant/controlled_session.py" \
        "$CONTROLLED"
}

echo "============================================================"
echo " Experiment 10.3a: Decouple Intent Routing and Qwen Prompt"
echo "============================================================"
echo "time    : $(date '+%Y-%m-%d %H:%M:%S')"
echo "out_dir : $OUT_DIR"
echo

echo "==================== 1. backup ===================="

cp -a \
    "$ORCHESTRATOR" \
    "$OUT_DIR/before/voice_assistant/orchestrator.py"

cp -a \
    "$CONTROLLED" \
    "$OUT_DIR/before/voice_assistant/controlled_session.py"

echo "[OK] source backups saved"
echo

echo "==================== 2. inspect current false trigger ===================="

.venv/bin/python - <<'PY' \
    | tee "$OUT_DIR/false_trigger_before.txt"

from voice_assistant.config import load_config
from voice_assistant.intent import IntentRouter

cfg = load_config("config/default.yaml")
router = IntentRouter.from_config(cfg)

recognized_text = "你是谁"

rewritten_prompt = (
    "你是端侧语音助手。"
    "必须只输出最终答案，"
    "不要解释分析过程，"
    "不要使用标题、列表或分点。"
    "请用一到两句中文直接回答，"
    "尽量控制在80个汉字以内。\n"
    f"用户问题：{recognized_text}"
)

matched = [
    keyword
    for keyword in cfg["intent"]["photo_keywords"]
    if keyword in rewritten_prompt
]

print("recognized_text:", recognized_text)
print(
    "original_need_photo:",
    router.analyze(recognized_text).need_photo,
)
print(
    "rewritten_need_photo:",
    router.analyze(rewritten_prompt).need_photo,
)
print("matched_keywords:", matched)
print()
print("rewritten_prompt:")
print(rewritten_prompt)
PY

echo

echo "==================== 3. patch source ===================="

set +e

.venv/bin/python - <<'PY'
from pathlib import Path


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


# =========================================================
# 1. Orchestrator
# =========================================================

path = Path("voice_assistant/orchestrator.py")
text = path.read_text(encoding="utf-8")

text = replace_once(
    text,
    '''        on_sentence=None,
        max_new_tokens=None,
    ) -> str:
        intent = self.intent.analyze(text)
        uses_photo = force_photo or intent.need_photo
        if uses_photo:
''',
    '''        on_sentence=None,
        max_new_tokens=None,
        need_photo_override=None,
    ) -> str:
        if need_photo_override is None:
            intent = self.intent.analyze(text)
            uses_photo = force_photo or intent.need_photo
            routed_qwen_text = intent.qwen_text
        else:
            uses_photo = (
                force_photo
                or bool(need_photo_override)
            )
            routed_qwen_text = text

        if uses_photo:
''',
    "ask_qwen routing override",
)

text = replace_once(
    text,
    '''        qwen_text = self._prepare_qwen_text(intent.qwen_text, uses_photo)
''',
    '''        qwen_text = self._prepare_qwen_text(
            routed_qwen_text,
            uses_photo,
        )
''',
    "ask_qwen routed prompt source",
)

text = replace_once(
    text,
    '''        play: bool = True,
        max_new_tokens=None,
    ) -> str:
        answer = self.ask_qwen(
            text,
            image_path=image_path,
            force_photo=force_photo,
            max_new_tokens=max_new_tokens,
        )
''',
    '''        play: bool = True,
        max_new_tokens=None,
        need_photo_override=None,
    ) -> str:
        answer = self.ask_qwen(
            text,
            image_path=image_path,
            force_photo=force_photo,
            max_new_tokens=max_new_tokens,
            need_photo_override=need_photo_override,
        )
''',
    "run_once_from_text routing override",
)

path.write_text(text, encoding="utf-8")


# =========================================================
# 2. Controlled session
# =========================================================

path = Path("voice_assistant/controlled_session.py")
text = path.read_text(encoding="utf-8")

text = replace_once(
    text,
    '''        summary["recognized_text"] = recognized_text
        summary["recognized_chars"] = len(recognized_text)
        summary["photo_intent_hint"] = int(
            _photo_intent_hint(recognized_text)
        )

        _write_text(recognized_text_path, recognized_text + "\\n")
''',
    '''        summary["recognized_text"] = recognized_text
        summary["recognized_chars"] = len(recognized_text)

        original_intent = assistant.intent.analyze(
            recognized_text
        )

        summary["photo_intent_hint"] = int(
            original_intent.need_photo
        )

        intent_debug = {
            "recognized_text": recognized_text,
            "need_photo": bool(original_intent.need_photo),
            "intent_qwen_text": original_intent.qwen_text,
            "heuristic_photo_hint": bool(
                _photo_intent_hint(recognized_text)
            ),
        }

        (out_dir / "intent_debug.json").write_text(
            json.dumps(
                intent_debug,
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )

        _write_text(recognized_text_path, recognized_text + "\\n")
''',
    "use official IntentRouter on original ASR text",
)

old_prompt = '''                prompt_text = (
                    "你是端侧语音助手。"
                    "必须只输出最终答案，"
                    "不要解释分析过程，"
                    "不要使用标题、列表或分点。"
                    "请用一到两句中文直接回答，"
                    f"尽量控制在{answer_max_chars}个汉字以内。\\n"
                    f"用户问题：{recognized_text}"
                )
'''

new_prompt = '''                prompt_text = (
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

text = replace_once(
    text,
    old_prompt,
    new_prompt,
    "improve concise text identity prompt",
)

text = replace_once(
    text,
    '''            max_new_tokens=request_max_new_tokens,
        )
''',
    '''            max_new_tokens=request_max_new_tokens,
            need_photo_override=bool(
                summary["photo_intent_hint"]
            ),
        )
''',
    "pass original routing decision to orchestrator",
)

path.write_text(text, encoding="utf-8")

print("[OK] all source files patched")
PY

PATCH_RC=$?

set -e

echo "patch_return_code: $PATCH_RC"

if [ "$PATCH_RC" -ne 0 ]; then
    restore_sources
    echo "[RESULT] Experiment 10.3a PATCH_FAILED_AND_RESTORED"
    exit 1
fi

echo

echo "==================== 4. compile ===================="

set +e

.venv/bin/python -m py_compile \
    voice_assistant/orchestrator.py \
    voice_assistant/controlled_session.py \
    voice_assistant/cli.py \
    voice_assistant/qwen_runner.py \
    > "$OUT_DIR/compile_stdout.txt" \
    2> "$OUT_DIR/compile_stderr.txt"

COMPILE_RC=$?

set -e

echo "compile_return_code: $COMPILE_RC"
cat "$OUT_DIR/compile_stdout.txt"
cat "$OUT_DIR/compile_stderr.txt"

if [ "$COMPILE_RC" -ne 0 ]; then
    restore_sources
    echo "[RESULT] Experiment 10.3a COMPILE_FAILED_AND_RESTORED"
    exit 1
fi

echo

echo "==================== 5. routing unit test ===================="

set +e

.venv/bin/python - <<'PY' \
    > "$OUT_DIR/routing_unit_test.txt" \
    2>&1

from pathlib import Path

import voice_assistant.orchestrator as orchestrator_module
from voice_assistant.config import load_config
from voice_assistant.orchestrator import VoiceAssistant


cfg = load_config("config/default.yaml")
assistant = VoiceAssistant(cfg)

captured = {
    "capture_count": 0,
    "runner_calls": [],
}


def fake_capture_photo():
    captured["capture_count"] += 1
    return Path("/tmp/fake_camera.jpg")


class DummyRunner:
    def __init__(self, config):
        self.config = config

    def ask(
        self,
        image_path,
        text,
        max_new_tokens=None,
    ):
        captured["runner_calls"].append(
            {
                "image_path": str(image_path),
                "text": text,
                "max_new_tokens": max_new_tokens,
            }
        )
        return "测试回答"


original_runner = orchestrator_module.QwenRunner
original_capture = assistant.capture_photo

orchestrator_module.QwenRunner = DummyRunner
assistant.capture_photo = fake_capture_photo

try:
    text_prompt = (
        "你是运行在RK3588设备上的本地中文语音助手，"
        "能够进行普通问答和摄像头画面描述。"
        "用户问题：你是谁"
    )

    text_answer = assistant.run_once_from_text(
        text_prompt,
        speak=False,
        play=False,
        max_new_tokens=128,
        need_photo_override=False,
    )

    print("text_answer:", text_answer)
    print(
        "capture_count_after_text:",
        captured["capture_count"],
    )

    if captured["capture_count"] != 0:
        raise SystemExit(
            "text override incorrectly triggered camera"
        )

    visual_prompt = (
        "请根据当前摄像头拍摄的图片描述画面。"
    )

    visual_answer = assistant.run_once_from_text(
        visual_prompt,
        speak=False,
        play=False,
        max_new_tokens=128,
        need_photo_override=True,
    )

    print("visual_answer:", visual_answer)
    print(
        "capture_count_after_visual:",
        captured["capture_count"],
    )

    if captured["capture_count"] != 1:
        raise SystemExit(
            "visual override did not trigger exactly one capture"
        )

    print("runner_calls:", captured["runner_calls"])
    print("[OK] intent routing and Qwen prompt are decoupled")
finally:
    orchestrator_module.QwenRunner = original_runner
    assistant.capture_photo = original_capture
PY

UNIT_RC=$?

set -e

cat "$OUT_DIR/routing_unit_test.txt"
echo "routing_unit_test_return_code: $UNIT_RC"

if [ "$UNIT_RC" -ne 0 ]; then
    restore_sources
    echo "[RESULT] Experiment 10.3a UNIT_TEST_FAILED_AND_RESTORED"
    exit 1
fi

echo

echo "==================== 6. signatures ===================="

.venv/bin/python - <<'PY' \
    | tee "$OUT_DIR/signatures.txt"

import inspect

from voice_assistant.orchestrator import VoiceAssistant

print(
    "ask_qwen:",
    inspect.signature(VoiceAssistant.ask_qwen),
)

print(
    "run_once_from_text:",
    inspect.signature(VoiceAssistant.run_once_from_text),
)
PY

echo

echo "==================== 7. diffs ===================="

diff -u \
    "$OUT_DIR/before/voice_assistant/orchestrator.py" \
    "$ORCHESTRATOR" \
    > "$OUT_DIR/orchestrator.diff" || true

diff -u \
    "$OUT_DIR/before/voice_assistant/controlled_session.py" \
    "$CONTROLLED" \
    > "$OUT_DIR/controlled_session.diff" || true

cat "$OUT_DIR/orchestrator.diff"
cat "$OUT_DIR/controlled_session.diff"

echo

echo "==================== 8. summary ===================="

{
    echo "out_dir                     : $OUT_DIR"
    echo "patch_return_code           : $PATCH_RC"
    echo "compile_return_code         : $COMPILE_RC"
    echo "routing_unit_test_return_code: $UNIT_RC"
    echo "override_definition_count   : $(grep -c 'need_photo_override' "$ORCHESTRATOR" || true)"
    echo "controlled_override_count   : $(grep -c 'need_photo_override=bool' "$CONTROLLED" || true)"
} | tee "$OUT_DIR/summary.txt"

echo

if [ "$PATCH_RC" -eq 0 ] \
  && [ "$COMPILE_RC" -eq 0 ] \
  && [ "$UNIT_RC" -eq 0 ] \
  && grep -q \
       "intent routing and Qwen prompt are decoupled" \
       "$OUT_DIR/routing_unit_test.txt"; then

    echo "[RESULT] Experiment 10.3a PATCH PASSED."
    echo "[NEXT] Run direct concise text QA without camera or TTS."
else
    echo "[RESULT] Experiment 10.3a FAILED_OR_NEEDS_CHECK."
    exit 1
fi
