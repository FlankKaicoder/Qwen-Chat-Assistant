#!/usr/bin/env bash

set -u

PROJECT_DIR="/home/cat/ai/qwen3vl2b"
cd "$PROJECT_DIR" || exit 1

OUT="${1:-output/exp07_8_once_nonstream_verify_clean_$(date +%Y%m%d_%H%M%S)}"
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
echo " Experiment 07.8: verify patched once with clean parser"
echo "============================================================"
echo "time        : $(date '+%Y-%m-%d %H:%M:%S')"
echo "out_dir     : $OUT"
echo "rec_seconds : $REC_SECONDS"
echo

echo "==================== 1. run once ===================="
echo "[INFO] 请在倒计时结束后说：你是谁"
echo

for i in 3 2 1; do
    echo "record starts in $i ..."
    sleep 1
done

timeout 300s "$PY" voice_assistant.py once \
  --seconds "$REC_SECONDS" \
  > "$OUT/once_stdout.txt" \
  2> "$OUT/once_stderr.log"

once_rc=$?

echo "once_return_code: $once_rc"
echo

echo "==================== 2. stdout ===================="
cat "$OUT/once_stdout.txt"
echo

echo "==================== 3. stderr ===================="
cat "$OUT/once_stderr.log"
echo

echo "==================== 4. parse clean result ===================="
python3 - "$OUT/once_stdout.txt" "$OUT/recognized_text.txt" "$OUT/qwen_answer.txt" <<'PY'
import sys
from pathlib import Path

src = Path(sys.argv[1])
rec_out = Path(sys.argv[2])
ans_out = Path(sys.argv[3])

lines = src.read_text(encoding="utf-8", errors="ignore").splitlines()

recognized = ""
answer_lines = []
collect = False

for line in lines:
    s = line.strip()

    if s.startswith("识别文本："):
        recognized = s.split("：", 1)[1].strip()
        continue

    # 这两类是状态提示，不属于回答
    if s.startswith("正在调用 Qwen"):
        continue
    if s.startswith("将使用整段 TTS"):
        collect = True
        continue
    if s.startswith("将使用流式 TTS"):
        collect = True
        continue

    # once 的最终回答通常在“将使用整段 TTS”之后由 CLI 打印
    if collect and s:
        answer_lines.append(line)

answer = "\n".join(answer_lines).strip()

rec_out.write_text(recognized, encoding="utf-8")
ans_out.write_text(answer, encoding="utf-8")
PY

recognized_text="$(cat "$OUT/recognized_text.txt" 2>/dev/null || true)"
qwen_answer_chars="$(python3 - <<PY
from pathlib import Path
p = Path("$OUT/qwen_answer.txt")
s = p.read_text(encoding="utf-8", errors="ignore") if p.exists() else ""
print(len(s))
PY
)"

echo "recognized_text: $recognized_text"
echo "qwen_answer_chars: $qwen_answer_chars"
echo

echo "========== qwen clean answer =========="
cat "$OUT/qwen_answer.txt"
echo

echo "==================== 5. underrun / abnormal ===================="
underrun_count="$(grep -ci "underrun" "$OUT/once_stderr.log" 2>/dev/null || true)"

grep -nEi "error|failed|not found|segmentation|killed|cannot|invalid|timeout|oom|exception|Traceback|ModuleNotFound|Broken pipe|Unable to install hw params" \
  "$OUT/once_stdout.txt" \
  "$OUT/once_stderr.log" \
  > "$OUT/abnormal_without_underrun.txt" 2>/dev/null || true

echo "underrun_count: $underrun_count"
echo

echo "----- abnormal_without_underrun -----"
cat "$OUT/abnormal_without_underrun.txt"
echo

echo "==================== 6. summary ===================="
echo "once_return_code   : $once_rc"
echo "underrun_count     : $underrun_count"
echo "recognized_text    : $recognized_text"
echo "qwen_answer_chars  : $qwen_answer_chars"
echo "out_dir            : $OUT"

if [ "$once_rc" -eq 0 ] && [ "$underrun_count" -eq 0 ] && [ -n "$recognized_text" ] && [ "$qwen_answer_chars" -gt 0 ]; then
    echo "[RESULT] Experiment 07.8 PASSED_CLEAN_VERIFY"
    echo "[NOTE] Please confirm by listening whether the assistant answer was spoken."
else
    echo "[RESULT] Experiment 07.8 FAILED_OR_INCOMPLETE"
fi

echo
echo "log saved to: $LOG"
