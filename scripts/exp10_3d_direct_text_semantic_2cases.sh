#!/usr/bin/env bash

set -u

PROJECT_DIR="/home/cat/ai/qwen3vl2b"
cd "$PROJECT_DIR" || exit 1

OUT_DIR="${1:-output/exp10_3d_direct_text_semantic_2cases_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT_DIR"

PYTHON_BIN="$PROJECT_DIR/.venv/bin/python"

export PYTHONPATH="$PROJECT_DIR:$PROJECT_DIR/.python_packages${PYTHONPATH:+:$PYTHONPATH}"

STDOUT_LOG="$OUT_DIR/stdout.log"
STDERR_LOG="$OUT_DIR/stderr.log"

set +e

timeout --signal=INT --kill-after=10 180 \
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


def snapshot() -> dict[str, int]:
    result: dict[str, int] = {}

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


def build_prompt(question: str) -> str:
    return (
        "你是一个本地中文语音助手，"
        "运行平台是RK3588。"
        "RK3588只是运行平台，"
        "不限制你回答问题的范围。"
        "你可以正常回答日常常识、计算和一般问题，"
        "也可以在需要时描述摄像头画面。"
        "如果用户询问你是谁，"
        "请明确说明你是本地中文语音助手。"
        "请直接给出最终答案，"
        "不要解释分析过程，"
        "不要使用标题、列表或分点，"
        "使用一到两句自然中文，"
        "尽量控制在80个汉字以内。\n"
        f"用户问题：{question}"
    )


refusal_phrases = (
    "无法处理",
    "无法提供",
    "不能处理",
    "信息不足",
    "提供具体问题",
    "提供更多上下文",
    "与RK3588设备无关",
)

cases = [
    {
        "name": "identity",
        "question": "你是谁",
    },
    {
        "name": "arithmetic",
        "question": "一加一等于几",
    },
]

before_all = snapshot()
results = []

for case in cases:
    name = case["name"]
    question = case["question"]
    case_dir = out_dir / name
    case_dir.mkdir(parents=True, exist_ok=True)

    prompt = build_prompt(question)

    (case_dir / "question.txt").write_text(
        question + "\n",
        encoding="utf-8",
    )

    (case_dir / "qwen_prompt.txt").write_text(
        prompt + "\n",
        encoding="utf-8",
    )

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

    refusal_count = sum(
        phrase in answer
        for phrase in refusal_phrases
    )

    if name == "identity":
        semantic_ok = (
            any(
                keyword in answer
                for keyword in (
                    "语音助手",
                    "中文助手",
                    "人工智能助手",
                    "AI助手",
                    "本地助手",
                )
            )
            and refusal_count == 0
        )
    else:
        semantic_ok = (
            any(
                token in answer
                for token in (
                    "2",
                    "二",
                    "两",
                )
            )
            and refusal_count == 0
        )

    status = "PASSED"

    if not answer:
        status = "EMPTY_ANSWER"
    elif new_photos:
        status = "UNEXPECTED_CAMERA"
    elif refusal_count:
        status = "REFUSAL_ANSWER"
    elif not semantic_ok:
        status = "SEMANTIC_FAILED"

    (case_dir / "qwen_answer.txt").write_text(
        answer + "\n",
        encoding="utf-8",
    )

    result = {
        "name": name,
        "question": question,
        "status": status,
        "answer": answer,
        "answer_chars": len(answer),
        "elapsed_seconds": elapsed,
        "new_photo_count": len(new_photos),
        "refusal_count": refusal_count,
        "semantic_ok": semantic_ok,
    }

    results.append(result)

    (case_dir / "summary.json").write_text(
        json.dumps(
            result,
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )

    with (case_dir / "summary.txt").open(
        "w",
        encoding="utf-8",
    ) as f:
        for key, value in result.items():
            if key == "answer":
                continue

            if isinstance(value, float):
                value = f"{value:.3f}"

            f.write(f"{key:<20}: {value}\n")

after_all = snapshot()

all_new_photos = [
    path
    for path, mtime in after_all.items()
    if path not in before_all
    or mtime > before_all[path]
]

passed_count = sum(
    result["status"] == "PASSED"
    for result in results
)

summary = {
    "status": (
        "PASSED"
        if passed_count == len(results)
        and not all_new_photos
        else "FAILED"
    ),
    "case_total": len(results),
    "case_passed": passed_count,
    "new_photo_count": len(all_new_photos),
    "results": results,
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
    f.write(f"status           : {summary['status']}\n")
    f.write(f"case_total       : {summary['case_total']}\n")
    f.write(f"case_passed      : {summary['case_passed']}\n")
    f.write(
        f"new_photo_count  : "
        f"{summary['new_photo_count']}\n"
    )

for result in results:
    print()
    print(
        "=================================================="
    )
    print("case:", result["name"])
    print("question:", result["question"])
    print("answer:", result["answer"])
    print("status:", result["status"])
    print(
        "elapsed_seconds:",
        f"{result['elapsed_seconds']:.3f}",
    )

print()
print("========== final summary ==========")
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
      "grep|exp10_3d_direct_text_semantic_2cases" \
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

    echo "[RESULT] Experiment 10.3d PASSED_TEXT_SEMANTIC_2_CASES."
else
    echo "[RESULT] Experiment 10.3d FAILED_OR_NEEDS_CHECK."
fi
