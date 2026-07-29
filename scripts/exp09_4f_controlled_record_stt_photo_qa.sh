#!/usr/bin/env bash
set -u

OUT_DIR="${1:-output/exp09_4f_controlled_record_stt_photo_qa_manual}"
CMD_SECONDS="${2:-6}"
RUN_TIMEOUT="${3:-180}"

mkdir -p "$OUT_DIR"

PY=".venv/bin/python"
if [ ! -x "$PY" ]; then
  PY="$(command -v python3)"
fi

export PYTHONPATH="$(pwd)/.python_packages:$(pwd):${PYTHONPATH:-}"

LOG="$OUT_DIR/run.log"
CMD_WAV="$OUT_DIR/command.wav"

exec > >(tee "$LOG") 2>&1

echo "============================================================"
echo " Experiment 09.4f: controlled record -> STT -> photo QA"
echo "============================================================"
echo "time       : $(date '+%Y-%m-%d %H:%M:%S')"
echo "workdir    : $(pwd)"
echo "out_dir    : $OUT_DIR"
echo "python     : $PY"
echo "cmd_seconds: $CMD_SECONDS"
echo "run_timeout: $RUN_TIMEOUT"
echo

echo "==================== 1. camera / capture config ===================="
grep -nE "capture_timeout|timeout=self.capture_timeout" voice_assistant/camera.py || true
grep -nE 'device=|width=|height=|pixfmt=|skip=' scripts/capture-photo.sh || true
echo

echo "==================== 2. before photo list ===================="
find /home/cat/图片 -maxdepth 1 -type f -name 'voice_*.jpg' 2>/dev/null | sort > "$OUT_DIR/photos_before.txt"
tail -8 "$OUT_DIR/photos_before.txt" || true
echo

echo "==================== 3. record command wav ===================="
echo "录音开始后请说：拍照，看一下画面"
echo "建议：看到 Recording WAVE 后再说，不要太靠近麦克风。"
read -p "准备好后按回车开始录音..." _

"$PY" voice_assistant.py record \
  --seconds "$CMD_SECONDS" \
  --out "$CMD_WAV" \
  > "$OUT_DIR/record_stdout.txt" \
  2> "$OUT_DIR/record_stderr.txt"

REC_RC=$?

echo "record_return_code: $REC_RC"
echo

echo "----- record stdout -----"
cat "$OUT_DIR/record_stdout.txt"
echo

echo "----- record stderr -----"
cat "$OUT_DIR/record_stderr.txt"
echo

echo "==================== 4. wav info / volume ===================="
ls -lh "$CMD_WAV" || true
file "$CMD_WAV" || true
soxi "$CMD_WAV" 2>/dev/null || true

ffmpeg -hide_banner -i "$CMD_WAV" -af volumedetect -f null - \
  > "$OUT_DIR/volumedetect.log" 2>&1 || true

grep -E "mean_volume|max_volume" "$OUT_DIR/volumedetect.log" || true
echo

echo "==================== 5. STT ===================="
"$PY" voice_assistant.py stt "$CMD_WAV" \
  > "$OUT_DIR/stt_text.txt" \
  2> "$OUT_DIR/stt_stderr.txt"

STT_RC=$?
TEXT=$(cat "$OUT_DIR/stt_text.txt" | tr -d '\r\n')

echo "stt_return_code: $STT_RC"
echo "recognized_text: $TEXT"
echo

echo "----- stt stderr -----"
cat "$OUT_DIR/stt_stderr.txt"
echo

echo "==================== 6. intent check ===================="
PHOTO_INTENT=0
case "$TEXT" in
  *拍照*|*画面*|*看一下*|*照片*|*图片*)
    PHOTO_INTENT=1
    ;;
esac

echo "photo_intent: $PHOTO_INTENT"

if [ "$PHOTO_INTENT" != "1" ]; then
  echo "[STOP] ASR 未命中拍照意图，本轮不继续调用 Qwen。"
  echo "[RESULT] Experiment 09.4f NEEDS_RETRY_ASR_NO_PHOTO_INTENT"
  exit 0
fi
echo

echo "==================== 7. ask --force-photo ===================="
echo "[RUN] timeout ${RUN_TIMEOUT}s $PY voice_assistant.py ask \"$TEXT\" --force-photo"

timeout "$RUN_TIMEOUT" stdbuf -oL -eL \
  "$PY" voice_assistant.py ask "$TEXT" --force-photo \
  > >(tee "$OUT_DIR/ask_stdout.txt") \
  2> >(tee "$OUT_DIR/ask_stderr.txt" >&2)

ASK_RC=$?

echo
echo "ask_return_code: $ASK_RC"
echo

