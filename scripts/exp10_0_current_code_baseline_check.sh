#!/usr/bin/env bash

set -u

PROJECT_DIR="/home/cat/ai/qwen3vl2b"
cd "$PROJECT_DIR" || exit 1

OUT_DIR="${1:-output/exp10_0_current_code_baseline_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT_DIR"
mkdir -p "$OUT_DIR/source_snapshot"

LOG="$OUT_DIR/run.log"

exec > >(tee "$LOG") 2>&1

echo "============================================================"
echo " Experiment 10.0: Current Code and Runtime Baseline Check"
echo "============================================================"
echo "time        : $(date '+%Y-%m-%d %H:%M:%S')"
echo "project_dir : $PROJECT_DIR"
echo "out_dir     : $OUT_DIR"
echo

echo "==================== 1. system ===================="
uname -a || true
echo
python3 --version || true
echo
free -h || true
echo
df -h "$PROJECT_DIR" || true
echo

echo "==================== 2. git baseline ===================="
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "----- remote -----"
    git remote -v || true
    echo

    echo "----- branch -----"
    git branch --show-current || true
    echo

    echo "----- latest commit -----"
    git log -1 --oneline || true
    echo

    echo "----- status -----"
    git status --short || true
    echo

    echo "----- diff stat -----"
    git diff --stat || true
    echo

    git status --short > "$OUT_DIR/git_status.txt" 2>&1 || true
    git diff > "$OUT_DIR/git_diff.patch" 2>&1 || true
else
    echo "[WARN] current directory is not a git worktree"
fi
echo

echo "==================== 3. critical file existence ===================="

FILES=(
    "voice_assistant.py"
    "voice_assistant/cli.py"
    "voice_assistant/orchestrator.py"
    "voice_assistant/audio_io.py"
    "voice_assistant/asr.py"
    "voice_assistant/wake.py"
    "voice_assistant/camera.py"
    "voice_assistant/intent.py"
    "voice_assistant/qwen_runner.py"
    "voice_assistant/streaming_tts.py"
    "voice_assistant/tts.py"
    "config/default.yaml"
    "config/wake_keywords.txt"
    "scripts/capture-photo.sh"
)

missing_files=0

for f in "${FILES[@]}"; do
    if [ -f "$f" ]; then
        echo "[OK  ] $f"
    else
        echo "[MISS] $f"
        missing_files=$((missing_files + 1))
    fi
done
echo

echo "==================== 4. source snapshot ===================="

for f in "${FILES[@]}"; do
    if [ -f "$f" ]; then
        mkdir -p "$OUT_DIR/source_snapshot/$(dirname "$f")"
        cp -a "$f" "$OUT_DIR/source_snapshot/$f"
        sha256sum "$f"
    fi
done > "$OUT_DIR/source_sha256.txt"

cat "$OUT_DIR/source_sha256.txt"
echo
echo "snapshot_dir: $OUT_DIR/source_snapshot"
echo

echo "==================== 5. python compile ===================="

python3 -m py_compile \
    voice_assistant.py \
    voice_assistant/cli.py \
    voice_assistant/orchestrator.py \
    voice_assistant/audio_io.py \
    voice_assistant/asr.py \
    voice_assistant/wake.py \
    voice_assistant/camera.py \
    voice_assistant/intent.py \
    voice_assistant/qwen_runner.py \
    voice_assistant/streaming_tts.py \
    voice_assistant/tts.py \
    > "$OUT_DIR/py_compile_stdout.txt" \
    2> "$OUT_DIR/py_compile_stderr.txt"

compile_return_code=$?

echo "compile_return_code: $compile_return_code"

if [ -s "$OUT_DIR/py_compile_stdout.txt" ]; then
    echo "----- compile stdout -----"
    cat "$OUT_DIR/py_compile_stdout.txt"
fi

if [ -s "$OUT_DIR/py_compile_stderr.txt" ]; then
    echo "----- compile stderr -----"
    cat "$OUT_DIR/py_compile_stderr.txt"
fi
echo

echo "==================== 6. CLI help ===================="

python3 voice_assistant.py --help \
    > "$OUT_DIR/cli_help.txt" \
    2> "$OUT_DIR/cli_help_stderr.txt"

cli_help_return_code=$?

echo "cli_help_return_code: $cli_help_return_code"
cat "$OUT_DIR/cli_help.txt" || true

if [ -s "$OUT_DIR/cli_help_stderr.txt" ]; then
    echo "----- CLI help stderr -----"
    cat "$OUT_DIR/cli_help_stderr.txt"
fi
echo

