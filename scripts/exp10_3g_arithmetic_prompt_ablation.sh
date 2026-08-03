#!/usr/bin/env bash

set -u

PROJECT_DIR="/home/cat/ai/qwen3vl2b"
cd "$PROJECT_DIR" || exit 1

OUT_DIR="${1:-output/exp10_3g_arithmetic_prompt_ablation_$(date +%Y%m%d_%H%M%S)}"
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
import re
import sys
import time

from voice_assistant.config import load_config
from voice_assistant.orchestrator import VoiceAssistant


out_dir = Path(sys.argv[1])
out_dir.mkdir(parents=True, exist_ok=True)

cfg = load_config("config/default.yaml")
assistant = VoiceAssistant(cfg)

photo_dir = Path(cfg["paths"]["photo_dir"])


def photo_snapshot() -> dict[str, int]:
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


def arithmetic_ok(answer: str) -> bool:
    compact = "".join(answer.split())

    patterns = (
        r"一加一(?:等于|是|为)?[2二两]",
        r"1\s*\+\s*1\s*(?:=|等于|是|为)?\s*[2二两]",
        r"(?:答案|结果)(?:是|为|等于)?[2二两]",
        r"^[2二两][。！!．]?$",
    )

    return any(
        re.search(pattern, compact)
        for pattern in patterns
    )


cases = (
    {
        "name": "natural",
        "prompt": "请简短回答这个问题：一加一等于几？",
    },
    {
        "name": "qa_format",
        "prompt": (
            "问题：一加一等于几？\n"
            "答案："
        ),
    },
    {
        "name": "numeric_constraint",
        "prompt": "计算1+1，只输出最终数字。",
    },
)

before_all = photo_snapshot()
results = []

for case in cases:
    name = case["name"]
    prompt = case["prompt"]

    case_dir = out_dir / name
    case_dir.mkdir(parents=True, exist_ok=True)

    (case_dir / "qwen_prompt.txt").write_text(
        prompt + "\n",
        encoding="utf-8",
    )

    before = photo_snapshot()
    start = time.monotonic()

    try:
        answer = assistant.run_once_from_text(
            prompt,
            speak=False,
            play=False,
            max_new_tokens=32,
            need_photo_override=False,
        )
        error = ""
    except Exception as exc:
        answer = ""
        error = f"{type(exc).__name__}: {exc}"

    elapsed = time.monotonic() - start
    answer = str(answer or "").strip()

    after = photo_snapshot()

    new_photos = [
        path
        for path, mtime in after.items()
        if path not in before
        or mtime > before[path]
    ]

    contains_platform_topic = any(
        token in answer
        for token in (
            "RK3588",
            "ARM",
            "芯片",
            "语音助手",
            "运行平台",
            "摄像头",
        )
    )

    semantic_ok = arithmetic_ok(answer)

    status = "PASSED"

    if error:
        status = "EXCEPTION"
    elif not answer:
        status = "EMPTY_ANSWER"
    elif new_photos:
        status = "UNEXPECTED_CAMERA"
    elif contains_platform_topic:
        status = "PLATFORM_DISTRACTION"
    elif not semantic_ok:
        status = "SEMANTIC_FAILED"

    result = {
        "name": name,
        "status": status,
        "prompt": prompt,
        "answer": answer,
        "answer_chars": len(answer),
        "elapsed_seconds": elapsed,
        "new_photo_count": len(new_photos),
        "semantic_ok": semantic_ok,
        "contains_platform_topic": contains_platform_topic,
        "error": error,
    }

    results.append(result)

    (case_dir / "qwen_answer.txt").write_text(
        answer + "\n",
        encoding="utf-8",
    )

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
    ) as file:
        for key, value in result.items():
            if key in {"prompt", "answer"}:
                continue

            if isinstance(value, float):
                value = f"{value:.3f}"

            file.write(f"{key:<26}: {value}\n")

    print()
    print("=" * 60)
    print("case:", name)
    print("prompt:", prompt)
    print("answer:", answer)
    print("status:", status)
    print("semantic_ok:", semantic_ok)
    print(
        "contains_platform_topic:",
        contains_platform_topic,
    )
    print("elapsed_seconds:", f"{elapsed:.3f}")


after_all = photo_snapshot()

all_new_photos = [
    path
    for path, mtime in after_all.items()
    if path not in before_all
    or mtime > before_all[path]
]

passed_cases = [
    result["name"]
    for result in results
    if result["status"] == "PASSED"
]

summary = {
    "status": (
        "PASSED"
        if passed_cases and not all_new_photos
        else "FAILED"
    ),
    "case_total": len(results),
    "case_passed": len(passed_cases),
    "passed_cases": passed_cases,
    "new_photo_count": len(all_new_photos),
    "qwen_max_new_tokens": 32,
}

(out_dir / "summary.json").write_text(
    json.dumps(
        {
            **summary,
            "results": results,
        },
        ensure_ascii=False,
        indent=2,
    ),
    encoding="utf-8",
)

with (out_dir / "summary.txt").open(
    "w",
    encoding="utf-8",
) as file:
    for key, value in summary.items():
        file.write(f"{key:<24}: {value}\n")

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
      "grep|exp10_3g_arithmetic_prompt_ablation" \
    > "$OUT_DIR/residual_processes.txt" || true

RESIDUAL_COUNT=$(
    wc -l < "$OUT_DIR/residual_processes.txt"
)

grep -nEi \
"error|failed|traceback|timeout|timed out|killed|oom" \
"$STDOUT_LOG" "$STDERR_LOG" \
> "$OUT_DIR/abnormal.txt" || true

{
    echo "python_return_code      : $PYTHON_RC"
    echo "residual_process_count : $RESIDUAL_COUNT"
} | tee "$OUT_DIR/process_result.txt"

if [ "$PYTHON_RC" -eq 0 ] \
  && [ "$RESIDUAL_COUNT" -eq 0 ]; then

    echo \
      "[RESULT] Experiment 10.3g PROMPT_ABLATION_PASSED." \
      | tee "$OUT_DIR/result.txt"
else
    echo \
      "[RESULT] Experiment 10.3g FAILED_OR_NEEDS_CHECK." \
      | tee "$OUT_DIR/result.txt"
fi
