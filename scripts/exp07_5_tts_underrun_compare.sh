#!/usr/bin/env bash

set -u

PROJECT_DIR="/home/cat/ai/qwen3vl2b"
cd "$PROJECT_DIR" || exit 1

OUT="${1:-output/exp07_5_tts_underrun_compare_$(date +%Y%m%d_%H%M%S)}"
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
echo " Experiment 07.5: TTS underrun compare"
echo "============================================================"
echo "time        : $(date '+%Y-%m-%d %H:%M:%S')"
echo "project_dir : $PROJECT_DIR"
echo "out_dir     : $OUT"
echo "python      : $PY"
echo "rec_seconds : $REC_SECONDS"
echo

count_underrun() {
    local file="$1"
    if [ -f "$file" ]; then
        grep -ci "underrun" "$file" || true
    else
        echo 0
    fi
}

run_tts_case() {
    local name="$1"
    local text="$2"

    local txt_file="$OUT/${name}_text.txt"
    local stdout_file="$OUT/${name}_stdout.log"
    local stderr_file="$OUT/${name}_stderr.log"

    printf "%s" "$text" > "$txt_file"

    echo "==================== TTS case: $name ===================="
    echo "text_chars: $(python3 - <<PY
from pathlib import Path
s = Path("$txt_file").read_text(encoding="utf-8", errors="ignore")
print(len(s))
PY
)"
    echo "text:"
    cat "$txt_file"
    echo

    timeout 180s "$PY" voice_assistant.py tts-stream "$text" \
      > "$stdout_file" \
      2> "$stderr_file"

    local rc=$?
    local underrun_count
    underrun_count="$(count_underrun "$stderr_file")"

    echo "${name}_return_code: $rc"
    echo "${name}_underrun_count: $underrun_count"
    echo

    echo "----- ${name} stdout -----"
    cat "$stdout_file" || true
    echo

    echo "----- ${name} stderr -----"
    cat "$stderr_file" || true
    echo
}

echo "==================== 1. prepare texts ===================="

SHORT_TEXT="你好，我是三五八八端侧语音助手。现在正在复核语音播放缓冲是否稳定。"

LAST_074="$(ls -td output/exp07_4_once_with_tts_play_* 2>/dev/null | head -1 || true)"
if [ -n "$LAST_074" ] && [ -s "$LAST_074/qwen_answer.txt" ]; then
    QWEN_ANSWER="$(cat "$LAST_074/qwen_answer.txt")"
else
    QWEN_ANSWER="我是一个AI助手，可以帮助你解答问题、提供信息和完成一些文本处理任务。"
fi

QWEN_TEXT="下面播放上一次大模型回答：${QWEN_ANSWER}"

echo "last_074: ${LAST_074:-NONE}"
echo

echo "==================== 2. case A: short fixed tts-stream ===================="
run_tts_case "caseA_short_tts_stream" "$SHORT_TEXT"

echo "==================== 3. case B: qwen answer tts-stream ===================="
run_tts_case "caseB_qwen_answer_tts_stream" "$QWEN_TEXT"

echo "==================== 4. case C: official once with streaming TTS ===================="
echo "[INFO] 请在倒计时结束后说一句短问题，建议说：你是谁"
echo

for i in 3 2 1; do
    echo "record starts in $i ..."
    sleep 1
done

echo "[RUN] voice_assistant.py once --seconds $REC_SECONDS"

timeout 300s "$PY" voice_assistant.py once \
  --seconds "$REC_SECONDS" \
  > "$OUT/caseC_once_stdout.txt" \
  2> "$OUT/caseC_once_stderr.log"

once_rc=$?
once_underrun_count="$(count_underrun "$OUT/caseC_once_stderr.log")"

echo "caseC_once_return_code: $once_rc"
echo "caseC_once_underrun_count: $once_underrun_count"
echo

echo "----- caseC once stdout -----"
cat "$OUT/caseC_once_stdout.txt" || true
echo

