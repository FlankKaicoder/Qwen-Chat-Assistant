#!/usr/bin/env bash
set -u

OUT_DIR="${1:-output/exp09_2_realtime_wake_kws_manual}"
WAKE_TIMEOUT="${2:-20}"

mkdir -p "$OUT_DIR"

PY=".venv/bin/python"
if [ ! -x "$PY" ]; then
  PY="$(command -v python3)"
fi

export PYTHONPATH="$(pwd)/.python_packages:$(pwd):${PYTHONPATH:-}"

LOG="$OUT_DIR/run.log"
STDOUT="$OUT_DIR/wake_stdout.txt"
STDERR="$OUT_DIR/wake_stderr.txt"

exec > >(tee "$LOG") 2>&1

echo "============================================================"
echo " Experiment 09.2: realtime KWS wake"
echo "============================================================"
echo "time        : $(date '+%Y-%m-%d %H:%M:%S')"
echo "workdir     : $(pwd)"
echo "out_dir     : $OUT_DIR"
echo "python      : $PY"
echo "wake_timeout: $WAKE_TIMEOUT"
echo

echo "==================== 1. instruction ===================="
echo "运行后请在 ${WAKE_TIMEOUT}s 内说唤醒词：鲁班猫"
echo "建议说得清楚一些，不要离麦克风太近。"
echo

echo "==================== 2. config key ===================="
grep -nE "input_channel|wake_input_gain|keywords_score|keywords_threshold|mic_device|sample_rate|channels" config/default.yaml || true
echo

echo "==================== 3. run wake ===================="
echo "[RUN] timeout $((WAKE_TIMEOUT + 8))s $PY voice_assistant.py wake --mode kws --timeout $WAKE_TIMEOUT"

timeout "$((WAKE_TIMEOUT + 8))" \
  "$PY" voice_assistant.py wake \
  --mode kws \
  --timeout "$WAKE_TIMEOUT" \
  > "$STDOUT" 2> "$STDERR"

RC=$?

echo "wake_return_code: $RC"
echo

echo "----- wake stdout -----"
cat "$STDOUT"
echo

echo "----- wake stderr -----"
cat "$STDERR"
echo

echo "==================== 4. abnormal scan ===================="
grep -nEi "error|failed|Traceback|ModuleNotFound|ImportError|Unable|Broken pipe|No such file|not found|cannot|killed|oom|segmentation|exception|Timeout" \
  "$STDOUT" "$STDERR" "$LOG" > "$OUT_DIR/abnormal.txt" 2>/dev/null || true
cat "$OUT_DIR/abnormal.txt"
echo

echo "==================== 5. summary ===================="
WAKE_TEXT=$(cat "$STDOUT" | tr -d '\r\n ')

echo "out_dir         : $OUT_DIR"
echo "wake_return_code: $RC"
echo "wake_text       : $WAKE_TEXT"

if [ "$RC" = "0" ] && [ "$WAKE_TEXT" = "鲁班猫" ]; then
  echo "[RESULT] Experiment 09.2 PASSED_REALTIME_KWS_WAKE"
elif [ "$RC" = "0" ] && [ -n "$WAKE_TEXT" ]; then
  echo "[RESULT] Experiment 09.2 PASSED_WITH_OTHER_WAKE_TEXT"
else
  echo "[RESULT] Experiment 09.2 FAILED_OR_TIMEOUT"
fi

echo
echo "log saved to: $LOG"
