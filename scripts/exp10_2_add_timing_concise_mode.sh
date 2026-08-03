#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="/home/cat/ai/qwen3vl2b"
cd "$PROJECT_DIR"

OUT_DIR="${1:-output/exp10_2_add_timing_concise_mode_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT_DIR"

CLI_FILE="voice_assistant/cli.py"
SESSION_FILE="voice_assistant/controlled_session.py"
LOG="$OUT_DIR/run.log"

exec > >(tee "$LOG") 2>&1

echo "============================================================"
echo " Experiment 10.2: Add Timing and Concise Answer Mode"
echo "============================================================"
echo "time    : $(date '+%Y-%m-%d %H:%M:%S')"
echo "out_dir : $OUT_DIR"
echo

echo "==================== 1. backup ===================="

cp -a "$CLI_FILE" "$OUT_DIR/cli.py.before"
cp -a "$SESSION_FILE" "$OUT_DIR/controlled_session.py.before"

echo "[OK] backups saved"
echo

echo "==================== 2. patch source ===================="

python3 - <<'PY'
from pathlib import Path

cli_path = Path("voice_assistant/cli.py")
session_path = Path("voice_assistant/controlled_session.py")

cli = cli_path.read_text(encoding="utf-8")
session = session_path.read_text(encoding="utf-8")


# ---------------------------------------------------------
# 1. CLI 参数
# ---------------------------------------------------------

if "--answer-mode" not in cli:
    old = '''    p.add_argument("--out-dir")
    p.add_argument("--no-speak", action="store_true")
    p.add_argument("--no-play", action="store_true")

    sub.add_parser("cleanup", help="Clean temporary files")
'''

    new = '''    p.add_argument("--out-dir")
    p.add_argument("--no-speak", action="store_true")
    p.add_argument("--no-play", action="store_true")
    p.add_argument(
        "--answer-mode",
        choices=["normal", "concise"],
        default="normal",
        help="Use normal or concise Qwen response prompt",
    )
    p.add_argument(
        "--answer-max-chars",
        type=int,
        default=80,
        help="Suggested maximum Chinese characters in concise mode",
    )

    sub.add_parser("cleanup", help="Clean temporary files")
'''

    if old not in cli:
        raise RuntimeError(
            "Cannot find listen-controlled argument insertion point"
        )

    cli = cli.replace(old, new, 1)
    print("[PATCH] added concise CLI arguments")
else:
    print("[SKIP] concise CLI arguments already exist")


# ---------------------------------------------------------
# 2. summary.txt 字段顺序
# ---------------------------------------------------------

if '"answer_mode",' not in session:
    old = '''        "record_seconds",
        "command_wav",
        "audio_duration_seconds",
'''

    new = '''        "record_seconds",
        "answer_mode",
        "answer_max_chars",
        "qwen_prompt_chars",
        "command_wav",
        "audio_duration_seconds",
'''

    if old not in session:
        raise RuntimeError("Cannot find ordered_keys insertion point")

    session = session.replace(old, new, 1)


if '"pipeline_elapsed_seconds",' not in session:
    old = '''        "answer_chars",
        "speak",
        "play",
        "elapsed_seconds",
'''

    new = '''        "answer_chars",
        "pipeline_elapsed_seconds",
        "tts_elapsed_seconds",
        "speak",
        "play",
        "elapsed_seconds",
'''

    if old not in session:
        raise RuntimeError("Cannot find timing key insertion point")

    session = session.replace(old, new, 1)


# ---------------------------------------------------------
# 3. 浮点数格式化字段
# ---------------------------------------------------------

old_float = '''            "max_volume_dbfs",
            "elapsed_seconds",
'''

new_float = '''            "max_volume_dbfs",
            "pipeline_elapsed_seconds",
            "tts_elapsed_seconds",
            "elapsed_seconds",
'''

if "pipeline_elapsed_seconds" not in session.split(
    "if key in {", 1
)[1].split("}:", 1)[0]:
    if old_float not in session:
        raise RuntimeError("Cannot find float field insertion point")

    session = session.replace(old_float, new_float, 1)


