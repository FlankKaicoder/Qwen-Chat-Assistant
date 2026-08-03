#!/usr/bin/env bash

set -u

PROJECT_DIR="/home/cat/ai/qwen3vl2b"
cd "$PROJECT_DIR" || exit 1

OUT_DIR="${1:-output/exp10_2fe_direct_visual_concise_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT_DIR"

PYTHON_BIN="$PROJECT_DIR/.venv/bin/python"

export PYTHONPATH="$PROJECT_DIR:$PROJECT_DIR/.python_packages${PYTHONPATH:+:$PYTHONPATH}"

STDOUT_LOG="$OUT_DIR/stdout.log"
STDERR_LOG="$OUT_DIR/stderr.log"

set +e

timeout --signal=INT --kill-after=10 150 \
"$PYTHON_BIN" - "$OUT_DIR" \
    > >(tee "$STDOUT_LOG") \
    2> >(tee "$STDERR_LOG" >&2) <<'PY'
from pathlib import Path
import json
import sys
import time

from voice_assistant.config import load_config
from voice_assistant.orchestrator import VoiceAssistant


out_dir = Path(sys.argv[1])
out_dir.mkdir(parents=True, exist_ok=True)

cfg = load_config("config/default.yaml")
assistant = VoiceAssistant(cfg)

photo_dir = Path(cfg["paths"]["photo_dir"])

def snapshot():
    result = {}

    if not photo_dir.exists():
        return result

    for path in photo_dir.iterdir():
        if not path.is_file():
            continue

        if path.suffix.lower() not in {
            ".jpg",
            ".jpeg",
            ".png",
        }:
            continue

        try:
            result[str(path.resolve())] = path.stat().st_mtime_ns
        except FileNotFoundError:
            pass

    return result


prompt = (
    "请根据当前摄像头拍摄的图片，"
    "直接描述画面中最主要的人物、物体和场景。"
    "只输出一到两句中文结论，"
    "不要解释推理过程，"
    "不要使用标题、列表或分点，"
    "不要说无法查看图片，"
    "尽量控制在80个汉字以内。"
)

(out_dir / "qwen_prompt.txt").write_text(
    prompt + "\n",
    encoding="utf-8",
)

before = snapshot()

start = time.monotonic()

answer = assistant.run_once_from_text(
    prompt,
    force_photo=True,
    speak=False,
    play=False,
    max_new_tokens=128,
)

elapsed = time.monotonic() - start

answer = str(answer or "").strip()

after = snapshot()

new_photos = [
    path
    for path, mtime in after.items()
    if path not in before or mtime > before[path]
]

new_photos.sort(
    key=lambda path: after.get(path, 0)
)

new_photo_path = new_photos[-1] if new_photos else ""

(out_dir / "qwen_answer.txt").write_text(
    answer + "\n",
    encoding="utf-8",
)

summary = {
    "status": "PASSED" if answer and new_photo_path else "FAILED",
    "qwen_max_new_tokens": 128,
    "prompt_chars": len(prompt),
    "answer_chars": len(answer),
    "pipeline_elapsed_seconds": elapsed,
    "new_photo_count": len(new_photos),
    "new_photo_path": new_photo_path,
}

(out_dir / "summary.json").write_text(
    json.dumps(
        summary,
        ensure_ascii=False,
        indent=2,
    ),
    encoding="utf-8",
)

with (out_dir / "summary.txt").open(
    "w",
    encoding="utf-8",
) as f:
    for key, value in summary.items():
        if isinstance(value, float):
            value = f"{value:.3f}"
        f.write(f"{key:<27}: {value}\n")

print()
print("========== answer ==========")
print(answer)

print()
print("========== summary ==========")
print((out_dir / "summary.txt").read_text(encoding="utf-8"))

if summary["status"] != "PASSED":
    raise SystemExit(1)
PY

RC=$?

set -e

echo "python_return_code: $RC" \
    | tee "$OUT_DIR/process_result.txt"

ps -eo pid,ppid,stat,etime,cmd \
    | grep -E \
      "voice_assistant.py|capture-photo.sh|v4l2-ctl|ffmpeg|/demo|imgenc" \
    | grep -v -E \
      "grep|exp10_2fe_direct_visual_concise" \
    > "$OUT_DIR/residual_processes.txt" || true

RESIDUAL_COUNT=$(
    wc -l < "$OUT_DIR/residual_processes.txt"
)

echo "residual_process_count: $RESIDUAL_COUNT" \
    | tee -a "$OUT_DIR/process_result.txt"

if [ "$RC" -eq 0 ] \
  && [ "$RESIDUAL_COUNT" -eq 0 ]; then
    echo "[RESULT] Experiment 10.2f-e PASSED."
else
    echo "[RESULT] Experiment 10.2f-e FAILED_OR_NEEDS_CHECK."
fi
