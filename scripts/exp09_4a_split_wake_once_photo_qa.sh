#!/usr/bin/env bash
set -u

OUT_DIR="${1:-output/exp09_4a_split_wake_once_photo_qa_manual}"
WAKE_TIMEOUT="${2:-25}"
CMD_SECONDS="${3:-5}"
ONCE_TIMEOUT="${4:-130}"

mkdir -p "$OUT_DIR"

PY=".venv/bin/python"
if [ ! -x "$PY" ]; then
  PY="$(command -v python3)"
fi

export PYTHONPATH="$(pwd)/.python_packages:$(pwd):${PYTHONPATH:-}"

LOG="$OUT_DIR/run.log"
WAKE_STDOUT="$OUT_DIR/wake_stdout.txt"
WAKE_STDERR="$OUT_DIR/wake_stderr.txt"
ONCE_STDOUT="$OUT_DIR/once_stdout.txt"
ONCE_STDERR="$OUT_DIR/once_stderr.txt"

exec > >(tee "$LOG") 2>&1

echo "============================================================"
echo " Experiment 09.4a: split wake -> once photo QA"
echo "============================================================"
echo "time         : $(date '+%Y-%m-%d %H:%M:%S')"
echo "workdir      : $(pwd)"
echo "out_dir      : $OUT_DIR"
echo "python       : $PY"
echo "wake_timeout : $WAKE_TIMEOUT"
echo "cmd_seconds  : $CMD_SECONDS"
echo "once_timeout : $ONCE_TIMEOUT"
echo

echo "==================== 1. before photo list ===================="
find /home/cat/图片 -maxdepth 1 -type f -name 'voice_*.jpg' 2>/dev/null | sort > "$OUT_DIR/photos_before.txt"
tail -8 "$OUT_DIR/photos_before.txt" || true
echo

echo "==================== 2. realtime KWS wake ===================="
echo "现在请在 ${WAKE_TIMEOUT}s 内说唤醒词：鲁班猫"
echo "[RUN] $PY voice_assistant.py wake --mode kws --timeout $WAKE_TIMEOUT"
echo

timeout "$((WAKE_TIMEOUT + 8))" \
  "$PY" voice_assistant.py wake \
  --mode kws \
  --timeout "$WAKE_TIMEOUT" \
  > "$WAKE_STDOUT" 2> "$WAKE_STDERR"

WAKE_RC=$?
WAKE_TEXT=$(cat "$WAKE_STDOUT" 2>/dev/null | tr -d '\r\n ')

echo "wake_return_code: $WAKE_RC"
echo "wake_text       : $WAKE_TEXT"
echo

echo "----- wake stdout -----"
cat "$WAKE_STDOUT" || true
echo

echo "----- wake stderr -----"
cat "$WAKE_STDERR" || true
echo

if [ "$WAKE_RC" != "0" ] || [ -z "$WAKE_TEXT" ]; then
  echo "[RESULT] Experiment 09.4a FAILED_AT_WAKE"
  exit 0
fi

echo "==================== 3. once photo QA ===================="
echo "已经唤醒成功。"
echo "接下来进入 once 命令录音，录音开始后请说：看一下画面"
echo "[RUN] timeout ${ONCE_TIMEOUT}s $PY voice_assistant.py once --seconds $CMD_SECONDS"
echo

timeout "$ONCE_TIMEOUT" stdbuf -oL -eL \
  "$PY" voice_assistant.py once \
  --seconds "$CMD_SECONDS" \
  > "$ONCE_STDOUT" 2> "$ONCE_STDERR"

ONCE_RC=$?

echo "once_return_code: $ONCE_RC"
echo

echo "==================== 4. after photo list ===================="
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

echo "==================== 5. stdout key lines ===================="
grep -nE "识别文本|正在调用|Qwen|将使用|整段|TTS|拍照|照片|画面|摄像头|图片|视觉|助手|回答" \
  "$ONCE_STDOUT" || true
echo