# ---------------------------------------------------------
# 4. summary 初始字段
# ---------------------------------------------------------

if '"answer_mode": args.answer_mode' not in session:
    old = '''        "record_seconds": int(args.seconds),
        "command_wav": str(out_dir / "command.wav"),
'''

    new = '''        "record_seconds": int(args.seconds),
        "answer_mode": str(args.answer_mode),
        "answer_max_chars": int(args.answer_max_chars),
        "qwen_prompt_chars": 0,
        "command_wav": str(out_dir / "command.wav"),
'''

    if old not in session:
        raise RuntimeError("Cannot find summary argument insertion point")

    session = session.replace(old, new, 1)


if '"pipeline_elapsed_seconds": None' not in session:
    old = '''        "answer_chars": 0,
        "speak": int(not args.no_speak),
'''

    new = '''        "answer_chars": 0,
        "pipeline_elapsed_seconds": None,
        "tts_elapsed_seconds": None,
        "speak": int(not args.no_speak),
'''

    if old not in session:
        raise RuntimeError("Cannot find summary timing insertion point")

    session = session.replace(old, new, 1)


# ---------------------------------------------------------
# 5. 拆分 Qwen pipeline 与 TTS
# ---------------------------------------------------------

old_run = '''        _state(
            out_dir,
            "INTENT_DISPATCH",
            f"photo_hint={summary['photo_intent_hint']}",
        )
        _state(out_dir, "QWEN_TTS")

        answer = assistant.run_once_from_text(
            recognized_text,
            speak=not args.no_speak,
            play=not args.no_play,
        )

        answer = str(answer or "").strip()
        summary["answer_chars"] = len(answer)
'''

new_run = '''        _state(
            out_dir,
            "INTENT_DISPATCH",
            f"photo_hint={summary['photo_intent_hint']}",
        )

        prompt_text = recognized_text

        if args.answer_mode == "concise":
            answer_max_chars = max(20, int(args.answer_max_chars))
            prompt_text = (
                f"{recognized_text}\\n"
                "请直接回答用户问题，最多两句话，"
                "不要分点，不要展开分析，"
                f"尽量控制在{answer_max_chars}个汉字以内。"
            )

        summary["qwen_prompt_chars"] = len(prompt_text)
        _write_text(out_dir / "qwen_prompt.txt", prompt_text + "\\n")

        _state(
            out_dir,
            "QWEN_PIPELINE_START",
            f"answer_mode={args.answer_mode}",
        )

        pipeline_start = time.monotonic()

        answer = assistant.run_once_from_text(
            prompt_text,
            speak=False,
            play=False,
        )

        summary["pipeline_elapsed_seconds"] = (
            time.monotonic() - pipeline_start
        )

        answer = str(answer or "").strip()

        _state(
            out_dir,
            "QWEN_PIPELINE_DONE",
            (
                f"elapsed={summary['pipeline_elapsed_seconds']:.3f}s, "
                f"answer_chars={len(answer)}"
            ),
        )

        if not args.no_speak and not args.no_play and answer:
            from .streaming_tts import StreamingTtsPlayer

            _state(
                out_dir,
                "TTS_START",
                f"answer_chars={len(answer)}",
            )

            tts_start = time.monotonic()
            player = StreamingTtsPlayer(assistant.config)

            try:
                player.enqueue(answer)
            finally:
                player.close()

            summary["tts_elapsed_seconds"] = (
                time.monotonic() - tts_start
            )

            _state(
                out_dir,
                "TTS_DONE",
                f"elapsed={summary['tts_elapsed_seconds']:.3f}s",
            )
        else:
            summary["tts_elapsed_seconds"] = 0.0
            _state(out_dir, "TTS_SKIPPED")

        summary["answer_chars"] = len(answer)
'''

