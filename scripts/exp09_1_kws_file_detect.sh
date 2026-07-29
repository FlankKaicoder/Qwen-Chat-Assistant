#!/usr/bin/env bash
set -u

OUT_DIR="${1:-output/exp09_1_kws_file_detect_manual}"
SECONDS="${2:-4}"

mkdir -p "$OUT_DIR"

PY=".venv/bin/python"
if [ ! -x "$PY" ]; then
  PY="$(command -v python3)"
fi

export PYTHONPATH="$(pwd)/.python_packages:$(pwd):${PYTHONPATH:-}"

LOG="$OUT_DIR/run.log"
WAV="$OUT_DIR/wake_record.wav"
RECORD_LOG="$OUT_DIR/record.log"
KWS_STDOUT="$OUT_DIR/kws_stdout.txt"
KWS_STDERR="$OUT_DIR/kws_stderr.txt"
VOL_LOG="$OUT_DIR/volumedetect.log"
HELP_LOG="$OUT_DIR/kws_file_help.txt"

exec > >(tee "$LOG") 2>&1

echo "============================================================"
echo " Experiment 09.1: KWS file detection"
echo "============================================================"
echo "time    : $(date '+%Y-%m-%d %H:%M:%S')"
echo "workdir : $(pwd)"
echo "out_dir : $OUT_DIR"
echo "python  : $PY"
echo "seconds : $SECONDS"
echo

echo "==================== 1. instruction ===================="
echo "录音开始后，请只说唤醒词：鲁班猫"
echo "如果这次不通过，下一次再测：拍照助手"
echo

echo "==================== 2. kws-file help ===================="
"$PY" voice_assistant.py kws-file -h > "$HELP_LOG" 2>&1 || true
cat "$HELP_LOG"
echo

echo "==================== 3. record wake wav ===================="
echo "[RUN] $PY voice_assistant.py record --seconds $SECONDS --out $WAV"
"$PY" voice_assistant.py record \
  --seconds "$SECONDS" \
  --out "$WAV" \
  > "$RECORD_LOG" 2>&1

RECORD_RC=$?
cat "$RECORD_LOG"
echo "record_return_code: $RECORD_RC"
echo

echo "==================== 4. wav info ===================="
if [ -f "$WAV" ]; then
  ls -lh "$WAV"
  file "$WAV" || true
  soxi "$WAV" 2>/dev/null || true
  ffprobe -hide_banner "$WAV" > "$OUT_DIR/wav_ffprobe.txt" 2>&1 || true
  cat "$OUT_DIR/wav_ffprobe.txt"
else
  echo "[MISS] $WAV"
fi
echo

echo "==================== 5. volume detect ===================="
if [ -f "$WAV" ]; then
  ffmpeg -hide_banner \
    -i "$WAV" \
    -af volumedetect \
    -f null - \
    > "$VOL_LOG" 2>&1 || true

  grep -E "mean_volume|max_volume" "$VOL_LOG" || true
fi
echo

echo "==================== 6. run kws-file ===================="
echo "[RUN] $PY voice_assistant.py kws-file $WAV"

"$PY" voice_assistant.py kws-file "$WAV" > "$KWS_STDOUT" 2> "$KWS_STDERR"
KWS_RC=$?

echo "kws_return_code: $KWS_RC"
echo

echo "----- kws stdout -----"
cat "$KWS_STDOUT"
echo

echo "----- kws stderr -----"
cat "$KWS_STDERR"
echo

echo "==================== 7. abnormal scan ===================="
grep -nEi "error|failed|Traceback|ModuleNotFound|ImportError|Unable|Broken pipe|No such file|not found|cannot|killed|oom|segmentation|exception" \
  "$RECORD_LOG" "$KWS_STDOUT" "$KWS_STDERR" "$LOG" > "$OUT_DIR/abnormal.txt" 2>/dev/null || true
cat "$OUT_DIR/abnormal.txt"
echo

echo "==================== 8. summary ===================="
MEAN_VOL=$(grep -E "mean_volume" "$VOL_LOG" 2>/dev/null | tail -1 | sed 's/.*mean_volume: //')
MAX_VOL=$(grep -E "max_volume" "$VOL_LOG" 2>/dev/null | tail -1 | sed 's/.*max_volume: //')

DETECTED_TEXT=$(cat "$KWS_STDOUT" "$KWS_STDERR" 2>/dev/null | grep -E "鲁班猫|拍照助手|keyword|Keyword|detected|Detected|wake|Wake" | tail -5 | tr '\n' ' ')

echo "out_dir           : $OUT_DIR"
echo "record_return_code: $RECORD_RC"
echo "kws_return_code   : $KWS_RC"
echo "wav_path          : $WAV"
echo "mean_volume       : ${MEAN_VOL:-}"
echo "max_volume        : ${MAX_VOL:-}"
echo "detected_key_text : ${DETECTED_TEXT:-}"

if [ "$RECORD_RC" = "0" ] && [ "$KWS_RC" = "0" ]; then
  echo "[RESULT] Experiment 09.1 PASSED_BY_COMMAND"
else
  echo "[RESULT] Experiment 09.1 FAILED_OR_NEEDS_CHECK"
fi

echo
echo "log saved to: $LOG"
