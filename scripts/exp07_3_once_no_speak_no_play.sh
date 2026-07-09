#!/usr/bin/env bash

set -u

PROJECT_DIR="/home/cat/ai/qwen3vl2b"
cd "$PROJECT_DIR" || exit 1

OUT="${1:-output/exp07_3_once_no_speak_no_play_$(date +%Y%m%d_%H%M%S)}"
REC_SECONDS="${2:-6}"

mkdir -p "$OUT"

LOG="$OUT/run.log"
exec > >(tee "$LOG") 2>&1

export PYTHONPATH="$PROJECT_DIR:$PROJECT_DIR/.python_packages:${PYTHONPATH:-}"
export LD_LIBRARY_PATH="$PROJECT_DIR:${LD_LIBRARY_PATH:-}"

PY="$PROJECT_DIR/.venv/bin/python"
if [ ! -x "$PY" ]; then
    PY="$(command -v python3)"
fi

echo "============================================================"
echo " Experiment 07.3: official once --no-speak --no-play"
echo "============================================================"
echo "time        : $(date '+%Y-%m-%d %H:%M:%S')"
echo "project_dir : $PROJECT_DIR"
echo "out_dir     : $OUT"
echo "python      : $PY"
echo "rec_seconds : $REC_SECONDS"
echo

echo "==================== 1. run once ===================="
echo "[INFO] 请在倒计时结束后说一句短问题，例如：请用一句话介绍自己"
echo

for i in 3 2 1; do
    echo "record starts in $i ..."
    sleep 1
done

echo "[RUN] voice_assistant.py once --seconds $REC_SECONDS --no-speak --no-play"
timeout 240s "$PY" voice_assistant.py once \
  --seconds "$REC_SECONDS" \
  --no-speak \
  --no-play \
  > "$OUT/once_stdout.txt" \
  2> "$OUT/once_stderr.log"

once_rc=$?

echo
echo "once_return_code: $once_rc"
echo

echo "==================== 2. once stdout ===================="
cat "$OUT/once_stdout.txt" || true
echo

echo "==================== 3. once stderr ===================="
cat "$OUT/once_stderr.log" || true
echo

echo "==================== 4. abnormal check ===================="
grep -nEi "error|failed|not found|segmentation|killed|cannot|invalid|timeout|oom|exception|Traceback|ModuleNotFound|xrun|Broken pipe|Unable to install hw params" \
  "$OUT/once_stdout.txt" \
  "$OUT/once_stderr.log" \
  > "$OUT/abnormal.txt" 2>/dev/null || true

cat "$OUT/abnormal.txt" || true
echo

echo "==================== 5. summary ===================="
echo "once_return_code: $once_rc"
echo "out_dir         : $OUT"

if [ "$once_rc" -eq 0 ]; then
    echo "[RESULT] Experiment 07.3 PASSED_BY_COMMAND"
else
    echo "[RESULT] Experiment 07.3 FAILED"
fi

echo
echo "log saved to: $LOG"
