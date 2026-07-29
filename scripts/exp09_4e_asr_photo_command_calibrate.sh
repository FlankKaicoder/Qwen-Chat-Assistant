#!/usr/bin/env bash
set -u

OUT_DIR="${1:-output/exp09_4e_asr_photo_command_calibrate_manual}"
REC_SECONDS="${2:-6}"

mkdir -p "$OUT_DIR"

PY=".venv/bin/python"
[ -x "$PY" ] || PY=python3

export PYTHONPATH="$(pwd)/.python_packages:$(pwd):${PYTHONPATH:-}"

LOG="$OUT_DIR/run.log"
exec > >(tee "$LOG") 2>&1

echo "============================================================"
echo " Experiment 09.4e: ASR photo command calibration"
echo "============================================================"
echo "out_dir    : $OUT_DIR"
echo "rec_seconds: $REC_SECONDS"
echo

run_case() {
  NAME="$1"
  PHRASE="$2"
  WAV="$OUT_DIR/${NAME}.wav"

  echo
  echo "==================== $NAME ===================="
  echo "录音开始后请说：$PHRASE"
  read -p "准备好后按回车开始录音..." _

  "$PY" voice_assistant.py record --seconds "$REC_SECONDS" --out "$WAV" \
    > "$OUT_DIR/${NAME}_record.log" 2>&1
  REC_RC=$?

  "$PY" voice_assistant.py stt "$WAV" \
    > "$OUT_DIR/${NAME}_stt.txt" 2> "$OUT_DIR/${NAME}_stt_stderr.txt"
  STT_RC=$?

  ffmpeg -hide_banner -i "$WAV" -af volumedetect -f null - \
    > "$OUT_DIR/${NAME}_volumedetect.log" 2>&1 || true

  MEAN=$(grep -E "mean_volume" "$OUT_DIR/${NAME}_volumedetect.log" | tail -1 | sed 's/.*mean_volume: //')
  MAX=$(grep -E "max_volume" "$OUT_DIR/${NAME}_volumedetect.log" | tail -1 | sed 's/.*max_volume: //')
  TEXT=$(cat "$OUT_DIR/${NAME}_stt.txt" | tr -d '\r\n')

  echo "phrase              : $PHRASE"
  echo "wav                 : $WAV"
  echo "record_return_code  : $REC_RC"
  echo "stt_return_code     : $STT_RC"
  echo "mean_volume         : ${MEAN:-}"
  echo "max_volume          : ${MAX:-}"
  echo "recognized_text     : $TEXT"

  {
    echo "case: $NAME"
    echo "phrase: $PHRASE"
    echo "recognized: $TEXT"
    echo "mean_volume: ${MEAN:-}"
    echo "max_volume: ${MAX:-}"
    echo
  } >> "$OUT_DIR/summary.txt"
}

run_case "look_screen" "看一下画面"
run_case "take_photo" "拍照"
run_case "photo_screen" "拍照，看一下画面"

echo
echo "==================== summary ===================="
cat "$OUT_DIR/summary.txt"

echo
echo "[RESULT] Experiment 09.4e COMPLETED_ASR_COMMAND_CALIBRATION"
echo "log saved to: $LOG"
