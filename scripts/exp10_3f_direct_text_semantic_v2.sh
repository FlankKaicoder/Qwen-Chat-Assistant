#!/usr/bin/env bash

set -u

PROJECT_DIR="/home/cat/ai/qwen3vl2b"
cd "$PROJECT_DIR" || exit 1

OUT_DIR="${1:-output/exp10_3f_direct_text_semantic_v2_$(date +%Y%m%d_%H%M%S)}"
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
from voice_assistant.controlled_session import (
    _build_concise_text_prompt,
)
from voice_assistant.orchestrator import VoiceAssistant


out_dir = Path(sys.argv[1])
out_dir.mkdir(parents=True, exist_ok=True)

cfg = load_config("config/default.yaml")
assistant = VoiceAssistant(cfg)

photo_dir = Path(cfg["paths"]["photo_dir"])


def photo_snapshot() -> dict[str, int]:
    result: dict[str, int] = {}

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
            result[str(path.resolve())] = (
                path.stat().st_mtime_ns
            )
        except FileNotFoundError:
            pass

    return result


def refusal_count(answer: str) -> int:
    phrases = (
        "无法处理",
        "无法提供",
        "不能回答",
        "不能处理",
        "信息不足",
        "提供具体问题",
        "提供更多上下文",
        "与RK3588设备无关",
    )

    return sum(
        phrase in answer
        for phrase in phrases
    )


def identity_semantic_ok(answer: str) -> bool:
    identity_terms = (
        "语音助手",
        "中文助手",
        "本地助手",
        "人工智能助手",
        "AI助手",
    )

    return any(
        term in answer
        for term in identity_terms
    )


def arithmetic_semantic_ok(answer: str) -> bool:
    compact = "".join(answer.split())

    patterns = (
        r"一加一(?:等于|是|为)[2二两]",
        r"1\+1(?:=|等于|是|为)[2二两]",
        r"(?:答案|结果)(?:是|为|等于)?[2二两]",
        r"^[2二两][。！!．]?$",
    )

    return any(
        re.search(pattern, compact)
        for pattern in patterns
    )


cases = (
    {
        "name": "identity",
        "question": "你是谁",
        "validator": identity_semantic_ok,
    },
    {
        "name": "arithmetic",
        "question": "一加一等于几",
        "validator": arithmetic_semantic_ok,
    },
)

before_all = photo_snapshot()
results = []

for case in cases:
    name = case["name"]
    question = case["question"]
    validator = case["validator"]

    case_dir = out_dir / name
    case_dir.mkdir(parents=True, exist_ok=True)

    prompt = _build_concise_text_prompt(
        question,
        80,
    )

    (case_dir / "question.txt").write_text(
        question + "\n",
        encoding="utf-8",
    )

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
            max_new_tokens=128,
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

    refusals = refusal_count(answer)
    semantic_ok = validator(answer)

    irrelevant_identity = False

    if name == "arithmetic":
        irrelevant_identity = any(
            phrase in answer
            for phrase in (
                "语音助手",
                "RK3588",
                "运行平台",
                "摄像头画面",
            )
        )

    status = "PASSED"

    if error:
        status = "EXCEPTION"
    elif not answer:
        status = "EMPTY_ANSWER"
    elif new_photos:
        status = "UNEXPECTED_CAMERA"
    elif refusals:
        status = "REFUSAL"
    elif irrelevant_identity:
        status = "IRRELEVANT_IDENTITY"
    elif not semantic_ok:
        status = "SEMANTIC_FAILED"

    result = {
        "name": name,
        "question": question,
        "status": status,
        "answer": answer,
        "answer_chars": len(answer),
        "elapsed_seconds": elapsed,
        "new_photo_count": len(new_photos),
        "refusal_count": refusals,
        "semantic_ok": semantic_ok,
        "irrelevant_identity": irrelevant_identity,
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
    ) as f:
        for key, value in result.items():
            if key == "answer":
                continue

            if isinstance(value, float):
                value = f"{value:.3f}"

            f.write(f"{key:<22}: {value}\n")

    print()
    print("=" * 60)
    print("case:", name)
    print("question:", question)
    print("prompt:")
    print(prompt)
    print()
    print("answer:", answer)
    print("status:", status)
    print("semantic_ok:", semantic_ok)
    print("elapsed_seconds:", f"{elapsed:.3f}")


after_all = photo_snapshot()

all_new_photos = [
    path
    for path, mtime in after_all.items()
    if path not in before_all
    or mtime > before_all[path]
]

case_passed = sum(
    item["status"] == "PASSED"
    for item in results
)

final_status = (
    "PASSED"
    if case_passed == len(results)
    and not all_new_photos
    else "FAILED"
)

summary = {
    "status": final_status,
    "case_total": len(results),
    "case_passed": case_passed,
    "new_photo_count": len(all_new_photos),
    "qwen_max_new_tokens": 128,
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
) as f:
    for key, value in summary.items():
        f.write(f"{key:<22}: {value}\n")

print()
print("========== final summary ==========")
print(
    (out_dir / "summary.txt").read_text(
        encoding="utf-8"
    )
)

if final_status != "PASSED":
    raise SystemExit(1)
PY

PYTHON_RC=$?

set -e

ps -eo pid,ppid,stat,etime,cmd \
    | grep -E \
      "voice_assistant.py|capture-photo.sh|v4l2-ctl|ffmpeg|/demo|imgenc" \
    | grep -v -E \
      "grep|exp10_3f_direct_text_semantic_v2" \
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
      "[RESULT] Experiment 10.3f PASSED_TEXT_SEMANTIC_2_CASES." \
      | tee "$OUT_DIR/result.txt"
else
    echo \
      "[RESULT] Experiment 10.3f FAILED_OR_NEEDS_CHECK." \
      | tee "$OUT_DIR/result.txt"
fi
