#!/usr/bin/env bash
set -u

OUT_DIR="${1:-output/exp09_1b_kws_pos_neg_compare_manual}"
SECONDS="${2:-4}"

mkdir -p "$OUT_DIR"

PY=".venv/bin/python"
if [ ! -x "$PY" ]; then
  PY="$(command -v python3)"
fi

export PYTHONPATH="$(pwd)/.python_packages:$(pwd):${PYTHONPATH:-}"

LOG="$OUT_DIR/run.log"
exec > >(tee "$LOG") 2>&1

echo "============================================================"
echo " Experiment 09.1b: KWS positive / negative compare"
echo "============================================================"
echo "time    : $(date '+%Y-%m-%d %H:%M:%S')"
echo "workdir : $(pwd)"
echo "out_dir : $OUT_DIR"
echo "python  : $PY"
echo "seconds : $SECONDS"
echo

run_case() {
  local name="$1"
  local hint="$2"
  local wav="$OUT_DIR/${name}.wav"
  local rec_log="$OUT_DIR/${name}_record.log"
  local stdout="$OUT_DIR/${name}_kws_stdout.txt"
  local stderr="$OUT_DIR/${name}_kws_stderr.txt"
  local vol="$OUT_DIR/${name}_volumedetect.log"

  echo
  echo "==================== case: $name ===================="
  echo "录音开始后请说：$hint"
  echo "[RUN] $PY voice_assistant.py record --seconds $SECONDS --out $wav"

  "$PY" voice_assistant.py record --seconds "$SECONDS" --out "$wav" > "$rec_log" 2>&1
  local rec_rc=$?

  cat "$rec_log"
  echo "record_return_code_${name}: $rec_rc"

  if [ -f "$wav" ]; then
    file "$wav" || true
    soxi "$wav" 2>/dev/null || true

    ffmpeg -hide_banner -i "$wav" -af volumedetect -f null - > "$vol" 2>&1 || true
    grep -E "mean_volume|max_volume" "$vol" || true
  else
    echo "[MISS] $wav"
  fi

  echo "[RUN] $PY voice_assistant.py kws-file $wav"
  "$PY" voice_assistant.py kws-file "$wav" > "$stdout" 2> "$stderr"
  local kws_rc=$?

  echo "kws_return_code_${name}: $kws_rc"

  echo "----- ${name} kws stdout -----"
  cat "$stdout"
  echo

  echo "----- ${name} kws stderr -----"
  cat "$stderr"
  echo

  local mean max
  mean=$(grep -E "mean_volume" "$vol" 2>/dev/null | tail -1 | sed 's/.*mean_volume: //')
  max=$(grep -E "max_volume" "$vol" 2>/dev/null | tail -1 | sed 's/.*max_volume: //')

  echo "summary_${name}_record_rc: $rec_rc" >> "$OUT_DIR/summary.txt"
  echo "summary_${name}_kws_rc   : $kws_rc" >> "$OUT_DIR/summary.txt"
  echo "summary_${name}_mean_vol : ${mean:-}" >> "$OUT_DIR/summary.txt"
  echo "summary_${name}_max_vol  : ${max:-}" >> "$OUT_DIR/summary.txt"
  echo "summary_${name}_stdout   : $(tr '\n' ' ' < "$stdout")" >> "$OUT_DIR/summary.txt"
  echo "summary_${name}_stderr   : $(tr '\n' ' ' < "$stderr")" >> "$OUT_DIR/summary.txt"
}

echo "第一段录音：正样本，只说：鲁班猫"
read -p "准备好后按回车开始正样本录音..." _
run_case "positive_lubancat" "鲁班猫"

echo
echo "第二段录音：负样本，只说：你好你好"
read -p "准备好后按回车开始负样本录音..." _
run_case "negative_hello" "你好你好"

echo
echo "==================== abnormal scan ===================="
grep -nEi "error|failed|Traceback|ModuleNotFound|ImportError|Unable|Broken pipe|No such file|not found|cannot|killed|oom|segmentation|exception" \
  "$OUT_DIR"/*.log "$OUT_DIR"/*.txt > "$OUT_DIR/abnormal.txt" 2>/dev/null || true
cat "$OUT_DIR/abnormal.txt"

echo
echo "==================== summary ===================="
cat "$OUT_DIR/summary.txt"

echo
echo "[RESULT] Experiment 09.1b COMPLETED_NEEDS_INTERPRETATION"
echo "log saved to: $LOG"
