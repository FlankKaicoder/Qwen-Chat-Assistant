#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="/home/cat/ai/qwen3vl2b"
cd "$PROJECT_DIR"

OUT_DIR="${1:-output/exp10_2d_add_per_request_token_limit_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT_DIR"

FILES=(
    "voice_assistant/qwen_runner.py"
    "voice_assistant/orchestrator.py"
    "voice_assistant/controlled_session.py"
    "voice_assistant/cli.py"
)

LOG="$OUT_DIR/run.log"
exec > >(tee "$LOG") 2>&1

restore_sources() {
    echo "[RESTORE] restoring source files"

    for file in "${FILES[@]}"; do
        cp -a "$OUT_DIR/before/$file" "$file"
    done
}

echo "============================================================"
echo " Experiment 10.2d: Per-request Qwen token limit"
echo "============================================================"
echo "time    : $(date '+%Y-%m-%d %H:%M:%S')"
echo "out_dir : $OUT_DIR"
echo

echo "==================== 1. backup ===================="

for file in "${FILES[@]}"; do
    mkdir -p "$OUT_DIR/before/$(dirname "$file")"
    cp -a "$file" "$OUT_DIR/before/$file"
    echo "[OK] $file"
done

echo

echo "==================== 2. patch source ===================="

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
            f"{label}: expected exactly one match, found {count}"
        )

    print(f"[PATCH] {label}")
    return text.replace(old, new, 1)


# =========================================================
# 1. QwenRunner
# =========================================================

path = Path("voice_assistant/qwen_runner.py")
text = path.read_text(encoding="utf-8")

text = replace_once(
    text,
    '''    def ask(self, image_path: str | Path, text: str) -> str:
        child = self._spawn(image_path)
''',
    '''    def ask(
        self,
        image_path: str | Path,
        text: str,
        max_new_tokens=None,
    ) -> str:
        child = self._spawn(
            image_path,
            max_new_tokens=max_new_tokens,
        )
''',
    "QwenRunner.ask request token argument",
)

text = replace_once(
    text,
    '''    def ask_stream(self, image_path: str | Path, text: str, on_sentence: Callable[[str], None]) -> str:
        child = self._spawn(image_path)
''',
    '''    def ask_stream(
        self,
        image_path: str | Path,
        text: str,
        on_sentence: Callable[[str], None],
        max_new_tokens=None,
    ) -> str:
        child = self._spawn(
            image_path,
            max_new_tokens=max_new_tokens,
        )
''',
    "QwenRunner.ask_stream request token argument",
)

text = replace_once(
    text,
    '''    def _spawn(self, image_path: str | Path) -> pexpect.spawn:
        env = os.environ.copy()
''',
    '''    def _spawn(
        self,
        image_path: str | Path,
        max_new_tokens=None,
    ) -> pexpect.spawn:
        env = os.environ.copy()
''',
    "QwenRunner._spawn request token argument",
)

text = replace_once(
    text,
    '''        env.setdefault("RKLLM_LOG_LEVEL", "1")

        args = [
''',
    '''        env.setdefault("RKLLM_LOG_LEVEL", "1")

        if max_new_tokens is None:
            effective_max_new_tokens = int(
                self.qwen["max_new_tokens"]
            )
        else:
            effective_max_new_tokens = int(max_new_tokens)

        if effective_max_new_tokens <= 0:
            raise ValueError(
                "max_new_tokens must be greater than zero"
            )

        args = [
''',
    "QwenRunner effective token calculation",
)

text = replace_once(
    text,
    '''            str(self.qwen["max_new_tokens"]),
''',
    '''            str(effective_max_new_tokens),
''',
    "QwenRunner demo argument override",
)

path.write_text(text, encoding="utf-8")


# =========================================================
# 2. Orchestrator
# =========================================================

path = Path("voice_assistant/orchestrator.py")
text = path.read_text(encoding="utf-8")

text = replace_once(
    text,
    '''        force_photo: bool = False,
        on_sentence=None,
    ) -> str:
''',
    '''        force_photo: bool = False,
        on_sentence=None,
        max_new_tokens=None,
    ) -> str:
''',
    "VoiceAssistant.ask_qwen token argument",
)

text = replace_once(
    text,
    '''            return runner.ask_stream(image, qwen_text, on_sentence=on_sentence)
        return runner.ask(image, qwen_text)
''',
    '''            return runner.ask_stream(
                image,
                qwen_text,
                on_sentence=on_sentence,
                max_new_tokens=max_new_tokens,
            )

        return runner.ask(
            image,
            qwen_text,
            max_new_tokens=max_new_tokens,
        )
''',
    "VoiceAssistant.ask_qwen pass token argument",
)

text = replace_once(
    text,
    '''        force_photo: bool = False,
        speak: bool = True,
        play: bool = True,
    ) -> str:
        answer = self.ask_qwen(text, image_path=image_path, force_photo=force_photo)
''',
    '''        force_photo: bool = False,
        speak: bool = True,
        play: bool = True,
        max_new_tokens=None,
    ) -> str:
        answer = self.ask_qwen(
            text,
            image_path=image_path,
            force_photo=force_photo,
            max_new_tokens=max_new_tokens,
        )
''',
    "VoiceAssistant.run_once_from_text token argument",
)