if "QWEN_PIPELINE_START" not in session:
    if old_run not in session:
        raise RuntimeError(
            "Cannot find existing QWEN_TTS execution block"
        )

    session = session.replace(old_run, new_run, 1)
    print("[PATCH] split Qwen pipeline and TTS timing")
else:
    print("[SKIP] timing split already exists")


cli_path.write_text(cli, encoding="utf-8")
session_path.write_text(session, encoding="utf-8")

print("[OK] source files updated")
PY

echo

echo "==================== 3. compile ===================="

set +e

.venv/bin/python -m py_compile \
    voice_assistant.py \
    voice_assistant/cli.py \
    voice_assistant/controlled_session.py \
    voice_assistant/orchestrator.py \
    voice_assistant/streaming_tts.py \
    > "$OUT_DIR/compile_stdout.txt" \
    2> "$OUT_DIR/compile_stderr.txt"

compile_return_code=$?

set -e

echo "compile_return_code: $compile_return_code"
cat "$OUT_DIR/compile_stdout.txt"
cat "$OUT_DIR/compile_stderr.txt"
echo

if [ "$compile_return_code" -ne 0 ]; then
    echo "[FAIL] compile failed, restoring source"

    cp -a "$OUT_DIR/cli.py.before" "$CLI_FILE"
    cp -a "$OUT_DIR/controlled_session.py.before" "$SESSION_FILE"

    echo "[RESULT] Experiment 10.2 COMPILE_FAILED_AND_RESTORED"
    exit 1
fi

echo "==================== 4. help ===================="

.venv/bin/python voice_assistant.py listen-controlled --help \
    > "$OUT_DIR/controlled_help.txt" \
    2> "$OUT_DIR/controlled_help_stderr.txt"

help_return_code=$?

echo "help_return_code: $help_return_code"
cat "$OUT_DIR/controlled_help.txt"
cat "$OUT_DIR/controlled_help_stderr.txt"
echo

echo "==================== 5. key lines ===================="

grep -nE \
"answer-mode|answer-max-chars|QWEN_PIPELINE|TTS_START|TTS_DONE|pipeline_elapsed|tts_elapsed|qwen_prompt" \
voice_assistant/cli.py \
voice_assistant/controlled_session.py \
> "$OUT_DIR/key_lines.txt" || true

cat "$OUT_DIR/key_lines.txt"
echo

echo "==================== 6. diff ===================="

diff -u \
    "$OUT_DIR/cli.py.before" \
    "$CLI_FILE" \
    > "$OUT_DIR/cli.diff" || true

diff -u \
    "$OUT_DIR/controlled_session.py.before" \
    "$SESSION_FILE" \
    > "$OUT_DIR/controlled_session.diff" || true

cat "$OUT_DIR/cli.diff"
cat "$OUT_DIR/controlled_session.diff"
echo

echo "==================== 7. summary ===================="

{
    echo "out_dir            : $OUT_DIR"
    echo "compile_return_code: $compile_return_code"
    echo "help_return_code   : $help_return_code"
    echo "answer_mode_count  : $(grep -c -- '--answer-mode' "$CLI_FILE" || true)"
    echo "pipeline_state_count: $(grep -c 'QWEN_PIPELINE_START' "$SESSION_FILE" || true)"
    echo "tts_state_count    : $(grep -c 'TTS_START' "$SESSION_FILE" || true)"
} | tee "$OUT_DIR/summary.txt"

if [ "$compile_return_code" -eq 0 ] \
  && [ "$help_return_code" -eq 0 ] \
  && grep -q -- "--answer-mode" "$OUT_DIR/controlled_help.txt" \
  && grep -q "QWEN_PIPELINE_START" "$SESSION_FILE" \
  && grep -q "TTS_START" "$SESSION_FILE"; then

    echo "[RESULT] Experiment 10.2 PATCH PASSED."
    echo "[NEXT] Run concise timing live test."
else
    echo "[RESULT] Experiment 10.2 PATCH FAILED_OR_NEEDS_CHECK."
    exit 1
fi
