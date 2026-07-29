#!/usr/bin/env bash

set -u

PROJECT_DIR="/home/cat/ai/qwen3vl2b"
cd "$PROJECT_DIR" || {
    echo "[FAIL] cannot enter project directory: $PROJECT_DIR"
    return 1 2>/dev/null || exit 1
}

PYTHON_BIN="$PROJECT_DIR/.venv/bin/python"

export PYTHONPATH="$PROJECT_DIR:$PROJECT_DIR/.python_packages${PYTHONPATH:+:$PYTHONPATH}"

if [ ! -x "$PYTHON_BIN" ]; then
    echo "[FAIL] project Python wrapper is missing or not executable: $PYTHON_BIN"
    return 1 2>/dev/null || exit 1
fi

OUT_DIR="${1:-output/exp10_1b_live_controlled_session_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT_DIR"

STDOUT_LOG="$OUT_DIR/stdout.log"
STDERR_LOG="$OUT_DIR/stderr.log"
RUN_LOG="$OUT_DIR/run.log"
SESSION_DIR="$OUT_DIR/session"

mkdir -p "$SESSION_DIR"

echo "============================================================" | tee "$RUN_LOG"
echo " Experiment 10.1b: Live Controlled Session" | tee -a "$RUN_LOG"
echo "============================================================" | tee -a "$RUN_LOG"
echo "time        : $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$RUN_LOG"
echo "out_dir     : $OUT_DIR" | tee -a "$RUN_LOG"
echo "session_dir : $SESSION_DIR" | tee -a "$RUN_LOG"
echo | tee -a "$RUN_LOG"

echo "交互说明：" | tee -a "$RUN_LOG"
echo "1. 看到 [PROMPT] 请说唤醒词 后，说：鲁班猫" | tee -a "$RUN_LOG"
echo "2. 看到 [PROMPT] 请现在说出命令 后，说：拍照，看一下画面" | tee -a "$RUN_LOG"
echo | tee -a "$RUN_LOG"

start_epoch=$(date +%s)

set +e

timeout --signal=INT --kill-after=10 240 \
    "$PYTHON_BIN" voice_assistant.py listen-controlled \
        --wake-mode kws \
        --wake-timeout 25 \
        --seconds 5 \
        --prepare-delay 1.0 \
        --out-dir "$SESSION_DIR" \
    > >(tee "$STDOUT_LOG") \
    2> >(tee "$STDERR_LOG" >&2)

controlled_return_code=$?

set -e

end_epoch=$(date +%s)
elapsed_seconds=$((end_epoch - start_epoch))

echo | tee -a "$RUN_LOG"
echo "========== process result ==========" | tee -a "$RUN_LOG"
echo "controlled_return_code: $controlled_return_code" | tee -a "$RUN_LOG"
echo "elapsed_seconds        : $elapsed_seconds" | tee -a "$RUN_LOG"

underrun_count=$(
    grep -hci "underrun" "$STDOUT_LOG" "$STDERR_LOG" 2>/dev/null \
    | awk '{s += $1} END {print s + 0}'
)

if [ -f "$SESSION_DIR/summary.txt" ]; then
    echo | tee -a "$RUN_LOG"
    echo "========== session summary ==========" | tee -a "$RUN_LOG"
    cat "$SESSION_DIR/summary.txt" | tee -a "$RUN_LOG"
fi

recognized_text=""
new_photo_count=0
new_photo_path=""
answer_chars=0
session_status=""

if [ -f "$SESSION_DIR/summary.json" ]; then
    eval "$(
        "$PYTHON_BIN" - "$SESSION_DIR/summary.json" <<'PY'
import json
import shlex
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))

values = {
    "recognized_text": data.get("recognized_text", ""),
    "new_photo_count": data.get("new_photo_count", 0),
    "new_photo_path": data.get("new_photo_path", ""),
    "answer_chars": data.get("answer_chars", 0),
    "session_status": data.get("status", ""),
}

for key, value in values.items():
    print(f"{key}={shlex.quote(str(value))}")
PY
    )"
fi

echo | tee -a "$RUN_LOG"
echo "========== parsed result ==========" | tee -a "$RUN_LOG"
echo "session_status        : $session_status" | tee -a "$RUN_LOG"
echo "recognized_text       : $recognized_text" | tee -a "$RUN_LOG"
echo "new_photo_count       : $new_photo_count" | tee -a "$RUN_LOG"
echo "new_photo_path        : $new_photo_path" | tee -a "$RUN_LOG"
echo "answer_chars          : $answer_chars" | tee -a "$RUN_LOG"
echo "underrun_count        : $underrun_count" | tee -a "$RUN_LOG"

if [ -n "$new_photo_path" ] && [ -f "$new_photo_path" ]; then
    ffprobe -v error \
        -select_streams v:0 \
        -show_entries stream=codec_name,width,height,pix_fmt \
        -of default=noprint_wrappers=1 \
        "$new_photo_path" \
        > "$OUT_DIR/photo_ffprobe.txt" 2>&1 || true
fi

ps -eo pid,ppid,stat,etime,cmd \
    | grep -E \
      "voice_assistant.py|capture-photo.sh|v4l2-ctl|ffmpeg|arecord|aplay|/demo|imgenc" \
    | grep -v -E "grep|exp10_1b_live_controlled_session" \
    > "$OUT_DIR/residual_processes.txt" || true

residual_process_count=$(wc -l < "$OUT_DIR/residual_processes.txt")

grep -nEi \
"error|failed|traceback|timeout|timed out|killed|segmentation|oom|broken pipe|unable to install" \
"$STDOUT_LOG" "$STDERR_LOG" \
> "$OUT_DIR/abnormal.txt" || true

{
    echo "out_dir               : $OUT_DIR"
    echo "session_dir           : $SESSION_DIR"
    echo "controlled_return_code: $controlled_return_code"
    echo "session_status        : $session_status"
    echo "recognized_text       : $recognized_text"
    echo "new_photo_count       : $new_photo_count"
    echo "new_photo_path        : $new_photo_path"
    echo "answer_chars          : $answer_chars"
    echo "underrun_count        : $underrun_count"
    echo "residual_process_count: $residual_process_count"
    echo "elapsed_seconds       : $elapsed_seconds"
} | tee "$OUT_DIR/summary.txt"

echo | tee -a "$RUN_LOG"

if [ "$controlled_return_code" -eq 0 ] \
  && [ "$session_status" = "PASSED" ] \
  && [ -n "$recognized_text" ] \
  && [ "$new_photo_count" -ge 1 ] \
  && [ "$answer_chars" -gt 0 ] \
  && [ "$underrun_count" -eq 0 ] \
  && [ "$residual_process_count" -eq 0 ]; then

    echo "[RESULT] Experiment 10.1b PASSED_CONTROLLED_CLI." \
        | tee -a "$RUN_LOG"
else
    echo "[RESULT] Experiment 10.1b FAILED_OR_NEEDS_CHECK." \
        | tee -a "$RUN_LOG"
fi