path.write_text(text, encoding="utf-8")


# =========================================================
# 3. CLI
# =========================================================

path = Path("voice_assistant/cli.py")
text = path.read_text(encoding="utf-8")

text = replace_once(
    text,
    '''    p.add_argument(
        "--answer-max-chars",
        type=int,
        default=80,
        help="Suggested maximum Chinese characters in concise mode",
    )

    sub.add_parser("cleanup", help="Clean temporary files")
''',
    '''    p.add_argument(
        "--answer-max-chars",
        type=int,
        default=80,
        help="Suggested maximum Chinese characters in concise mode",
    )
    p.add_argument(
        "--concise-max-new-tokens",
        type=int,
        default=128,
        help="Qwen generation token limit used by concise mode",
    )

    sub.add_parser("cleanup", help="Clean temporary files")
''',
    "listen-controlled concise token CLI argument",
)

path.write_text(text, encoding="utf-8")


# =========================================================
# 4. Controlled session
# =========================================================

path = Path("voice_assistant/controlled_session.py")
text = path.read_text(encoding="utf-8")

text = replace_once(
    text,
    '''        "qwen_prompt_chars",
        "command_wav",
''',
    '''        "qwen_prompt_chars",
        "qwen_max_new_tokens",
        "command_wav",
''',
    "summary ordered token field",
)

text = replace_once(
    text,
    '''        "qwen_prompt_chars": 0,
        "command_wav": str(out_dir / "command.wav"),
''',
    '''        "qwen_prompt_chars": 0,
        "qwen_max_new_tokens": int(
            assistant.config["qwen"]["max_new_tokens"]
        ),
        "command_wav": str(out_dir / "command.wav"),
''',
    "summary initial token field",
)

text = replace_once(
    text,
    '''        prompt_text = recognized_text

        if args.answer_mode == "concise":
            answer_max_chars = max(20, int(args.answer_max_chars))
            prompt_text = (
                f"{recognized_text}\\n"
                "请直接回答用户问题，最多两句话，"
                "不要分点，不要展开分析，"
                f"尽量控制在{answer_max_chars}个汉字以内。"
            )

        summary["qwen_prompt_chars"] = len(prompt_text)
''',
    '''        prompt_text = recognized_text
        request_max_new_tokens = None

        if args.answer_mode == "concise":
            answer_max_chars = max(
                20,
                int(args.answer_max_chars),
            )
            request_max_new_tokens = max(
                32,
                int(args.concise_max_new_tokens),
            )

            prompt_text = (
                "你是端侧语音助手。"
                "必须只输出最终答案，"
                "不要解释分析过程，"
                "不要使用标题、列表或分点。"
                "请用一到两句中文直接回答，"
                f"尽量控制在{answer_max_chars}个汉字以内。\\n"
                f"用户问题：{recognized_text}"
            )

        if request_max_new_tokens is None:
            effective_max_new_tokens = int(
                assistant.config["qwen"]["max_new_tokens"]
            )
        else:
            effective_max_new_tokens = int(
                request_max_new_tokens
            )

        summary["qwen_max_new_tokens"] = (
            effective_max_new_tokens
        )
        summary["qwen_prompt_chars"] = len(prompt_text)
''',
    "controlled concise prompt and token budget",
)

text = replace_once(
    text,
    '''            "QWEN_PIPELINE_START",
            f"answer_mode={args.answer_mode}",
''',
    '''            "QWEN_PIPELINE_START",
            (
                f"answer_mode={args.answer_mode}, "
                f"max_new_tokens={effective_max_new_tokens}"
            ),
''',
    "Qwen pipeline state token logging",
)

text = replace_once(
    text,
    '''        answer = assistant.run_once_from_text(
            prompt_text,
            speak=False,
            play=False,
        )
''',
    '''        answer = assistant.run_once_from_text(
            prompt_text,
            speak=False,
            play=False,
            max_new_tokens=request_max_new_tokens,
        )
''',
    "controlled request token pass-through",
)

path.write_text(text, encoding="utf-8")

print("[OK] all source files patched")
PY

patch_return_code=$?

set -e

echo
echo "patch_return_code: $patch_return_code"
echo

if [ "$patch_return_code" -ne 0 ]; then
    restore_sources
    echo "[RESULT] Experiment 10.2d PATCH_FAILED_AND_RESTORED"
    exit 1
fi

echo "==================== 3. compile ===================="

set +e

.venv/bin/python -m py_compile \
    voice_assistant.py \
    voice_assistant/qwen_runner.py \
    voice_assistant/orchestrator.py \
    voice_assistant/controlled_session.py \
    voice_assistant/cli.py \
    > "$OUT_DIR/compile_stdout.txt" \
    2> "$OUT_DIR/compile_stderr.txt"

compile_return_code=$?

set -e

echo "compile_return_code: $compile_return_code"
cat "$OUT_DIR/compile_stdout.txt"
cat "$OUT_DIR/compile_stderr.txt"
echo

