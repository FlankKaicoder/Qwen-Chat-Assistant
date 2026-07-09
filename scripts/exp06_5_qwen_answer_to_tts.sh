#!/usr/bin/env bash
set -u

OUT="${1:-output/exp06_5_qwen_answer_to_tts_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT"
LOG="$OUT/run.log"

exec > >(tee "$LOG") 2>&1

echo "============================================================"
echo " Experiment 06.5: Qwen answer -> TTS playback"
echo "============================================================"
echo "time    : $(date '+%Y-%m-%d %H:%M:%S')"
echo "workdir : $(pwd)"
echo "out_dir : $OUT"
echo

if [ -x .venv/bin/python ]; then
    PY=.venv/bin/python
else
    PY=python3
fi

echo "PY=$PY"
$PY --version || true
echo

echo "==================== 1. asset check ===================="
ls -lh demo imgenc librknnrt.so librkllmrt.so qwen3-vl-2b_vision_rk3588.rknn qwen3-vl-2b-instruct_w8a8_rk3588.rkllm
ls -lh models/matcha-icefall-zh-baker/model-steps-3.onnx models/vocos-22khz-univ.onnx
echo

echo "==================== 2. generate Qwen answer ===================="

QUESTION="<image>请用一句中文简短介绍这张图片。"
IMAGE="demo.jpg"

cat > "$OUT/qwen_answer_once.py" <<'PY'
from pathlib import Path
import sys
import time

from voice_assistant.config import load_config
from voice_assistant.qwen_runner import QwenRunner

image = sys.argv[1]
question = sys.argv[2]
out_answer = Path(sys.argv[3])

cfg = load_config("config/default.yaml")
runner = QwenRunner(cfg)

print("image:", image)
print("question:", question)

t0 = time.time()
answer = runner.ask(image, question)
t1 = time.time()

answer = str(answer).strip()
out_answer.write_text(answer, encoding="utf-8")

print("qwen_elapsed_seconds:", round(t1 - t0, 3))
print("answer_chars:", len(answer))
print("answer_saved:", out_answer)
print()
print("========== answer ==========")
print(answer)
PY

START_QWEN=$(date +%s)

$PY "$OUT/qwen_answer_once.py" "$IMAGE" "$QUESTION" "$OUT/qwen_answer.txt" \
  > "$OUT/qwen_stdout.log" \
  2> "$OUT/qwen_stderr.log"

QWEN_RC=$?
END_QWEN=$(date +%s)
QWEN_ELAPSED=$((END_QWEN - START_QWEN))

echo "qwen_return_code: $QWEN_RC"
echo "qwen_elapsed_seconds_wall: $QWEN_ELAPSED"
echo

echo "----- qwen stdout -----"
cat "$OUT/qwen_stdout.log"
echo

echo "----- qwen stderr -----"
cat "$OUT/qwen_stderr.log"
echo

if [ "$QWEN_RC" -ne 0 ] || [ ! -s "$OUT/qwen_answer.txt" ]; then
    echo "[RESULT] Experiment 06.5 FAILED_AT_QWEN"
    exit 1
fi

echo "==================== 3. prepare TTS text ===================="
ANSWER="$(cat "$OUT/qwen_answer.txt")"

# 控制实验时长，避免 Qwen 输出太长导致 TTS 播放很久。
# streaming_tts.py 内部也有 stream_max_speak_chars，这里再做一次显式裁剪。
TTS_TEXT="$(python3 - "$OUT/qwen_answer.txt" "$OUT/tts_text.txt" <<'PY'
from pathlib import Path
import sys

answer_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])

s = answer_path.read_text(encoding="utf-8").strip()
s = "下面播放大模型对图片的回答：" + s

max_chars = 180
if len(s) > max_chars:
    s = s[:max_chars] + "。"

out_path.write_text(s, encoding="utf-8")
print(s)
PY
)"

echo "tts_text_chars: ${#TTS_TEXT}"
echo "tts_text:"
cat "$OUT/tts_text.txt"
echo

echo "==================== 4. play answer with official tts-stream ===================="
START_TTS=$(date +%s)

timeout 120s $PY voice_assistant.py tts-stream "$TTS_TEXT" \
  > "$OUT/tts_stream_stdout.log" \
  2> "$OUT/tts_stream_stderr.log"

TTS_RC=$?
END_TTS=$(date +%s)
TTS_ELAPSED=$((END_TTS - START_TTS))

echo "tts_return_code: $TTS_RC"
echo "tts_elapsed_seconds: $TTS_ELAPSED"
echo

echo "----- tts stdout -----"
cat "$OUT/tts_stream_stdout.log"
echo

echo "----- tts stderr -----"
cat "$OUT/tts_stream_stderr.log"
echo

echo "==================== 5. abnormal check ===================="
grep -nEi "error|failed|not found|cannot|invalid|exception|traceback|segmentation|killed|oom|No such file|underrun|xrun|Broken pipe|timeout|Unable to install hw params" \
  "$LOG" \
  "$OUT/qwen_stdout.log" \
  "$OUT/qwen_stderr.log" \
  "$OUT/tts_stream_stdout.log" \
  "$OUT/tts_stream_stderr.log" 2>/dev/null || true
echo

echo "==================== 6. summary ===================="
echo "qwen_return_code: $QWEN_RC"
echo "qwen_elapsed_seconds_wall: $QWEN_ELAPSED"
echo "tts_return_code: $TTS_RC"
echo "tts_elapsed_seconds: $TTS_ELAPSED"
echo "qwen_answer: $OUT/qwen_answer.txt"
echo "tts_text: $OUT/tts_text.txt"

if [ "$QWEN_RC" -eq 0 ] && [ "$TTS_RC" -eq 0 ]; then
    echo "[RESULT] Experiment 06.5 PASSED_BY_COMMAND"
    echo "[NOTE] Please confirm by listening whether the Qwen answer was spoken."
elif [ "$TTS_RC" -eq 124 ]; then
    echo "[RESULT] Experiment 06.5 FAILED_TTS_TIMEOUT"
else
    echo "[RESULT] Experiment 06.5 FAILED"
fi

echo
echo "log saved to: $LOG"