echo "==================== 8. after photo list ===================="
find /home/cat/图片 -maxdepth 1 -type f -name 'voice_*.jpg' 2>/dev/null | sort > "$OUT_DIR/photos_after.txt"
comm -13 "$OUT_DIR/photos_before.txt" "$OUT_DIR/photos_after.txt" > "$OUT_DIR/new_photos.txt" || true

NEW_PHOTO_COUNT=$(wc -l < "$OUT_DIR/new_photos.txt" | tr -d ' ')
NEW_PHOTO_PATH=$(tail -1 "$OUT_DIR/new_photos.txt" 2>/dev/null || true)

echo "new_photo_count: $NEW_PHOTO_COUNT"
echo "new_photo_path : $NEW_PHOTO_PATH"
echo

if [ -n "$NEW_PHOTO_PATH" ] && [ -f "$NEW_PHOTO_PATH" ]; then
  cp -av "$NEW_PHOTO_PATH" "$OUT_DIR/latest_voice_photo.jpg" || true

  ffprobe -hide_banner -v error \
    -select_streams v:0 \
    -show_entries stream=codec_name,width,height,pix_fmt \
    -of default=noprint_wrappers=1 \
    "$NEW_PHOTO_PATH" > "$OUT_DIR/photo_ffprobe.txt" 2>&1 || true

  echo "----- photo ffprobe -----"
  cat "$OUT_DIR/photo_ffprobe.txt"
fi
echo

echo "==================== 9. parse answer ===================="
# ask stdout 里前面有 lightweight ask 的 image/text 打印，后面才是 Qwen 回答。
# 这里保守提取：去掉明显的头部信息。
awk '
  BEGIN{skip=0}
  /^========== lightweight ask ==========/ {skip=1; next}
  /^image[[:space:]]*:/ {next}
  /^text[[:space:]]*:/ {next}
  skip && /^[[:space:]]*$/ {skip=0; next}
  {print}
' "$OUT_DIR/ask_stdout.txt" > "$OUT_DIR/qwen_answer.txt" 2>/dev/null || true

QWEN_ANSWER_CHARS=$(python3 - <<PY
from pathlib import Path
p = Path("$OUT_DIR/qwen_answer.txt")
s = p.read_text(errors="ignore") if p.exists() else ""
print(len(s.strip()))
PY
)

UNDERRUN_COUNT=$(grep -R "underrun" "$OUT_DIR/ask_stdout.txt" "$OUT_DIR/ask_stderr.txt" 2>/dev/null | wc -l | tr -d ' ')

echo "qwen_answer_chars: $QWEN_ANSWER_CHARS"
echo
echo "qwen_answer:"
cat "$OUT_DIR/qwen_answer.txt"
echo

echo "==================== 10. abnormal scan ===================="
grep -nEi "error|failed|Traceback|ModuleNotFound|ImportError|Unable to install hw params|underrun|Broken pipe|No such file|not found|cannot|timeout|killed|oom|segmentation|exception" \
  "$OUT_DIR"/*.txt "$OUT_DIR"/*.log > "$OUT_DIR/abnormal.txt" 2>/dev/null || true
cat "$OUT_DIR/abnormal.txt"
echo

echo "==================== 11. summary ===================="
MEAN=$(grep -E "mean_volume" "$OUT_DIR/volumedetect.log" 2>/dev/null | tail -1 | sed 's/.*mean_volume: //')
MAX=$(grep -E "max_volume" "$OUT_DIR/volumedetect.log" 2>/dev/null | tail -1 | sed 's/.*max_volume: //')

echo "out_dir          : $OUT_DIR"
echo "record_return_code: $REC_RC"
echo "stt_return_code   : $STT_RC"
echo "ask_return_code   : $ASK_RC"
echo "recognized_text   : $TEXT"
echo "photo_intent      : $PHOTO_INTENT"
echo "mean_volume       : ${MEAN:-}"
echo "max_volume        : ${MAX:-}"
echo "new_photo_count   : $NEW_PHOTO_COUNT"
echo "new_photo_path    : $NEW_PHOTO_PATH"
echo "qwen_answer_chars : $QWEN_ANSWER_CHARS"
echo "underrun_count    : $UNDERRUN_COUNT"

if [ "$REC_RC" = "0" ] \
   && [ "$STT_RC" = "0" ] \
   && [ "$ASK_RC" = "0" ] \
   && [ "$PHOTO_INTENT" = "1" ] \
   && [ "$NEW_PHOTO_COUNT" -gt 0 ] \
   && [ "$QWEN_ANSWER_CHARS" -gt 0 ] \
   && [ "$UNDERRUN_COUNT" = "0" ]; then
  echo "[RESULT] Experiment 09.4f PASSED_CONTROLLED_VOICE_PHOTO_QA"
else
  echo "[RESULT] Experiment 09.4f FAILED_OR_NEEDS_CHECK"
fi

echo
echo "log saved to: $LOG"
