#!/usr/bin/env bash
set -u

OUT="output/exp05_2a_qwen_runner_direct_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"

LOG="$OUT/run.log"
exec > >(tee "$LOG") 2>&1

echo "========== exp05.2a qwen runner direct =========="
echo "time    : $(date '+%Y-%m-%d %H:%M:%S')"
echo "workdir : $(pwd)"
echo "out     : $OUT"
echo

export LD_LIBRARY_PATH=".:${LD_LIBRARY_PATH:-}"
export RKLLM_LOG_LEVEL=1

echo "========== direct QwenRunner.ask =========="
python3 - <<'PY'
from voice_assistant.config import load_config
from voice_assistant.qwen_runner import QwenRunner

cfg = load_config("config/default.yaml")
runner = QwenRunner(cfg)

question = "<image>请用中文简短描述这张图片里有什么。"
image = "demo.jpg"

print("image   :", image)
print("question:", question)
print()

answer = runner.ask(image, question)

print("========== answer ==========")
print(answer)

if answer.strip():
    print("[RESULT] Experiment 05.2a PASSED")
else:
    print("[RESULT] Experiment 05.2a FAILED: empty answer")
PY

echo
echo "log saved to: $LOG"
