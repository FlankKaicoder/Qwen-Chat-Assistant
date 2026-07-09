#!/usr/bin/env bash

set -u

PROJECT_DIR="/home/cat/ai/qwen3vl2b"
cd "$PROJECT_DIR" || exit 1

OUT="${1:-output/exp07_1_record_stt_qwen_tts_once_$(date +%Y%m%d_%H%M%S)}"
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

WAV="$OUT/command.wav"
RECOGNIZED_TXT="$OUT/recognized_text.txt"
QWEN_PROMPT_TXT="$OUT/qwen_prompt.txt"
QWEN_ANSWER_TXT="$OUT/qwen_answer.txt"
TTS_TEXT_TXT="$OUT/tts_text.txt"

echo "============================================================"
echo " Experiment 07.1: record -> stt -> qwen -> tts-stream"
echo "============================================================"
echo "time        : $(date '+%Y-%m-%d %H:%M:%S')"
echo "project_dir : $PROJECT_DIR"
echo "out_dir     : $OUT"
echo "python      : $PY"
echo "rec_seconds : $REC_SECONDS"
echo

echo "==================== 0. precheck ===================="
echo "----- python -----"
"$PY" --version || true
echo

echo "----- key files -----"
for p in \
  voice_assistant.py \
  config/default.yaml \
  demo \
  qwen3-vl-2b_vision_rk3588.rknn \
  qwen3-vl-2b-instruct_w8a8_rk3588.rkllm \
  models/sherpa-onnx-conformer-zh-stateless2-2023-05-23 \
  models/matcha-icefall-zh-baker/model-steps-3.onnx \
  models/vocos-22khz-univ.onnx
do
    if [ -e "$p" ]; then
        echo "[OK] $p"
    else
        echo "[MISS] $p"
    fi
done
echo

echo "----- audio config -----"
sed -n '/audio:/,/models:/p' config/default.yaml || true
echo

echo "==================== 1. record ===================="
echo "[INFO] 请在倒计时结束后说一句短问题，例如：请用一句话介绍一下你自己"
echo

for i in 3 2 1; do
    echo "record starts in $i ..."
    sleep 1
done

echo "[RUN] voice_assistant.py record"
"$PY" voice_assistant.py record \
  --seconds "$REC_SECONDS" \
  --out "$WAV" \
  > "$OUT/record_stdout.log" \
  2> "$OUT/record_stderr.log"
record_rc=$?

echo "record_return_code: $record_rc"
echo

echo "----- record stdout -----"
cat "$OUT/record_stdout.log" || true
echo

echo "----- record stderr -----"
cat "$OUT/record_stderr.log" || true
echo

echo "----- wav info -----"
if [ -f "$WAV" ]; then
    ls -lh "$WAV"
    file "$WAV" || true
    soxi "$WAV" 2>/dev/null || true

    ffmpeg -hide_banner \
      -i "$WAV" \
      -af volumedetect \
      -f null - \
      > "$OUT/record_volumedetect.log" \
      2>&1 || true

    grep -E "mean_volume|max_volume" "$OUT/record_volumedetect.log" || true
else
    echo "[MISS] $WAV"
fi
echo

echo "==================== 2. stt ===================="
if [ "$record_rc" -eq 0 ] && [ -f "$WAV" ]; then
    echo "[RUN] voice_assistant.py stt"
    "$PY" voice_assistant.py stt "$WAV" \
      > "$OUT/stt_stdout.txt" \
      2> "$OUT/stt_stderr.log"
    stt_rc=$?
else
    echo "[SKIP] record failed"
    stt_rc=99
fi

echo "stt_return_code: $stt_rc"
echo

echo "----- stt stdout -----"
cat "$OUT/stt_stdout.txt" 2>/dev/null || true
echo

echo "----- stt stderr -----"
cat "$OUT/stt_stderr.log" 2>/dev/null || true
echo

python3 - "$OUT/stt_stdout.txt" "$RECOGNIZED_TXT" <<'PY'
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])

text = ""
if src.exists():
    lines = [x.strip() for x in src.read_text(errors="ignore").splitlines() if x.strip()]
    candidates = []
    for line in lines:
        if "recognized_text" in line and ":" in line:
            candidates.append(line.split(":", 1)[1].strip())
        elif not line.startswith("[") and not line.startswith("="):
            candidates.append(line.strip())
    if candidates:
        text = candidates[-1].strip()

dst.write_text(text, encoding="utf-8")
PY

recognized_text="$(cat "$RECOGNIZED_TXT" 2>/dev/null || true)"
echo "recognized_text: $recognized_text"
echo

echo "==================== 3. qwen ask ===================="
if [ "$stt_rc" -eq 0 ] && [ -n "$recognized_text" ]; then
    # 为了控制 TTS 时间，这里强制要求 Qwen 用一两句话回答。
    printf "请用一到两句中文简短回答下面的问题：%s\n" "$recognized_text" > "$QWEN_PROMPT_TXT"
    qwen_prompt="$(cat "$QWEN_PROMPT_TXT")"

    echo "qwen_prompt: $qwen_prompt"
    echo
    echo "[RUN] voice_assistant.py ask --no-speak --no-play"

    timeout 180s "$PY" voice_assistant.py ask "$qwen_prompt" \
      --no-speak \
      --no-play \
      > "$OUT/qwen_stdout.txt" \
      2> "$OUT/qwen_stderr.log"
    qwen_rc=$?
