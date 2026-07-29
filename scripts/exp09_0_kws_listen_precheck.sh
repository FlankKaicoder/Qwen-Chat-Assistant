#!/usr/bin/env bash
set -u

OUT_DIR="${1:-output/exp09_0_kws_listen_precheck_manual}"
mkdir -p "$OUT_DIR"

LOG="$OUT_DIR/run.log"
exec > >(tee "$LOG") 2>&1

PY=".venv/bin/python"
if [ ! -x "$PY" ]; then
  PY="$(command -v python3)"
fi

export PYTHONPATH="$(pwd)/.python_packages:$(pwd):${PYTHONPATH:-}"

echo "============================================================"
echo " Experiment 09.0: KWS / listen / listen-forever Precheck"
echo "============================================================"
echo "time    : $(date '+%Y-%m-%d %H:%M:%S')"
echo "workdir : $(pwd)"
echo "out_dir : $OUT_DIR"
echo "python  : $PY"
echo "PYTHONPATH=$PYTHONPATH"
echo

echo "==================== 1. repo and branch ===================="
pwd
git branch --show-current 2>/dev/null || true
git log -1 --oneline 2>/dev/null || true
echo

echo "==================== 2. command availability ===================="
for cmd in python3 ffmpeg arecord aplay amixer file soxi ffprobe timeout grep sed awk find; do
  printf "%-12s : " "$cmd"
  command -v "$cmd" || echo "MISSING"
done
echo

echo "==================== 3. audio config quick check ===================="
grep -nE "audio:|mic_device|speaker_device|sample_rate|channels|input_channel|wake_input_gain|asr_input_gain|command_seconds|wake_chunk_seconds|mixer_card" \
  config/default.yaml || true
echo

echo "==================== 4. kws config quick check ===================="
grep -nE "kws|wake|keyword|tokens|encoder|decoder|joiner" config/default.yaml || true
echo

echo "==================== 5. wake keywords ===================="
if [ -f config/wake_keywords.txt ]; then
  cat config/wake_keywords.txt
else
  echo "[MISS] config/wake_keywords.txt"
fi
echo

echo "==================== 6. parse config models.kws ===================="
"$PY" - <<'PY' > "$OUT_DIR/kws_config.txt" 2>&1
from pathlib import Path
from voice_assistant.config import load_config

cfg = load_config("config/default.yaml")
models = cfg.get("models", {})
kws = models.get("kws", {})

print("models.kws =", kws)

required_keys = ["tokens", "encoder", "decoder", "joiner"]
missing = 0

for k in required_keys:
    p = kws.get(k)
    print(f"{k:8s}: {p}")
    if not p:
        print(f"[MISS] config key models.kws.{k}")
        missing += 1
    elif not Path(p).exists():
        print(f"[MISS] file not found: {p}")
        missing += 1
    else:
        fp = Path(p)
        print(f"[OK] {fp} size={fp.stat().st_size}")

print("missing_kws_config_or_files:", missing)
PY

cat "$OUT_DIR/kws_config.txt"
echo

echo "==================== 7. expected kws directory listing ===================="
KWS_DIR="models/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20"
if [ -d "$KWS_DIR" ]; then
  echo "[OK] $KWS_DIR"
  find "$KWS_DIR" -maxdepth 2 -type f | sort | sed 's/^/  /' | head -80
else
  echo "[MISS] $KWS_DIR"
fi
echo

echo "==================== 8. python import check ===================="
IMPORT_FAIL=0
for mod in \
  yaml \
  numpy \
  sherpa_onnx \
  voice_assistant.config \
  voice_assistant.audio_io \
  voice_assistant.asr \
  voice_assistant.wake \
  voice_assistant.intent \
  voice_assistant.camera \
  voice_assistant.qwen_runner \
  voice_assistant.tts \
  voice_assistant.streaming_tts \
  voice_assistant.orchestrator
do
  printf "%-36s : " "$mod"
  if "$PY" - <<PY >/dev/null 2>&1
import ${mod}
PY
  then
    echo "[OK]"
  else
    echo "[FAIL]"
    IMPORT_FAIL=$((IMPORT_FAIL + 1))
  fi
done
echo "import_fail_count: $IMPORT_FAIL"
echo

echo "==================== 9. py_compile check ===================="
COMPILE_FAIL=0
for f in \
  voice_assistant.py \
  voice_assistant/cli.py \
  voice_assistant/config.py \
  voice_assistant/audio_io.py \
  voice_assistant/wake.py \
  voice_assistant/orchestrator.py \
  voice_assistant/asr.py \
  voice_assistant/qwen_runner.py \
  voice_assistant/tts.py \
  voice_assistant/streaming_tts.py \
  voice_assistant/intent.py
do
  printf "%-36s : " "$f"
  if "$PY" -m py_compile "$f" >/dev/null 2>&1; then
    echo "[OK]"
  else
    echo "[FAIL]"
    COMPILE_FAIL=$((COMPILE_FAIL + 1))
  fi
done
echo "compile_fail_count: $COMPILE_FAIL"
echo

echo "==================== 10. cli help check ===================="
"$PY" voice_assistant.py -h > "$OUT_DIR/voice_assistant_help.txt" 2>&1 || true
cat "$OUT_DIR/voice_assistant_help.txt"
echo

for cmd in wake kws-file listen listen-forever once cleanup; do
  echo "----- help: $cmd -----"
  "$PY" voice_assistant.py "$cmd" -h > "$OUT_DIR/help_${cmd}.txt" 2>&1 || true
  cat "$OUT_DIR/help_${cmd}.txt"
  echo
done

echo "==================== 11. VoiceAssistant init check ===================="
"$PY" - <<'PY' > "$OUT_DIR/voiceassistant_init.txt" 2>&1
from voice_assistant.config import load_config
from voice_assistant.orchestrator import VoiceAssistant

cfg = load_config("config/default.yaml")
assistant = VoiceAssistant(cfg)
print("[OK] config loaded")
print("[OK] VoiceAssistant initialized")
print("assistant_type:", type(assistant).__name__)
PY

INIT_RC=$?
cat "$OUT_DIR/voiceassistant_init.txt"
echo "init_return_code: $INIT_RC"
echo

echo "==================== 12. abnormal scan ===================="
grep -nEi "error|failed|not found|No such file|Traceback|ModuleNotFound|ImportError|cannot|invalid|exception|killed|oom|segmentation" \
  "$OUT_DIR"/*.txt "$LOG" 2>/dev/null || true
echo

echo "==================== 13. summary ===================="
MISSING_KWS=$(grep -E "missing_kws_config_or_files:" "$OUT_DIR/kws_config.txt" | awk '{print $2}' | tail -1)
[ -z "${MISSING_KWS:-}" ] && MISSING_KWS=999

echo "missing_kws_config_or_files: $MISSING_KWS"
echo "import_fail_count          : $IMPORT_FAIL"
echo "compile_fail_count         : $COMPILE_FAIL"
echo "init_return_code           : $INIT_RC"

if [ "$MISSING_KWS" = "0" ] && [ "$IMPORT_FAIL" = "0" ] && [ "$COMPILE_FAIL" = "0" ] && [ "$INIT_RC" = "0" ]; then
  echo "[RESULT] Experiment 09.0 PRECHECK PASSED"
else
  echo "[RESULT] Experiment 09.0 PRECHECK BLOCKED_OR_NEEDS_FIX"
fi

echo
echo "log saved to: $LOG"