echo "----- caseC once stderr -----"
cat "$OUT/caseC_once_stderr.log" || true
echo

python3 - "$OUT/caseC_once_stdout.txt" "$OUT/caseC_recognized_text.txt" "$OUT/caseC_qwen_answer.txt" <<'PY'
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

echo "caseC_recognized_text: $(cat "$OUT/caseC_recognized_text.txt" 2>/dev/null || true)"
echo "caseC_qwen_answer_chars: $(python3 - <<PY
from pathlib import Path
p = Path("$OUT/caseC_qwen_answer.txt")
s = p.read_text(encoding="utf-8", errors="ignore") if p.exists() else ""
print(len(s))
PY
)"
echo

echo "==================== 5. underrun summary ===================="
caseA_underrun_count="$(count_underrun "$OUT/caseA_short_tts_stream_stderr.log")"
caseB_underrun_count="$(count_underrun "$OUT/caseB_qwen_answer_tts_stream_stderr.log")"
caseC_underrun_count="$(count_underrun "$OUT/caseC_once_stderr.log")"

echo "caseA_short_tts_stream_underrun_count     : $caseA_underrun_count"
echo "caseB_qwen_answer_tts_stream_underrun_count: $caseB_underrun_count"
echo "caseC_once_streaming_tts_underrun_count   : $caseC_underrun_count"
echo

echo "==================== 6. abnormal check ===================="
grep -nEi "error|failed|not found|segmentation|killed|cannot|invalid|timeout|oom|exception|Traceback|ModuleNotFound|Broken pipe|Unable to install hw params" \
  "$OUT"/caseA_short_tts_stream_stdout.log \
  "$OUT"/caseA_short_tts_stream_stderr.log \
  "$OUT"/caseB_qwen_answer_tts_stream_stdout.log \
  "$OUT"/caseB_qwen_answer_tts_stream_stderr.log \
  "$OUT"/caseC_once_stdout.txt \
  "$OUT"/caseC_once_stderr.log \
  > "$OUT/abnormal_without_underrun.txt" 2>/dev/null || true

cat "$OUT/abnormal_without_underrun.txt" || true
echo

echo "==================== 7. conclusion hint ===================="
if [ "$caseA_underrun_count" -eq 0 ] && [ "$caseB_underrun_count" -eq 0 ] && [ "$caseC_underrun_count" -gt 0 ]; then
    echo "[DIAGNOSIS] underrun likely comes from once streaming integration / buffering."
elif [ "$caseA_underrun_count" -gt 0 ] || [ "$caseB_underrun_count" -gt 0 ]; then
    echo "[DIAGNOSIS] underrun also appears in standalone tts-stream; playback buffer path needs optimization."
elif [ "$caseA_underrun_count" -eq 0 ] && [ "$caseB_underrun_count" -eq 0 ] && [ "$caseC_underrun_count" -eq 0 ]; then
    echo "[DIAGNOSIS] no underrun reproduced this time; previous underrun may be incidental."
else
    echo "[DIAGNOSIS] mixed result; inspect stderr logs manually."
fi
echo

echo "==================== 8. summary ===================="
echo "caseA_short_tts_stream_underrun_count      : $caseA_underrun_count"
echo "caseB_qwen_answer_tts_stream_underrun_count: $caseB_underrun_count"
echo "caseC_once_streaming_tts_underrun_count    : $caseC_underrun_count"
echo "caseC_once_return_code                     : $once_rc"
echo "caseC_recognized_text                      : $(cat "$OUT/caseC_recognized_text.txt" 2>/dev/null || true)"
echo "out_dir                                    : $OUT"

if [ "$once_rc" -eq 0 ]; then
    echo "[RESULT] Experiment 07.5 COMPLETED"
else
    echo "[RESULT] Experiment 07.5 COMPLETED_WITH_ONCE_FAILURE"
fi

echo
echo "log saved to: $LOG"
