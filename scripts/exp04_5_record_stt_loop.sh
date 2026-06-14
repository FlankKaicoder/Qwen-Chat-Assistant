#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="$1"
mkdir -p "$OUT_DIR"

LOG="$OUT_DIR/exp04_5_record_stt_loop.log"
exec > >(tee "$LOG") 2>&1

WAV="$OUT_DIR/command.wav"
TXT="$OUT_DIR/asr_text.txt"

echo "======================================="
echo " Experiment 04.5 Record -> STT Loop"
echo "======================================="
echo "out dir: $OUT_DIR"
echo

echo "请说一句中文，例如："
echo "你好我是良民健我正在使用三五八八"
echo
echo "3秒后开始录音..."
sleep 3

echo
echo "========== record =========="
.venv/bin/python voice_assistant.py record \
  --seconds 6 \
  --out "$WAV"

echo
echo "========== wav check =========="
ls -lh "$WAV"
file "$WAV"

ffprobe -v error \
  -show_entries stream=codec_name,sample_rate,channels,sample_fmt,duration \
  -show_entries format=size,duration \
  -of default=noprint_wrappers=1 \
  "$WAV"

echo
echo "========== volume =========="
ffmpeg -hide_banner \
  -i "$WAV" \
  -af volumedetect \
  -f null - 2>&1 \
  | tee "$OUT_DIR/volume_detect.log"

echo
echo "========== stt =========="
.venv/bin/python voice_assistant.py stt "$WAV" \
  > "$TXT" \
  2> "$OUT_DIR/stt_stderr.log"

cat "$TXT"

echo
echo "========== stderr =========="
cat "$OUT_DIR/stt_stderr.log"

echo
echo "========== final result =========="
if [ -s "$TXT" ]; then
    echo "[RESULT] Experiment 04.5 PASSED"
    echo "recognized_text: $(cat "$TXT")"
else
    echo "[RESULT] Experiment 04.5 FAILED: empty ASR text"
    exit 1
fi

echo
echo "log saved to: $LOG"
