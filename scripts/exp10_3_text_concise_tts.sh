#!/usr/bin/env bash

set -u

PROJECT_DIR="/home/cat/ai/qwen3vl2b"
cd "$PROJECT_DIR" || exit 1

OUT_DIR="${1:-output/exp10_3_text_concise_tts_$(date +%Y%m%d_%H%M%S)}"
SESSION_DIR="$OUT_DIR/session"

mkdir -p "$SESSION_DIR"

PYTHON_BIN="$PROJECT_DIR/.venv/bin/python"

export PYTHONPATH="$PROJECT_DIR:$PROJECT_DIR/.python_packages${PYTHONPATH:+:$PYTHONPATH}"

STDOUT_LOG="$OUT_DIR/stdout.log"
STDERR_LOG="$OUT_DIR/stderr.log"
RUN_LOG="$OUT_DIR/run.log"

echo "============================================================" | tee "$RUN_LOG"
echo " Experiment 10.3: Text Concise TTS Loop" | tee -a "$RUN_LOG"
echo "============================================================" | tee -a "$RUN_LOG"
echo "time        : $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$RUN_LOG"
echo "out_dir     : $OUT_DIR" | tee -a "$RUN_LOG"
echo "session_dir : $SESSION_DIR" | tee -a "$RUN_LOG"
echo | tee -a "$RUN_LOG"

echo "交互说明：" | tee -a "$RUN_LOG"
echo "1. 出现“请说唤醒词”后，说：鲁班猫" | tee -a "$RUN_LOG"
echo "2. 出现“请现在说出命令”后，清晰说：你是谁" | tee -a "$RUN_LOG"
echo "3. 本轮不应该启动摄像头。" | tee -a "$RUN_LOG"
echo | tee -a "$RUN_LOG"

START_EPOCH=$(date +%s)

set +e

timeout --signal=INT --kill-after=10 150 \
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

WALL_ELAPSED=$(($(date +%s) - START_EPOCH))

STATUS=""
RECOGNIZED_TEXT=""
PHOTO_INTENT_HINT=0
NEW_PHOTO_COUNT=0
ANSWER_CHARS=0
PIPELINE_ELAPSED=""
TTS_ELAPSED=""
TOTAL_ELAPSED=""
AUDIO_MAX_DBFS=""

if [ -f "$SESSION_DIR/summary.json" ]; then
    eval "$(
        "$PYTHON_BIN" - \
            "$SESSION_DIR/summary.json" \
            "$SESSION_DIR/audio_stats.json" <<'PY'
import json
import shlex
import sys
from pathlib import Path

summary = json.loads(
    Path(sys.argv[1]).read_text(encoding="utf-8")
)

audio = {}

if Path(sys.argv[2]).exists():
    audio = json.loads(
        Path(sys.argv[2]).read_text(encoding="utf-8")
    )

recognized = str(summary.get("recognized_text", ""))

values = {
    "STATUS": summary.get("status", ""),
    "RECOGNIZED_TEXT": recognized,
    "TEXT_INTENT_OK": int(
        "你" in recognized and "谁" in recognized
    ),
    "PHOTO_INTENT_HINT": summary.get(
        "photo_intent_hint",
        0,
    ),
    "NEW_PHOTO_COUNT": summary.get(
        "new_photo_count",
        0,
    ),
    "ANSWER_CHARS": summary.get(
        "answer_chars",
        0,
    ),
    "PIPELINE_ELAPSED": summary.get(
        "pipeline_elapsed_seconds",
        "",
    ),
    "TTS_ELAPSED": summary.get(
        "tts_elapsed_seconds",
        "",
    ),
    "TOTAL_ELAPSED": summary.get(
        "elapsed_seconds",
        "",
    ),
    "AUDIO_MAX_DBFS": audio.get(
        "max_volume_dbfs",
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

ps -eo pid,ppid,stat,etime,cmd \
    | grep -E \
      "voice_assistant.py|capture-photo.sh|v4l2-ctl|ffmpeg|arecord|aplay|/demo|imgenc" \
    | grep -v -E \
      "grep|exp10_3_text_concise_tts" \
    > "$OUT_DIR/residual_processes.txt" || true

RESIDUAL_COUNT=$(
    wc -l < "$OUT_DIR/residual_processes.txt"
)

grep -nEi \
"error|failed|traceback|timed out|broken pipe|killed|oom|underrun" \
"$STDOUT_LOG" "$STDERR_LOG" \
> "$OUT_DIR/abnormal.txt" || true

{
    echo "out_dir                 : $OUT_DIR"
    echo "session_dir             : $SESSION_DIR"
    echo "controlled_return_code  : $CONTROLLED_RC"
    echo "status                  : $STATUS"
    echo "recognized_text         : $RECOGNIZED_TEXT"
    echo "text_intent_ok          : ${TEXT_INTENT_OK:-0}"
    echo "photo_intent_hint       : $PHOTO_INTENT_HINT"
    echo "new_photo_count         : $NEW_PHOTO_COUNT"
    echo "answer_chars            : $ANSWER_CHARS"
    echo "pipeline_elapsed_seconds: $PIPELINE_ELAPSED"
    echo "tts_elapsed_seconds     : $TTS_ELAPSED"
    echo "total_elapsed_seconds   : $TOTAL_ELAPSED"
    echo "wall_elapsed_seconds    : $WALL_ELAPSED"
    echo "audio_max_volume_dbfs   : $AUDIO_MAX_DBFS"
    echo "underrun_count          : $UNDERRUN_COUNT"
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
  && [ "${TEXT_INTENT_OK:-0}" -eq 1 ] \
  && [ "$PHOTO_INTENT_HINT" -eq 0 ] \
  && [ "$NEW_PHOTO_COUNT" -eq 0 ] \
  && [ "$ANSWER_CHARS" -gt 0 ] \
  && [ "$ANSWER_CHARS" -le 150 ] \
  && [ "$TTS_POSITIVE" -eq 1 ] \
  && [ "$UNDERRUN_COUNT" -eq 0 ] \
  && [ "$RESIDUAL_COUNT" -eq 0 ]; then

    echo "[RESULT] Experiment 10.3 PASSED_TEXT_CONCISE_TTS." \
        | tee -a "$RUN_LOG"
else
    echo "[RESULT] Experiment 10.3 FAILED_OR_NEEDS_CHECK." \
        | tee -a "$RUN_LOG"
fi