echo "==================== 6. stderr key lines ===================="
grep -nE "Recording|underrun|error|failed|Traceback|ModuleNotFound|Unable|Broken pipe|No such|not found|cannot" \
  "$ONCE_STDERR" || true
echo

echo "==================== 7. full once stdout ===================="
cat "$ONCE_STDOUT" || true
echo

echo "==================== 8. full once stderr ===================="
cat "$ONCE_STDERR" || true
echo

echo "==================== 9. abnormal scan ===================="
grep -nEi "error|failed|Traceback|ModuleNotFound|ImportError|Unable to install hw params|underrun|Broken pipe|No such file|not found|cannot|killed|oom|segmentation|exception" \
  "$WAKE_STDOUT" "$WAKE_STDERR" "$ONCE_STDOUT" "$ONCE_STDERR" > "$OUT_DIR/abnormal.txt" 2>/dev/null || true
cat "$OUT_DIR/abnormal.txt"
echo

echo "==================== 10. parse result ===================="
RECOGNIZED_TEXT=$(grep -E "识别文本[:：]" "$ONCE_STDOUT" | tail -1 | sed 's/.*识别文本[:：][[:space:]]*//' || true)
echo "$RECOGNIZED_TEXT" > "$OUT_DIR/recognized_text.txt"

awk '
  BEGIN{flag=0}
  /正在调用 Qwen demo/ {flag=1; next}
  /将使用整段 TTS/ {next}
  flag {print}
' "$ONCE_STDOUT" > "$OUT_DIR/qwen_answer_raw.txt" 2>/dev/null || true

sed '/^[[:space:]]*$/d' "$OUT_DIR/qwen_answer_raw.txt" > "$OUT_DIR/qwen_answer.txt" || true

QWEN_ANSWER_CHARS=$(python3 - <<PY
from pathlib import Path
p = Path("$OUT_DIR/qwen_answer.txt")
s = p.read_text(errors="ignore") if p.exists() else ""
print(len(s.strip()))
PY
)

UNDERRUN_COUNT=$(grep -R "underrun" "$ONCE_STDERR" "$ONCE_STDOUT" 2>/dev/null | wc -l | tr -d ' ')

echo "recognized_text:"
cat "$OUT_DIR/recognized_text.txt"
echo
echo "qwen_answer_chars: $QWEN_ANSWER_CHARS"
echo
echo "qwen_answer:"
cat "$OUT_DIR/qwen_answer.txt"
echo

echo "==================== 11. summary ===================="
echo "out_dir          : $OUT_DIR"
echo "wake_return_code : $WAKE_RC"
echo "wake_text        : $WAKE_TEXT"
echo "once_return_code : $ONCE_RC"
echo "recognized_text  : $RECOGNIZED_TEXT"
echo "new_photo_count  : $NEW_PHOTO_COUNT"
echo "new_photo_path   : $NEW_PHOTO_PATH"
echo "qwen_answer_chars: $QWEN_ANSWER_CHARS"
echo "underrun_count   : $UNDERRUN_COUNT"

if [ "$WAKE_RC" = "0" ] \
   && [ "$WAKE_TEXT" = "鲁班猫" ] \
   && [ "$ONCE_RC" = "0" ] \
   && [ -n "$RECOGNIZED_TEXT" ] \
   && [ "$NEW_PHOTO_COUNT" -gt 0 ] \
   && [ "$QWEN_ANSWER_CHARS" -gt 0 ] \
   && [ "$UNDERRUN_COUNT" = "0" ]; then
  echo "[RESULT] Experiment 09.4a PASSED_SPLIT_WAKE_ONCE_PHOTO_QA"
elif [ "$ONCE_RC" = "0" ] && [ "$NEW_PHOTO_COUNT" = "0" ]; then
  echo "[RESULT] Experiment 09.4a NEEDS_CHECK_NO_PHOTO_TRIGGER"
else
  echo "[RESULT] Experiment 09.4a FAILED_OR_NEEDS_CHECK"
fi

echo
echo "log saved to: $LOG"
