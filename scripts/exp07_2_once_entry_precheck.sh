#!/usr/bin/env bash

set -u

PROJECT_DIR="/home/cat/ai/qwen3vl2b"
cd "$PROJECT_DIR" || exit 1

OUT="${1:-output/exp07_2_once_entry_precheck_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT"

LOG="$OUT/run.log"
exec > >(tee "$LOG") 2>&1

export PYTHONPATH="$PROJECT_DIR:$PROJECT_DIR/.python_packages:${PYTHONPATH:-}"
export LD_LIBRARY_PATH="$PROJECT_DIR:${LD_LIBRARY_PATH:-}"

PY="$PROJECT_DIR/.venv/bin/python"
if [ ! -x "$PY" ]; then
    PY="$(command -v python3)"
fi

echo "============================================================"
echo " Experiment 07.2: once entry precheck"
echo "============================================================"
echo "time        : $(date '+%Y-%m-%d %H:%M:%S')"
echo "project_dir : $PROJECT_DIR"
echo "out_dir     : $OUT"
echo "python      : $PY"
echo

echo "==================== 1. command help ===================="
echo "----- voice_assistant.py --help -----"
"$PY" voice_assistant.py --help > "$OUT/help_main.txt" 2>&1
cat "$OUT/help_main.txt"
echo

echo "----- voice_assistant.py once --help -----"
"$PY" voice_assistant.py once --help > "$OUT/help_once.txt" 2>&1
cat "$OUT/help_once.txt"
echo

echo "==================== 2. import checks ===================="
"$PY" - <<'PY' > "output_tmp_import_check.txt" 2>&1
import sys
print("python:", sys.version)

mods = [
    "yaml",
    "numpy",
    "pexpect",
    "sherpa_onnx",
    "voice_assistant.config",
    "voice_assistant.audio_io",
    "voice_assistant.asr",
    "voice_assistant.qwen_runner",
    "voice_assistant.tts",
    "voice_assistant.streaming_tts",
    "voice_assistant.camera",
    "voice_assistant.intent",
    "voice_assistant.orchestrator",
]

for m in mods:
    try:
        __import__(m)
        print("[OK]", m)
    except Exception as e:
        print("[FAIL]", m, repr(e))
PY
cat output_tmp_import_check.txt
cp output_tmp_import_check.txt "$OUT/import_check.txt"
rm -f output_tmp_import_check.txt
echo

echo "==================== 3. VoiceAssistant init check ===================="
"$PY" - <<'PY' > "$OUT/voiceassistant_init.txt" 2>&1
from voice_assistant.config import load_config
from voice_assistant.orchestrator import VoiceAssistant

cfg = load_config("config/default.yaml")
print("[OK] config loaded")

assistant = VoiceAssistant(cfg)
print("[OK] VoiceAssistant initialized")
print("assistant_type:", type(assistant).__name__)
PY

init_rc=$?
cat "$OUT/voiceassistant_init.txt"
echo
echo "init_return_code: $init_rc"
echo

echo "==================== 4. abnormal check ===================="
grep -nEi "error|failed|not found|segmentation|killed|cannot|invalid|timeout|oom|exception|Traceback|ModuleNotFound|xrun|Broken pipe|Unable to install hw params" \
  "$OUT/help_main.txt" \
  "$OUT/help_once.txt" \
  "$OUT/import_check.txt" \
  "$OUT/voiceassistant_init.txt" \
  > "$OUT/abnormal.txt" 2>/dev/null || true

cat "$OUT/abnormal.txt" || true
echo

echo "==================== 5. summary ===================="
echo "init_return_code: $init_rc"
echo "out_dir         : $OUT"

if [ "$init_rc" -eq 0 ]; then
    echo "[RESULT] Experiment 07.2 PRECHECK PASSED"
else
    echo "[RESULT] Experiment 07.2 PRECHECK FAILED"
fi

echo
echo "log saved to: $LOG"
