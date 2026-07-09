#!/usr/bin/env bash
set -u

OUT="output/exp05_2_qwen_runner_cli_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"

LOG="$OUT/run.log"
exec > >(tee "$LOG") 2>&1

echo "========== exp05.2 qwen runner cli =========="
echo "time    : $(date '+%Y-%m-%d %H:%M:%S')"
echo "workdir : $(pwd)"
echo "out     : $OUT"
echo

export LD_LIBRARY_PATH=".:${LD_LIBRARY_PATH:-}"
export RKLLM_LOG_LEVEL=1

echo "========== asset check =========="
for f in \
  demo \
  imgenc \
  librknnrt.so \
  librkllmrt.so \
  demo.jpg \
  qwen3-vl-2b_vision_rk3588.rknn \
  qwen3-vl-2b-instruct_w8a8_rk3588.rkllm
do
  if [ -e "$f" ]; then
    echo "[OK] $f"
    ls -lh "$f"
  else
    echo "[MISS] $f"
  fi
done

echo
echo "========== qwen runner direct import =========="
python3 - <<'PY'
from voice_assistant.config import load_config
from voice_assistant.qwen_runner import QwenRunner

cfg = load_config("config/default.yaml")
runner = QwenRunner(cfg)

print("[OK] QwenRunner import/init")
print("demo        :", runner.qwen["demo"])
print("vision_model:", runner.qwen["vision_model"])
print("llm_model   :", runner.qwen["llm_model"])
PY

echo
echo "========== run voice_assistant.py ask =========="
QUESTION="<image>请用中文简短描述这张图片里有什么。"

echo "question: $QUESTION"
echo

START=$(date +%s)

python3 voice_assistant.py ask "$QUESTION" \
  --image demo.jpg \
  --no-speak \
  --no-play \
  > "$OUT/ask_stdout.log" 2> "$OUT/ask_stderr.log"

RC=$?
END=$(date +%s)
ELAPSED=$((END - START))

echo "return_code: $RC"
echo "elapsed_seconds: $ELAPSED"

echo
echo "========== ask stdout =========="
cat "$OUT/ask_stdout.log"

echo
echo "========== ask stderr =========="
cat "$OUT/ask_stderr.log"

echo
echo "========== result =========="
if [ "$RC" -eq 0 ] && [ -s "$OUT/ask_stdout.log" ]; then
  echo "[RESULT] Experiment 05.2 PASSED"
else
  echo "[RESULT] Experiment 05.2 FAILED"
fi

echo
echo "log saved to: $LOG"
