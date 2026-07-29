#!/usr/bin/env bash
set -u

OUT_DIR="${1:-output/exp09_4d_once_photo_qa_live_debug_manual}"
CMD_SECONDS="${2:-5}"
RUN_TIMEOUT="${3:-160}"

mkdir -p "$OUT_DIR"

PY=".venv/bin/python"
if [ ! -x "$PY" ]; then
  PY="$(command -v python3)"
fi

export PYTHONPATH="$(pwd)/.python_packages:$(pwd):${PYTHONPATH:-}"

LOG="$OUT_DIR/run.log"
STDOUT="$OUT_DIR/once_stdout.txt"
STDERR="$OUT_DIR/once_stderr.txt"

exec > >(tee "$LOG") 2>&1

echo "============================================================"
echo " Experiment 09.4d: once photo QA live debug"
echo "============================================================"
echo "time       : $(date '+%Y-%m-%d %H:%M:%S')"
echo "workdir    : $(pwd)"
echo "out_dir    : $OUT_DIR"
echo "python     : $PY"
echo "cmd_seconds: $CMD_SECONDS"
echo "run_timeout: $RUN_TIMEOUT"
echo

echo "==================== 1. camera.py timeout check ===================="
grep -nE "capture_timeout|subprocess.run|timeout=self.capture_timeout" voice_assistant/camera.py || true
echo

echo "==================== 2. capture-photo defaults ===================="
grep -nE 'device=|width=|height=|pixfmt=|skip=' scripts/capture-photo.sh || true
echo

echo "==================== 3. before photo list ===================="
find /home/cat/图片 -maxdepth 1 -type f -name 'voice_*.jpg' 2>/dev/null | sort > "$OUT_DIR/photos_before.txt"
tail -8 "$OUT_DIR/photos_before.txt" || true
echo

echo "==================== 4. run once live ===================="
echo "现在只说命令，不需要说鲁班猫。"
echo "录音开始后请说：看一下画面"
echo
echo "[RUN] timeout ${RUN_TIMEOUT}s $PY voice_assistant.py once --seconds $CMD_SECONDS"
echo

set +e
timeout "$RUN_TIMEOUT" stdbuf -oL -eL \
  "$PY" voice_assistant.py once \
  --seconds "$CMD_SECONDS" \
  > >(tee "$STDOUT") \
  2> >(tee "$STDERR" >&2)

RC=$?
set -e

echo
echo "once_return_code: $RC"
echo

echo "==================== 5. after photo list ===================="
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

echo "==================== 6. parse result ===================="
RECOGNIZED_TEXT=$(grep -E "识别文本[:：]" "$STDOUT" | tail -1 | sed 's/.*识别文本[:：][[:space:]]*//' || true)
echo "$RECOGNIZED_TEXT" > "$OUT_DIR/recognized_text.txt"

awk '
  BEGIN{flag=0}
  /正在调用 Qwen demo/ {flag=1; next}
  /将使用整段 TTS/ {next}
  flag {print}
' "$STDOUT" > "$OUT_DIR/qwen_answer_raw.txt" 2>/dev/null || true

sed '/^[[:space:]]*$/d' "$OUT_DIR/qwen_answer_raw.txt" > "$OUT_DIR/qwen_answer.txt" || true

QWEN_ANSWER_CHARS=$(python3 - <<PY
from pathlib import Path
p = Path("$OUT_DIR/qwen_answer.txt")
s = p.read_text(errors="ignore") if p.exists() else ""
print(len(s.strip()))
PY
)

UNDERRUN_COUNT=$(grep -R "underrun" "$STDERR" "$STDOUT" 2>/dev/null | wc -l | tr -d ' ')

echo "recognized_text:"
cat "$OUT_DIR/recognized_text.txt"
echo
echo "qwen_answer_chars: $QWEN_ANSWER_CHARS"
echo
echo "qwen_answer:"
cat "$OUT_DIR/qwen_answer.txt"
echo

echo "==================== 7. abnormal scan ===================="
grep -nEi "error|failed|Traceback|ModuleNotFound|ImportError|Unable to install hw params|underrun|Broken pipe|No such file|not found|cannot|timeout|killed|oom|segmentation|exception" \
  "$STDOUT" "$STDERR" "$LOG" > "$OUT_DIR/abnormal.txt" 2>/dev/null || true
cat "$OUT_DIR/abnormal.txt"
echo

echo "==================== 8. summary ===================="
echo "out_dir          : $OUT_DIR"
echo "once_return_code : $RC"
echo "recognized_text  : $RECOGNIZED_TEXT"
echo "new_photo_count  : $NEW_PHOTO_COUNT"
echo "new_photo_path   : $NEW_PHOTO_PATH"
echo "qwen_answer_chars: $QWEN_ANSWER_CHARS"
echo "underrun_count   : $UNDERRUN_COUNT"

if [ "$RC" = "0" ] \
   && [ -n "$RECOGNIZED_TEXT" ] \
   && [ "$NEW_PHOTO_COUNT" -gt 0 ] \
   && [ "$QWEN_ANSWER_CHARS" -gt 0 ] \
   && [ "$UNDERRUN_COUNT" = "0" ]; then
  echo "[RESULT] Experiment 09.4d PASSED_ONCE_PHOTO_QA_LIVE"
elif [ "$RC" = "124" ]; then
  echo "[RESULT] Experiment 09.4d TIMEOUT_NEEDS_STAGE_CHECK"
else
  echo "[RESULT] Experiment 09.4d FAILED_OR_NEEDS_CHECK"
fi

echo
echo "log saved to: $LOG"
