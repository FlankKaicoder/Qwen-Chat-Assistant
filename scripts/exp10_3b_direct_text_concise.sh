#!/usr/bin/env bash

set -u

PROJECT_DIR="/home/cat/ai/qwen3vl2b"
cd "$PROJECT_DIR" || exit 1

OUT_DIR="${1:-output/exp10_3b_direct_text_concise_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT_DIR"

PYTHON_BIN="$PROJECT_DIR/.venv/bin/python"

export PYTHONPATH="$PROJECT_DIR:$PROJECT_DIR/.python_packages${PYTHONPATH:+:$PYTHONPATH}"

STDOUT_LOG="$OUT_DIR/stdout.log"
STDERR_LOG="$OUT_DIR/stderr.log"

set +e

timeout --signal=INT --kill-after=10 120 \
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

recognized_text = "你是谁"

prompt = (
    "你是运行在RK3588设备上的本地中文语音助手，"
    "能够进行普通问答和摄像头画面描述。"
    "请根据用户问题直接给出最终答案，"
    "不要解释分析过程，"
    "不要使用标题、列表或分点，"
    "使用一到两句自然中文，"
    "尽量控制在80个汉字以内。\n"
    f"用户问题：{recognized_text}"
)

(out_dir / "recognized_text.txt").write_text(
    recognized_text + "\n",
    encoding="utf-8",
)

(out_dir / "qwen_prompt.txt").write_text(
    prompt + "\n",
    encoding="utf-8",
)

photo_dir = Path(cfg["paths"]["photo_dir"])


def snapshot():
    result = {}

    if not photo_dir.exists():
        return result

    for path in photo_dir.iterdir():
        if (
            path.is_file()
            and path.suffix.lower()
            in {".jpg", ".jpeg", ".png"}
        ):
            try:
                result[str(path.resolve())] = (
                    path.stat().st_mtime_ns
                )
            except FileNotFoundError:
                pass

    return result


before = snapshot()

start = time.monotonic()

answer = assistant.run_once_from_text(
    prompt,
    speak=False,
    play=False,
    max_new_tokens=128,
    need_photo_override=False,
)

elapsed = time.monotonic() - start

answer = str(answer or "").strip()

after = snapshot()

new_photos = [
    path
    for path, mtime in after.items()
    if path not in before or mtime > before[path]
]

(out_dir / "qwen_answer.txt").write_text(
    answer + "\n",
    encoding="utf-8",
)

bad_phrases = (
    "无法提供",
    "信息不足",
    "提供更多上下文",
    "无法查看",
)

bad_answer_count = sum(
    phrase in answer
    for phrase in bad_phrases
)

identity_keyword_count = sum(
    keyword in answer
    for keyword in (
        "助手",
        "语音",
        "人工智能",
        "AI",
        "RK3588",
    )
)

summary = {
    "status": "PASSED",
    "recognized_text": recognized_text,
    "need_photo_override": False,
    "qwen_max_new_tokens": 128,
    "prompt_chars": len(prompt),
    "answer_chars": len(answer),
    "pipeline_elapsed_seconds": elapsed,
    "new_photo_count": len(new_photos),
    "bad_answer_count": bad_answer_count,
    "identity_keyword_count": identity_keyword_count,
}

if not answer:
    summary["status"] = "EMPTY_ANSWER"
elif new_photos:
    summary["status"] = "UNEXPECTED_CAMERA"
elif bad_answer_count:
    summary["status"] = "BAD_ANSWER"
elif identity_keyword_count == 0:
    summary["status"] = "IDENTITY_NOT_CLEAR"

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

        f.write(f"{key:<28}: {value}\n")

print()
print("========== answer ==========")
print(answer)

print()
print("========== summary ==========")
print(
    (out_dir / "summary.txt").read_text(
        encoding="utf-8"
    )
)

if summary["status"] != "PASSED":
    raise SystemExit(1)
PY

PYTHON_RC=$?

set -e

ps -eo pid,ppid,stat,etime,cmd \
    | grep -E \
      "voice_assistant.py|capture-photo.sh|v4l2-ctl|ffmpeg|/demo|imgenc" \
    | grep -v -E \
      "grep|exp10_3b_direct_text_concise" \
    > "$OUT_DIR/residual_processes.txt" || true

RESIDUAL_COUNT=$(
    wc -l < "$OUT_DIR/residual_processes.txt"
)

{
    echo "python_return_code     : $PYTHON_RC"
    echo "residual_process_count: $RESIDUAL_COUNT"
} | tee "$OUT_DIR/process_result.txt"

if [ "$PYTHON_RC" -eq 0 ] \
  && [ "$RESIDUAL_COUNT" -eq 0 ]; then

    echo "[RESULT] Experiment 10.3b PASSED_DIRECT_TEXT_CONCISE."
else
    echo "[RESULT] Experiment 10.3b FAILED_OR_NEEDS_CHECK."
fi
