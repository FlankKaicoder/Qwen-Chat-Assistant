#!/usr/bin/env bash
set -u

OUT="output/exp05_1_qwen_demo_text_image_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"

LOG="$OUT/run.log"
exec > >(tee "$LOG") 2>&1

echo "========== exp05.1 qwen demo text+image baseline =========="
echo "time    : $(date '+%Y-%m-%d %H:%M:%S')"
echo "workdir : $(pwd)"
echo "out     : $OUT"
echo

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
    file "$f" 2>/dev/null || true
  else
    echo "[MISS] $f"
  fi
  echo
done

echo "========== ldd check =========="
LD_LIBRARY_PATH=. ldd ./demo || true
echo
LD_LIBRARY_PATH=. ldd ./imgenc || true
echo
LD_LIBRARY_PATH=. ldd ./demo ./imgenc 2>/dev/null | grep -i "not found" || echo "[OK] no not-found deps"
echo

echo "========== memory before =========="
free -h
echo

echo "========== demo usage =========="
./demo 2>&1 | head -20 || true
echo

echo "========== run qwen demo through pexpect =========="
python3 - <<'PY'
import os
import time
from pathlib import Path

import pexpect

project = Path("/home/cat/ai/qwen3vl2b")
out = Path(os.environ.get("OUT_DIR", "")) if os.environ.get("OUT_DIR") else None

env = os.environ.copy()
env["LD_LIBRARY_PATH"] = f"{project}:{env.get('LD_LIBRARY_PATH', '')}"
env["RKLLM_LOG_LEVEL"] = "1"

args = [
    str(project / "demo"),
    str(project / "demo.jpg"),
    str(project / "qwen3-vl-2b_vision_rk3588.rknn"),
    str(project / "qwen3-vl-2b-instruct_w8a8_rk3588.rkllm"),
    "2048",
    "4096",
    "3",
    "<|vision_start|>",
    "<|vision_end|>",
    "<|image_pad|>",
]

print("[CMD]")
print(" ".join(args), flush=True)

child = pexpect.spawn(
    args[0],
    args[1:],
    cwd=str(project),
    env=env,
    encoding="utf-8",
    codec_errors="ignore",
    timeout=600,
)

full = []
t0 = time.time()

def save_chunk(x):
    if x:
        full.append(x)
        print(x, end="", flush=True)

try:
    print("\n[WAIT] initial user prompt", flush=True)
    child.expect("user:", timeout=600)
    save_chunk(child.before)
    print("user:", flush=True)

    question = "<image>请用中文简短描述这张图片里有什么。"
    print(f"\n[SEND] {question}", flush=True)
    child.sendline(question)

    child.expect("robot:", timeout=120)
    save_chunk(child.before)
    print("robot:", flush=True)

    child.expect("user:", timeout=600)
    answer = child.before
    save_chunk(answer)
    print("user:", flush=True)

    child.sendline("exit")

    elapsed = time.time() - t0
    clean_answer = "\n".join(
        line.strip()
        for line in answer.splitlines()
        if line.strip()
        and line.strip() not in {"robot:", "user:"}
        and not line.strip().startswith("I rkllm:")
    ).strip()

    print("\n========== clean answer ==========")
    print(clean_answer)
    print()
    print(f"elapsed_seconds: {elapsed:.3f}")

    if clean_answer:
        print("[RESULT] Experiment 05.1 PASSED")
    else:
        print("[RESULT] Experiment 05.1 FAILED: empty answer")

except Exception as e:
    print("\n[ERROR]", repr(e))
    tail = child.before[-3000:] if isinstance(child.before, str) else repr(child.before)
    print("========== last output tail ==========")
    print(tail)
    print("[RESULT] Experiment 05.1 FAILED")
finally:
    try:
        child.close(force=True)
    except Exception:
        pass
PY

echo
echo "========== memory after =========="
free -h
echo

echo "log saved to: $LOG"
