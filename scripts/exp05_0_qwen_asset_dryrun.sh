#!/usr/bin/env bash
set -u

OUT="output/exp05_0_qwen_asset_dryrun_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"

LOG="$OUT/run.log"
exec > >(tee "$LOG") 2>&1

echo "========== exp05.0 qwen asset dryrun =========="
echo "time    : $(date '+%Y-%m-%d %H:%M:%S')"
echo "workdir : $(pwd)"
echo "out     : $OUT"
echo

echo "========== required qwen assets =========="
missing=0
for f in \
  demo \
  imgenc \
  librknnrt.so \
  librkllmrt.so \
  qwen3-vl-2b_vision_rk3588.rknn \
  qwen3-vl-2b-instruct_w8a8_rk3588.rkllm
do
  if [ -e "$f" ]; then
    echo "[OK] $f"
    ls -lh "$f"
    file "$f" 2>/dev/null || true
  else
    echo "[MISS] $f"
    missing=$((missing+1))
  fi
  echo
done

echo "missing_qwen_assets: $missing"
echo

echo "========== qwen config =========="
sed -n '/qwen:/,/intent:/p' config/default.yaml

echo
echo "========== expected demo command =========="
python3 - <<'PY'
import yaml
from pathlib import Path

cfg = yaml.safe_load(Path("config/default.yaml").read_text())
q = cfg["qwen"]

args = [
    q["demo"],
    cfg["paths"]["placeholder_image"],
    q["vision_model"],
    q["llm_model"],
    str(q["max_new_tokens"]),
    str(q["max_context_len"]),
    str(q["rknn_core_num"]),
    q["img_start"],
    q["img_end"],
    q["img_content"],
]

print(" ".join(args))
PY

echo
echo "========== QwenRunner import check =========="
python3 - <<'PY'
from voice_assistant.config import load_config
from voice_assistant.qwen_runner import QwenRunner

cfg = load_config("config/default.yaml")
runner = QwenRunner(cfg)

print("[OK] QwenRunner import and init passed")
print("project_dir :", runner.project_dir)
print("demo        :", runner.qwen["demo"])
print("vision_model:", runner.qwen["vision_model"])
print("llm_model   :", runner.qwen["llm_model"])
PY

echo
echo "========== result =========="
if [ "$missing" -eq 0 ]; then
  echo "[RESULT] Qwen assets complete. Continue to real Qwen inference."
else
  echo "[RESULT] Qwen assets missing. Real Qwen inference is blocked."
fi

echo
echo "log saved to: $LOG"
