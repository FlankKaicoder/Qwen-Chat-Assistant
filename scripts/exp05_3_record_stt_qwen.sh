#!/usr/bin/env bash
set -u

OUT="output/exp05_3_record_stt_qwen_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"

LOG="$OUT/run.log"
exec > >(tee "$LOG") 2>&1

echo "========== exp05.3 record -> stt -> qwen =========="
echo "time    : $(date '+%Y-%m-%d %H:%M:%S')"
echo "workdir : $(pwd)"
echo "out     : $OUT"
echo

export LD_LIBRARY_PATH=".:${LD_LIBRARY_PATH:-}"
export RKLLM_LOG_LEVEL=1

PY=".venv/bin/python"
if [ ! -x "$PY" ]; then
  PY="python3"
fi

echo "python: $PY"
"$PY" --version
echo

WAV="$OUT/command.wav"
ASR_TXT="$OUT/asr_text.txt"
QWEN_OUT="$OUT/qwen_answer.txt"
QWEN_ERR="$OUT/qwen_stderr.txt"

echo "========== 1. record =========="
echo "请在开始录音后说一句中文问题，例如：请简单介绍一下这张图片。"
"$PY" voice_assistant.py record \
  --seconds 6 \
  --out "$WAV"

echo
echo "========== wav info =========="
file "$WAV"
ffprobe -hide_banner "$WAV" 2>&1 || true

echo
echo "========== volume =========="
ffmpeg -hide_banner \
  -i "$WAV" \
  -af volumedetect \
  -f null - 2>&1 | tee "$OUT/volume_detect.log" | grep -E "mean_volume|max_volume" || true

echo
echo "========== 2. stt =========="
"$PY" voice_assistant.py stt "$WAV" | tee "$ASR_TXT"

TEXT="$(cat "$ASR_TXT" | tail -n 1 | tr -d '\r')"

echo
echo "recognized_text: $TEXT"

if [ -z "$TEXT" ]; then
  echo "[RESULT] Experiment 05.3 FAILED: empty ASR text"
  exit 1
fi

echo
echo "========== 3. qwen ask =========="
echo "question: $TEXT"

START=$(date +%s)

"$PY" voice_assistant.py ask "$TEXT" \
  --image demo.jpg \
  --no-speak \
  --no-play \
  > "$QWEN_OUT" 2> "$QWEN_ERR"

RC=$?
END=$(date +%s)
ELAPSED=$((END - START))

echo "return_code: $RC"
echo "elapsed_seconds: $ELAPSED"

echo
echo "========== qwen stdout =========="
cat "$QWEN_OUT"

echo
echo "========== qwen stderr =========="
cat "$QWEN_ERR"

echo
echo "========== result =========="
if [ "$RC" -eq 0 ] && [ -s "$QWEN_OUT" ]; then
  echo "[RESULT] Experiment 05.3 PASSED"
else
  echo "[RESULT] Experiment 05.3 FAILED"
fi

echo
echo "log saved to: $LOG"
