#!/usr/bin/env bash
set -u

OUT_DIR="${1:-output/exp09_3_listen_kws_once_text_qa_manual}"
WAKE_TIMEOUT="${2:-25}"
CMD_SECONDS="${3:-5}"
RUN_TIMEOUT="${4:-130}"

mkdir -p "$OUT_DIR"

PY=".venv/bin/python"
if [ ! -x "$PY" ]; then
  PY="$(command -v python3)"
fi

export PYTHONPATH="$(pwd)/.python_packages:$(pwd):${PYTHONPATH:-}"

LOG="$OUT_DIR/run.log"
STDOUT="$OUT_DIR/listen_stdout.txt"
STDERR="$OUT_DIR/listen_stderr.txt"

exec > >(tee "$LOG") 2>&1

echo "============================================================"
echo " Experiment 09.3: listen KWS -> once text QA"
echo "============================================================"
echo "time         : $(date '+%Y-%m-%d %H:%M:%S')"
echo "workdir      : $(pwd)"
echo "out_dir      : $OUT_DIR"
echo "python       : $PY"
echo "wake_timeout : $WAKE_TIMEOUT"
echo "cmd_seconds  : $CMD_SECONDS"
echo "run_timeout  : $RUN_TIMEOUT"
echo

echo "==================== 1. instruction ===================="
echo "本实验步骤："
echo "1) 运行后先说唤醒词：鲁班猫"
echo "2) 唤醒后进入命令录音，请说：你是谁"
echo "3) 等待 Qwen 回答并听 TTS 播放"
echo

echo "==================== 2. config key ===================="
grep -nE "mic_device|speaker_device|sample_rate|channels|input_channel|wake_input_gain|asr_input_gain|keywords_score|keywords_threshold|command_seconds" config/default.yaml || true
echo

echo "==================== 3. before photo list ===================="
find /home/cat/图片 -maxdepth 1 -type f -name 'voice_*.jpg' 2>/dev/null | sort > "$OUT_DIR/photos_before.txt"
tail -5 "$OUT_DIR/photos_before.txt" || true
echo

echo "==================== 4. run listen ===================="
echo "[RUN] timeout ${RUN_TIMEOUT}s $PY voice_assistant.py listen --wake-mode kws --wake-timeout $WAKE_TIMEOUT --seconds $CMD_SECONDS"
echo

timeout "$RUN_TIMEOUT" stdbuf -oL -eL \
  "$PY" voice_assistant.py listen \
  --wake-mode kws \
  --wake-timeout "$WAKE_TIMEOUT" \
  --seconds "$CMD_SECONDS" \
  > "$STDOUT" 2> "$STDERR"

RC=$?

echo
echo "listen_return_code: $RC"
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
  ffprobe -hide_banner -v error \
    -select_streams v:0 \
    -show_entries stream=codec_name,width,height,pix_fmt \
    -of default=noprint_wrappers=1 \
    "$NEW_PHOTO_PATH" > "$OUT_DIR/photo_ffprobe.txt" 2>&1 || true
  cat "$OUT_DIR/photo_ffprobe.txt"
fi
echo

echo "==================== 6. stdout key lines ===================="
grep -nE "唤醒|wake|keyword|识别文本|正在调用|Qwen|将使用|整段|TTS|拍照|画面|摄像头|助手|回答|鲁班猫" "$STDOUT" || true
echo

echo "==================== 7. stderr key lines ===================="
grep -nE "Recording|underrun|error|failed|Traceback|ModuleNotFound|Unable|Broken pipe|No such|not found|cannot" "$STDERR" || true
echo

echo "==================== 8. full stdout tail ===================="
tail -220 "$STDOUT" || true
echo

echo "==================== 9. full stderr tail ===================="
tail -220 "$STDERR" || true
echo

echo "==================== 10. abnormal scan ===================="
grep -nEi "error|failed|Traceback|ModuleNotFound|ImportError|Unable to install hw params|underrun|Broken pipe|No such file|not found|cannot|killed|oom|segmentation|exception" \
  "$STDOUT" "$STDERR" > "$OUT_DIR/abnormal.txt" 2>/dev/null || true
cat "$OUT_DIR/abnormal.txt"
echo

echo "==================== 11. summary ===================="
UNDERRUN_COUNT=$(grep -R "underrun" "$STDERR" "$STDOUT" 2>/dev/null | wc -l | tr -d ' ')

RECOGNIZED_TEXT=$(grep -E "识别文本[:：]" "$STDOUT" | tail -1 | sed 's/.*识别文本[:：][[:space:]]*//' || true)

QWEN_ANSWER_CHARS=$(awk '
  BEGIN{flag=0; n=0}
  /正在调用 Qwen demo/ {flag=1; next}
  /将使用整段 TTS/ {next}
  flag {n += length($0)}
  END{print n}
' "$STDOUT" 2>/dev/null || echo 0)

echo "out_dir           : $OUT_DIR"
echo "listen_return_code: $RC"
echo "recognized_text   : $RECOGNIZED_TEXT"
echo "qwen_answer_chars : $QWEN_ANSWER_CHARS"
echo "new_photo_count   : $NEW_PHOTO_COUNT"
echo "new_photo_path    : $NEW_PHOTO_PATH"
echo "underrun_count    : $UNDERRUN_COUNT"

if [ "$RC" = "0" ] && [ -n "$RECOGNIZED_TEXT" ] && [ "$QWEN_ANSWER_CHARS" -gt 0 ] && [ "$UNDERRUN_COUNT" = "0" ]; then
  echo "[RESULT] Experiment 09.3 PASSED_LISTEN_KWS_TEXT_QA"
elif [ "$RC" = "124" ]; then
  echo "[RESULT] Experiment 09.3 TIMEOUT_OR_NO_WAKE"
else
  echo "[RESULT] Experiment 09.3 FAILED_OR_NEEDS_CHECK"
fi

echo
echo "log saved to: $LOG"
