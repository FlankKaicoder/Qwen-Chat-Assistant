#!/usr/bin/env bash

set -u

PROJECT_DIR="/home/cat/ai/qwen3vl2b"
cd "$PROJECT_DIR" || exit 1

OUT_DIR="${1:-output/exp10_2g_full_visual_concise_tts_$(date +%Y%m%d_%H%M%S)}"
SESSION_DIR="$OUT_DIR/session"

mkdir -p "$SESSION_DIR"

PYTHON_BIN="$PROJECT_DIR/.venv/bin/python"

export PYTHONPATH="$PROJECT_DIR:$PROJECT_DIR/.python_packages${PYTHONPATH:+:$PYTHONPATH}"

STDOUT_LOG="$OUT_DIR/stdout.log"
STDERR_LOG="$OUT_DIR/stderr.log"
RUN_LOG="$OUT_DIR/run.log"

echo "============================================================" | tee "$RUN_LOG"
echo " Experiment 10.2g: Full Visual Concise TTS Loop" | tee -a "$RUN_LOG"
echo "============================================================" | tee -a "$RUN_LOG"
echo "time        : $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$RUN_LOG"
echo "out_dir     : $OUT_DIR" | tee -a "$RUN_LOG"
echo "session_dir : $SESSION_DIR" | tee -a "$RUN_LOG"
echo | tee -a "$RUN_LOG"

echo "交互说明：" | tee -a "$RUN_LOG"
echo "1. 出现“请说唤醒词”后，说：鲁班猫" | tee -a "$RUN_LOG"
echo "2. 出现“请现在说出命令”后，靠近麦克风清晰说：" | tee -a "$RUN_LOG"
echo "   拍照看一下画面" | tee -a "$RUN_LOG"
echo | tee -a "$RUN_LOG"

START_EPOCH=$(date +%s)

set +e

timeout --signal=INT --kill-after=10 180 \
"$PYTHON_BIN" voice_assistant.py listen-controlled \
    --wake-mode kws \
    --wake-timeout 25 \
    --seconds 5 \
    --prepare-delay 1.0 \
    --answer-mode concise \
    --answer-max-chars 80 \
    --concise-max-new-tokens 128 \
    --out-dir "$SESSION_DIR" \
    > >(tee "$STDOUT_LOG") \
    2> >(tee "$STDERR_LOG" >&2)

CONTROLLED_RC=$?

set -e

END_EPOCH=$(date +%s)
WALL_ELAPSED=$((END_EPOCH - START_EPOCH))

echo | tee -a "$RUN_LOG"
echo "controlled_return_code: $CONTROLLED_RC" | tee -a "$RUN_LOG"
echo "wall_elapsed_seconds  : $WALL_ELAPSED" | tee -a "$RUN_LOG"

STATUS=""
RECOGNIZED_TEXT=""
PHOTO_INTENT_HINT=0
NEW_PHOTO_COUNT=0
NEW_PHOTO_PATH=""
ANSWER_CHARS=0
PIPELINE_ELAPSED=""
TTS_ELAPSED=""
TOTAL_ELAPSED=""

if [ -f "$SESSION_DIR/summary.json" ]; then
    eval "$(
        "$PYTHON_BIN" - "$SESSION_DIR/summary.json" <<'PY'
import json
import shlex
import sys
from pathlib import Path

data = json.loads(
    Path(sys.argv[1]).read_text(encoding="utf-8")
)

values = {
    "STATUS": data.get("status", ""),
    "RECOGNIZED_TEXT": data.get("recognized_text", ""),
    "PHOTO_INTENT_HINT": data.get("photo_intent_hint", 0),
    "NEW_PHOTO_COUNT": data.get("new_photo_count", 0),
    "NEW_PHOTO_PATH": data.get("new_photo_path", ""),
    "ANSWER_CHARS": data.get("answer_chars", 0),
    "PIPELINE_ELAPSED": data.get(
        "pipeline_elapsed_seconds",
        "",
    ),
    "TTS_ELAPSED": data.get(
        "tts_elapsed_seconds",
        "",
    ),
    "TOTAL_ELAPSED": data.get(
        "elapsed_seconds",
        "",
    ),
}

for key, value in values.items():
    print(f"{key}={shlex.quote(str(value))}")