echo "==================== 7. command inventory ===================="

grep -nE \
    "add_parser|add_subparsers|set_defaults|args\.cmd|once|listen|wake|record|stt|ask|camera|tts-stream|kws-file|controlled" \
    voice_assistant/cli.py \
    > "$OUT_DIR/cli_command_inventory.txt" 2>&1 || true

cat "$OUT_DIR/cli_command_inventory.txt"
echo

echo "==================== 8. orchestrator current logic ===================="

nl -ba voice_assistant/orchestrator.py \
    > "$OUT_DIR/orchestrator_numbered.txt"

grep -nE \
    "def |run_once|listen|record|recognized|识别文本|ask_qwen|force_photo|StreamingTtsPlayer|enqueue|完整|流式|speak|play" \
    "$OUT_DIR/orchestrator_numbered.txt" \
    > "$OUT_DIR/orchestrator_key_lines.txt" || true

cat "$OUT_DIR/orchestrator_key_lines.txt"
echo

echo "==================== 9. camera current logic ===================="

nl -ba voice_assistant/camera.py \
    > "$OUT_DIR/camera_numbered.txt"

cat "$OUT_DIR/camera_numbered.txt"
echo

echo "==================== 10. capture-photo defaults ===================="

grep -nE \
    'device=|width=|height=|pixfmt=|skip=|stream-skip|stream-count|stream-to|ffmpeg' \
    scripts/capture-photo.sh \
    > "$OUT_DIR/capture_photo_key_lines.txt" || true

cat "$OUT_DIR/capture_photo_key_lines.txt"
echo

echo "==================== 11. relevant config ===================="

python3 - <<'PY' > "$OUT_DIR/config_relevant.txt"
from pathlib import Path

try:
    import yaml
except Exception as exc:
    print(f"[FAIL] import yaml: {exc}")
    raise

path = Path("config/default.yaml")
cfg = yaml.safe_load(path.read_text())

for section in ("paths", "audio", "camera", "models", "qwen"):
    print(f"========== {section} ==========")
    value = cfg.get(section, "<MISSING>")
    print(yaml.safe_dump(value, allow_unicode=True, sort_keys=False))
PY

config_return_code=$?

echo "config_return_code: $config_return_code"
cat "$OUT_DIR/config_relevant.txt"
echo

echo "==================== 12. wake keywords ===================="

cat config/wake_keywords.txt \
    > "$OUT_DIR/wake_keywords.txt" 2>&1 || true

cat "$OUT_DIR/wake_keywords.txt"
echo

echo "==================== 13. module import check ===================="

python3 - <<'PY' > "$OUT_DIR/import_check.txt" 2>&1
modules = [
    "yaml",
    "numpy",
    "pexpect",
    "sherpa_onnx",
    "voice_assistant.config",
    "voice_assistant.audio_io",
    "voice_assistant.asr",
    "voice_assistant.wake",
    "voice_assistant.camera",
    "voice_assistant.intent",
    "voice_assistant.qwen_runner",
    "voice_assistant.tts",
    "voice_assistant.streaming_tts",
    "voice_assistant.orchestrator",
    "voice_assistant.cli",
]

failed = 0

for name in modules:
    try:
        __import__(name)
        print(f"[OK  ] {name}")
    except Exception as exc:
        failed += 1
        print(f"[FAIL] {name}: {type(exc).__name__}: {exc}")

print(f"import_fail_count: {failed}")

if failed:
    raise SystemExit(1)
PY

import_return_code=$?

cat "$OUT_DIR/import_check.txt"
echo "import_return_code: $import_return_code"
echo

echo "==================== 14. VoiceAssistant init ===================="

python3 - <<'PY' > "$OUT_DIR/assistant_init.txt" 2>&1
from voice_assistant.config import load_config
from voice_assistant.orchestrator import VoiceAssistant

cfg = load_config("config/default.yaml")
print("[OK] config loaded")

assistant = VoiceAssistant(cfg)
print("[OK] VoiceAssistant initialized")
print("assistant_type:", type(assistant).__name__)
PY

assistant_init_return_code=$?

cat "$OUT_DIR/assistant_init.txt"
echo "assistant_init_return_code: $assistant_init_return_code"
echo

echo "==================== 15. key fix detection ===================="

full_answer_tts=0
camera_popen=0
camera_new_session=0
camera_killpg=0
camera_timeout=0
capture_1280=0
capture_720=0
capture_skip5=0
controlled_cli=0

grep -q "先得到完整 Qwen 回答" voice_assistant/orchestrator.py \
    && full_answer_tts=1 || true