else
    echo "[SKIP] stt failed or recognized_text empty"
    qwen_rc=99
fi

echo "qwen_return_code: $qwen_rc"
echo

echo "----- qwen stdout -----"
cat "$OUT/qwen_stdout.txt" 2>/dev/null || true
echo

echo "----- qwen stderr -----"
cat "$OUT/qwen_stderr.log" 2>/dev/null || true
echo

python3 - "$OUT/qwen_stdout.txt" "$QWEN_ANSWER_TXT" <<'PY'
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])

answer = ""
if src.exists():
    lines = src.read_text(errors="ignore").splitlines()

    # 去掉 lightweight ask 头部，只保留真正回答
    start = 0
    for i, line in enumerate(lines):
        if line.startswith("text"):
            start = i + 1
            break

    rest = lines[start:]
    while rest and not rest[0].strip():
        rest.pop(0)

    cleaned = []
    for line in rest:
        s = line.strip()
        if not s:
            cleaned.append("")
            continue
        if s.startswith("=========="):
            continue
        if s.startswith("image :"):
            continue
        if s.startswith("text  :"):
            continue
        cleaned.append(line)

    answer = "\n".join(cleaned).strip()

dst.write_text(answer, encoding="utf-8")
PY

qwen_answer="$(cat "$QWEN_ANSWER_TXT" 2>/dev/null || true)"
echo "qwen_answer_chars: $(python3 - <<PY
s = """$qwen_answer"""
print(len(s))
PY
)"
echo

echo "========== qwen clean answer =========="
cat "$QWEN_ANSWER_TXT" 2>/dev/null || true
echo

echo "==================== 4. tts-stream ===================="
if [ "$qwen_rc" -eq 0 ] && [ -s "$QWEN_ANSWER_TXT" ]; then
    python3 - "$QWEN_ANSWER_TXT" "$TTS_TEXT_TXT" <<'PY'
import sys
from pathlib import Path

answer = Path(sys.argv[1]).read_text(encoding="utf-8", errors="ignore").strip()
# 控制首次闭环实验的播报长度，避免回答过长导致 TTS 时间太长
answer = answer.replace("\n", " ")
max_chars = 120
if len(answer) > max_chars:
    answer = answer[:max_chars] + "。"

tts_text = "下面播放语音助手回答：" + answer
Path(sys.argv[2]).write_text(tts_text, encoding="utf-8")
PY

    tts_text="$(cat "$TTS_TEXT_TXT")"

    echo "tts_text_chars: $(python3 - <<PY
s = """$tts_text"""
print(len(s))
PY
)"
    echo

    echo "========== tts text =========="
    cat "$TTS_TEXT_TXT"
    echo

    echo "[RUN] voice_assistant.py tts-stream"
    timeout 180s "$PY" voice_assistant.py tts-stream "$tts_text" \
      > "$OUT/tts_stdout.log" \
      2> "$OUT/tts_stderr.log"
    tts_rc=$?
else
    echo "[SKIP] qwen failed or answer empty"
    tts_rc=99
fi

echo "tts_return_code: $tts_rc"
echo

echo "----- tts stdout -----"
cat "$OUT/tts_stdout.log" 2>/dev/null || true
echo

echo "----- tts stderr -----"
cat "$OUT/tts_stderr.log" 2>/dev/null || true
echo

echo "==================== 5. abnormal check ===================="
grep -nEi "error|failed|not found|segmentation|killed|cannot|invalid|timeout|oom|exception|Traceback|ModuleNotFound|xrun|Broken pipe|Unable to install hw params" \
  "$OUT"/record_stdout.log \
  "$OUT"/record_stderr.log \
  "$OUT"/stt_stdout.txt \
  "$OUT"/stt_stderr.log \
  "$OUT"/qwen_stdout.txt \
  "$OUT"/qwen_stderr.log \
  "$OUT"/tts_stdout.log \
  "$OUT"/tts_stderr.log \
  > "$OUT/abnormal.txt" 2>/dev/null || true

cat "$OUT/abnormal.txt" || true
echo

echo "==================== 6. summary ===================="
echo "record_return_code: $record_rc"
echo "stt_return_code   : $stt_rc"
echo "qwen_return_code  : $qwen_rc"
echo "tts_return_code   : $tts_rc"
echo "recognized_text   : $recognized_text"
echo "out_dir           : $OUT"

if [ "$record_rc" -eq 0 ] && \
   [ "$stt_rc" -eq 0 ] && \
   [ "$qwen_rc" -eq 0 ] && \
   [ "$tts_rc" -eq 0 ] && \
   [ -n "$recognized_text" ] && \
   [ -s "$QWEN_ANSWER_TXT" ]; then
    echo "[RESULT] Experiment 07.1 PASSED_BY_COMMAND"
    echo "[NOTE] Please confirm by listening whether the Qwen answer was spoken."
else
    echo "[RESULT] Experiment 07.1 FAILED_OR_INCOMPLETE"
fi

echo
echo "log saved to: $LOG"