PY
    )"
fi

UNDERRUN_COUNT=$(
    grep -hci "underrun" \
        "$STDOUT_LOG" \
        "$STDERR_LOG" \
        2>/dev/null \
    | awk '{sum += $1} END {print sum + 0}'
)

BAD_ANSWER_COUNT=0

if [ -f "$SESSION_DIR/qwen_answer.txt" ]; then
    BAD_ANSWER_COUNT=$(
        grep -Ec \
          "无法提供|图像信息不完整|提供更多上下文|无法查看图片" \
          "$SESSION_DIR/qwen_answer.txt" || true
    )
fi

ps -eo pid,ppid,stat,etime,cmd \
    | grep -E \
      "voice_assistant.py|capture-photo.sh|v4l2-ctl|ffmpeg|arecord|aplay|/demo|imgenc" \
    | grep -v -E \
      "grep|exp10_2g_full_visual_concise_tts" \
    > "$OUT_DIR/residual_processes.txt" || true

RESIDUAL_COUNT=$(
    wc -l < "$OUT_DIR/residual_processes.txt"
)

if [ -n "$NEW_PHOTO_PATH" ] \
  && [ -f "$NEW_PHOTO_PATH" ]; then

    ffprobe -v error \
        -select_streams v:0 \
        -show_entries \
          stream=codec_name,width,height,pix_fmt \
        -of default=noprint_wrappers=1 \
        "$NEW_PHOTO_PATH" \
        > "$OUT_DIR/photo_ffprobe.txt" \
        2>&1 || true
fi

grep -nEi \
"error|failed|traceback|timeout|timed out|broken pipe|killed|oom" \
"$STDOUT_LOG" "$STDERR_LOG" \
> "$OUT_DIR/abnormal.txt" || true

{
    echo "out_dir                 : $OUT_DIR"
    echo "session_dir             : $SESSION_DIR"
    echo "controlled_return_code  : $CONTROLLED_RC"
    echo "status                  : $STATUS"
    echo "recognized_text         : $RECOGNIZED_TEXT"
    echo "photo_intent_hint       : $PHOTO_INTENT_HINT"
    echo "new_photo_count         : $NEW_PHOTO_COUNT"
    echo "new_photo_path          : $NEW_PHOTO_PATH"
    echo "answer_chars            : $ANSWER_CHARS"
    echo "pipeline_elapsed_seconds: $PIPELINE_ELAPSED"
    echo "tts_elapsed_seconds     : $TTS_ELAPSED"
    echo "total_elapsed_seconds   : $TOTAL_ELAPSED"
    echo "wall_elapsed_seconds    : $WALL_ELAPSED"
    echo "underrun_count          : $UNDERRUN_COUNT"
    echo "bad_answer_count        : $BAD_ANSWER_COUNT"
    echo "residual_process_count  : $RESIDUAL_COUNT"
} | tee "$OUT_DIR/summary.txt"

TTS_POSITIVE=$(
    "$PYTHON_BIN" - "$TTS_ELAPSED" <<'PY'
import sys

try:
    value = float(sys.argv[1])
except Exception:
    value = 0.0

print(1 if value > 0 else 0)
PY
)

if [ "$CONTROLLED_RC" -eq 0 ] \
  && [ "$STATUS" = "PASSED" ] \
  && [ "$PHOTO_INTENT_HINT" -eq 1 ] \
  && [ "$NEW_PHOTO_COUNT" -ge 1 ] \
  && [ "$ANSWER_CHARS" -gt 0 ] \
  && [ "$ANSWER_CHARS" -le 150 ] \
  && [ "$TTS_POSITIVE" -eq 1 ] \
  && [ "$UNDERRUN_COUNT" -eq 0 ] \
  && [ "$BAD_ANSWER_COUNT" -eq 0 ] \
  && [ "$RESIDUAL_COUNT" -eq 0 ]; then

    echo "[RESULT] Experiment 10.2g PASSED_FULL_CONCISE_VISUAL_TTS." \
        | tee -a "$RUN_LOG"
else
    echo "[RESULT] Experiment 10.2g FAILED_OR_NEEDS_CHECK." \
        | tee -a "$RUN_LOG"
fi