grep -q "subprocess.Popen" voice_assistant/camera.py \
    && camera_popen=1 || true

grep -q "start_new_session=True" voice_assistant/camera.py \
    && camera_new_session=1 || true

grep -q "killpg" voice_assistant/camera.py \
    && camera_killpg=1 || true

grep -q "communicate(timeout" voice_assistant/camera.py \
    && camera_timeout=1 || true

grep -q 'width="1280"' scripts/capture-photo.sh \
    && capture_1280=1 || true

grep -q 'height="720"' scripts/capture-photo.sh \
    && capture_720=1 || true

grep -q 'skip="5"' scripts/capture-photo.sh \
    && capture_skip5=1 || true

grep -qE "listen-controlled|listen_controlled|controlled-listen|controlled_listen" \
    voice_assistant/cli.py voice_assistant/orchestrator.py \
    && controlled_cli=1 || true

echo "full_answer_tts       : $full_answer_tts"
echo "camera_popen          : $camera_popen"
echo "camera_new_session    : $camera_new_session"
echo "camera_killpg         : $camera_killpg"
echo "camera_timeout        : $camera_timeout"
echo "capture_width_1280    : $capture_1280"
echo "capture_height_720    : $capture_720"
echo "capture_skip_5        : $capture_skip5"
echo "controlled_cli_exists : $controlled_cli"
echo

echo "==================== 16. residual process check ===================="

ps -eo pid,ppid,stat,etime,cmd \
    | grep -E \
      "voice_assistant.py|capture-photo.sh|v4l2-ctl|ffmpeg|arecord|aplay|/demo|imgenc" \
    | grep -v -E "grep|exp10_0_current_code_baseline_check" \
    > "$OUT_DIR/residual_processes.txt" || true

if [ -s "$OUT_DIR/residual_processes.txt" ]; then
    cat "$OUT_DIR/residual_processes.txt"
else
    echo "[OK] no related residual processes"
fi
echo

echo "==================== 17. summary ===================="

{
    echo "out_dir                 : $OUT_DIR"
    echo "missing_files           : $missing_files"
    echo "compile_return_code     : $compile_return_code"
    echo "cli_help_return_code    : $cli_help_return_code"
    echo "config_return_code      : $config_return_code"
    echo "import_return_code      : $import_return_code"
    echo "assistant_init_return_code: $assistant_init_return_code"
    echo "full_answer_tts         : $full_answer_tts"
    echo "camera_popen            : $camera_popen"
    echo "camera_new_session      : $camera_new_session"
    echo "camera_killpg           : $camera_killpg"
    echo "camera_timeout          : $camera_timeout"
    echo "capture_width_1280      : $capture_1280"
    echo "capture_height_720      : $capture_720"
    echo "capture_skip_5          : $capture_skip5"
    echo "controlled_cli_exists   : $controlled_cli"
    echo "residual_process_count  : $(wc -l < "$OUT_DIR/residual_processes.txt")"
} | tee "$OUT_DIR/summary.txt"

echo

if [ "$missing_files" -ne 0 ]; then
    echo "[RESULT] Experiment 10.0 FAILED: critical source files missing."
elif [ "$compile_return_code" -ne 0 ]; then
    echo "[RESULT] Experiment 10.0 FAILED: Python compile failed."
elif [ "$import_return_code" -ne 0 ]; then
    echo "[RESULT] Experiment 10.0 FAILED: module import failed."
elif [ "$assistant_init_return_code" -ne 0 ]; then
    echo "[RESULT] Experiment 10.0 FAILED: VoiceAssistant initialization failed."
elif [ "$full_answer_tts" -ne 1 ]; then
    echo "[RESULT] Experiment 10.0 NEEDS_FIX: full-answer TTS patch not detected."
elif [ "$camera_popen" -ne 1 ] \
  || [ "$camera_new_session" -ne 1 ] \
  || [ "$camera_killpg" -ne 1 ] \
  || [ "$camera_timeout" -ne 1 ]; then
    echo "[RESULT] Experiment 10.0 NEEDS_FIX: camera process-group timeout patch incomplete."
elif [ "$capture_1280" -ne 1 ] \
  || [ "$capture_720" -ne 1 ] \
  || [ "$capture_skip5" -ne 1 ]; then
    echo "[RESULT] Experiment 10.0 NEEDS_FIX: capture-photo defaults do not match Experiment 09 stable settings."
else
    echo "[RESULT] Experiment 10.0 BASELINE PASSED."
    echo "[NEXT] Continue to Experiment 10.1: add the formal listen-controlled CLI."
fi

echo
echo "log saved to: $LOG"
