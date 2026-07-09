#!/usr/bin/env bash

set -u

PROJECT_DIR="/home/cat/ai/qwen3vl2b"
cd "$PROJECT_DIR" || exit 1

OUT="${1:-output/exp07_4_once_with_tts_play_$(date +%Y%m%d_%H%M%S)}"
REC_SECONDS="${2:-5}"

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
echo " Experiment 07.4: official once with TTS playback"
echo "============================================================"
echo "time        : $(date '+%Y-%m-%d %H:%M:%S')"
echo "project_dir : $PROJECT_DIR"
echo "out_dir     : $OUT"
echo "python      : $PY"
echo "rec_seconds : $REC_SECONDS"
echo

echo "==================== 1. run once with speak/play ===================="
echo "[INFO] 请在倒计时结束后说一句短问题，建议说：你是谁"
echo

for i in 3 2 1; do
    echo "record starts in $i ..."
    sleep 1
done

echo "[RUN] voice_assistant.py once --seconds $REC_SECONDS"
timeout 300s "$PY" voice_assistant.py once \
  --seconds "$REC_SECONDS" \
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

echo "==================== 4. command wav check ===================="
CMD_WAV="/tmp/qwen_voice_assistant/command.wav"

if [ -f "$CMD_WAV" ]; then
    cp -av "$CMD_WAV" "$OUT/command.wav" || true

    echo "----- wav file -----"
    ls -lh "$OUT/command.wav" || true
    file "$OUT/command.wav" || true
    soxi "$OUT/command.wav" 2>/dev/null || true

    ffmpeg -hide_banner \
      -i "$OUT/command.wav" \
      -af volumedetect \
      -f null - \
      > "$OUT/record_volumedetect.log" \
      2>&1 || true

    echo "----- volume -----"
    grep -E "mean_volume|max_volume" "$OUT/record_volumedetect.log" || true
else
    echo "[WARN] $CMD_WAV not found"
fi
echo

echo "==================== 5. parse stdout ===================="
python3 - "$OUT/once_stdout.txt" "$OUT/recognized_text.txt" "$OUT/qwen_answer.txt" <<'PY'
import sys
from pathlib import Path

src = Path(sys.argv[1])
rec_out = Path(sys.argv[2])
ans_out = Path(sys.argv[3])

text = src.read_text(encoding="utf-8", errors="ignore") if src.exists() else ""
lines = text.splitlines()

recognized = ""
answer_lines = []

for i, line in enumerate(lines):
    s = line.strip()
    if s.startswith("识别文本："):
        recognized = s.split("：", 1)[1].strip()
        continue
    if s.startswith("正在调用 Qwen"):
        answer_lines = lines[i+1:]
        break

answer = "\n".join(answer_lines).strip()

rec_out.write_text(recognized, encoding="utf-8")
ans_out.write_text(answer, encoding="utf-8")
PY

echo "recognized_text: $(cat "$OUT/recognized_text.txt" 2>/dev/null || true)"
echo "qwen_answer_chars: $(python3 - <<PY
from pathlib import Path
p = Path("$OUT/qwen_answer.txt")
s = p.read_text(encoding="utf-8", errors="ignore") if p.exists() else ""
print(len(s))
PY
)"
echo

echo "========== qwen clean answer =========="
cat "$OUT/qwen_answer.txt" 2>/dev/null || true
echo

echo "==================== 6. abnormal check ===================="
grep -nEi "error|failed|not found|segmentation|killed|cannot|invalid|timeout|oom|exception|Traceback|ModuleNotFound|xrun|Broken pipe|Unable to install hw params" \
  "$OUT/once_stdout.txt" \
  "$OUT/once_stderr.log" \
  > "$OUT/abnormal.txt" 2>/dev/null || true

cat "$OUT/abnormal.txt" || true
echo

echo "==================== 7. summary ===================="
echo "once_return_code: $once_rc"
echo "recognized_text : $(cat "$OUT/recognized_text.txt" 2>/dev/null || true)"
echo "out_dir         : $OUT"

if [ "$once_rc" -eq 0 ]; then
    echo "[RESULT] Experiment 07.4 PASSED_BY_COMMAND"
    echo "[NOTE] Please confirm by listening whether the assistant answer was spoken."
else
    echo "[RESULT] Experiment 07.4 FAILED"
fi

echo
echo "log saved to: $LOG"