if [ "$compile_return_code" -ne 0 ]; then
    restore_sources
    echo "[RESULT] Experiment 10.2d COMPILE_FAILED_AND_RESTORED"
    exit 1
fi

echo "==================== 4. signature check ===================="

.venv/bin/python - <<'PY' \
    > "$OUT_DIR/signature_check.txt" \
    2>&1

import inspect

from voice_assistant.qwen_runner import QwenRunner
from voice_assistant.orchestrator import VoiceAssistant

print("QwenRunner.ask:")
print(inspect.signature(QwenRunner.ask))

print("QwenRunner.ask_stream:")
print(inspect.signature(QwenRunner.ask_stream))

print("QwenRunner._spawn:")
print(inspect.signature(QwenRunner._spawn))

print("VoiceAssistant.ask_qwen:")
print(inspect.signature(VoiceAssistant.ask_qwen))

print("VoiceAssistant.run_once_from_text:")
print(inspect.signature(VoiceAssistant.run_once_from_text))
PY

signature_return_code=$?

cat "$OUT_DIR/signature_check.txt"
echo "signature_return_code: $signature_return_code"
echo

echo "==================== 5. spawn argument unit test ===================="

set +e

.venv/bin/python - <<'PY' \
    > "$OUT_DIR/spawn_argument_test.txt" \
    2>&1

from voice_assistant.config import load_config
import voice_assistant.qwen_runner as module
from voice_assistant.qwen_runner import QwenRunner

captured = {}


class DummyChild:
    pass


def fake_spawn(command, args, **kwargs):
    captured["command"] = command
    captured["args"] = list(args)
    captured["kwargs"] = kwargs
    return DummyChild()


original_spawn = module.pexpect.spawn
module.pexpect.spawn = fake_spawn

try:
    cfg = load_config("config/default.yaml")
    runner = QwenRunner(cfg)

    runner._spawn(
        cfg["paths"]["placeholder_image"],
        max_new_tokens=128,
    )
finally:
    module.pexpect.spawn = original_spawn


print("command:", captured["command"])
print("argv:", captured["args"])

actual = captured["args"][3]
print("max_new_tokens_argument:", actual)

if actual != "128":
    raise SystemExit(
        f"expected token argument 128, got {actual}"
    )

print("[OK] per-request max_new_tokens reached demo argv")
PY

spawn_test_return_code=$?

set -e

cat "$OUT_DIR/spawn_argument_test.txt"
echo "spawn_test_return_code: $spawn_test_return_code"
echo

if [ "$spawn_test_return_code" -ne 0 ]; then
    restore_sources
    echo "[RESULT] Experiment 10.2d UNIT_TEST_FAILED_AND_RESTORED"
    exit 1
fi

echo "==================== 6. CLI help ===================="

.venv/bin/python voice_assistant.py listen-controlled --help \
    > "$OUT_DIR/controlled_help.txt" \
    2> "$OUT_DIR/controlled_help_stderr.txt"

help_return_code=$?

echo "help_return_code: $help_return_code"
cat "$OUT_DIR/controlled_help.txt"
cat "$OUT_DIR/controlled_help_stderr.txt"
echo

echo "==================== 7. diffs ===================="

for file in "${FILES[@]}"; do
    safe_name=$(echo "$file" | tr '/' '_')

    diff -u \
        "$OUT_DIR/before/$file" \
        "$file" \
        > "$OUT_DIR/${safe_name}.diff" || true

    echo "----- $file -----"
    cat "$OUT_DIR/${safe_name}.diff"
    echo
done

echo "==================== 8. summary ===================="

{
    echo "out_dir                  : $OUT_DIR"
    echo "patch_return_code        : $patch_return_code"
    echo "compile_return_code      : $compile_return_code"
    echo "signature_return_code    : $signature_return_code"
    echo "spawn_test_return_code   : $spawn_test_return_code"
    echo "help_return_code         : $help_return_code"
    echo "cli_token_argument_count : $(grep -c -- '--concise-max-new-tokens' voice_assistant/cli.py || true)"
    echo "runner_override_count    : $(grep -c 'effective_max_new_tokens' voice_assistant/qwen_runner.py || true)"
    echo "controlled_pass_count    : $(grep -c 'max_new_tokens=request_max_new_tokens' voice_assistant/controlled_session.py || true)"
} | tee "$OUT_DIR/summary.txt"

echo

if [ "$patch_return_code" -eq 0 ] \
  && [ "$compile_return_code" -eq 0 ] \
  && [ "$signature_return_code" -eq 0 ] \
  && [ "$spawn_test_return_code" -eq 0 ] \
  && [ "$help_return_code" -eq 0 ] \
  && grep -q -- "--concise-max-new-tokens" \
       "$OUT_DIR/controlled_help.txt"; then

    echo "[RESULT] Experiment 10.2d PATCH PASSED."
    echo "[NEXT] Run isolated concise Qwen test without TTS."
else
    echo "[RESULT] Experiment 10.2d PATCH FAILED_OR_NEEDS_CHECK."
    exit 1
fi
