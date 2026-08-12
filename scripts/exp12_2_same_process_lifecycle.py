#!/usr/bin/env python3

from __future__ import annotations

import csv
import gc
import json
import os
import statistics
import subprocess
import sys
import time
import traceback
from pathlib import Path
from typing import Any, Dict, List


PROJECT_DIR = Path("/home/cat/ai/qwen3vl2b")
PHOTO_DIR = Path("/home/cat/图片")

VISUAL_TEXT = (
    "看一下画面，用一句中文简短描述"
    "画面中最主要的人物、物体和场景。"
)

TEXT_TEXT = (
    "一加一等于几？"
    "只用一句中文简短回答。"
)

ROUND_COUNT = int(
    os.environ.get(
        "EXP12_ROUND_COUNT",
        "10",
    )
)

MAX_NEW_TOKENS = int(
    os.environ.get(
        "EXP12_MAX_NEW_TOKENS",
        "96",
    )
)

OUTPUT_PREFIX = os.environ.get(
    "EXP12_OUTPUT_PREFIX",
    "exp12_2_same_process_lifecycle",
)


def mem_available_kb() -> int:
    for line in Path("/proc/meminfo").read_text().splitlines():
        if line.startswith("MemAvailable:"):
            return int(line.split()[1])
    return -1


def self_rss_kb() -> int:
    for line in Path("/proc/self/status").read_text().splitlines():
        if line.startswith("VmRSS:"):
            return int(line.split()[1])
    return -1


def self_fd_count() -> int:
    return len(list(Path("/proc/self/fd").iterdir()))


def self_thread_count() -> int:
    return len(list(Path("/proc/self/task").iterdir()))


def max_temperature_c() -> float:
    values: List[float] = []

    for path in Path("/sys/class/thermal").glob(
        "thermal_zone*/temp"
    ):
        try:
            value = float(path.read_text().strip())

            if value > 1000:
                value /= 1000.0

            values.append(value)
        except Exception:
            pass

    return max(values) if values else -1.0


def photo_set() -> set[Path]:
    if not PHOTO_DIR.is_dir():
        return set()

    return {
        path.resolve()
        for path in PHOTO_DIR.glob("voice_*.jpg")
        if path.is_file()
    }


def residual_processes() -> List[str]:
    commands = [
        ["pgrep", "-a", "-x", "demo"],
        ["pgrep", "-a", "-x", "imgenc"],
        ["pgrep", "-a", "-x", "v4l2-ctl"],
        ["pgrep", "-a", "-x", "ffmpeg"],
        ["pgrep", "-a", "-x", "arecord"],
        ["pgrep", "-a", "-x", "aplay"],
    ]

    found: List[str] = []

    for command in commands:
        result = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
        )

        for line in result.stdout.splitlines():
            line = line.strip()

            if line and line not in found:
                found.append(line)

    return found


def snapshot() -> Dict[str, Any]:
    return {
        "rss_kb": self_rss_kb(),
        "fd_count": self_fd_count(),
        "thread_count": self_thread_count(),
        "mem_available_kb": mem_available_kb(),
        "temperature_c": round(
            max_temperature_c(),
            1,
        ),
        "photo_count": len(photo_set()),
    }


def wait_for_residual_cleanup(
    timeout_seconds: float = 10.0,
    interval_seconds: float = 0.5,
):
    initial = residual_processes()

    if not initial:
        return initial, [], 0.0

    start = time.monotonic()
    current = list(initial)

    while current:
        elapsed = time.monotonic() - start

        if elapsed >= timeout_seconds:
            break

        time.sleep(interval_seconds)
        current = residual_processes()

    elapsed = time.monotonic() - start

    return initial, current, elapsed


def median(values: List[float]) -> float:
    if not values:
        return -1.0
    return float(statistics.median(values))


def main() -> int:
    os.chdir(PROJECT_DIR)

    branch = subprocess.run(
        ["git", "branch", "--show-current"],
        stdout=subprocess.PIPE,
        text=True,
        check=False,
    ).stdout.strip()

    if branch != "exp/12-multiturn-stability":
        print(
            "[STOP] wrong branch:",
            branch,
        )
        return 0

    timestamp = time.strftime("%Y%m%d_%H%M%S")
    out_dir = (
        PROJECT_DIR
        / "output"
        / f"{OUTPUT_PREFIX}_{timestamp}"
    )
    out_dir.mkdir(parents=True)

    print("=" * 72)
    print(
        " Experiment 12.2: Same-Process "
        "10-Round Lifecycle Stability"
    )
    print("=" * 72)
    print("pid         :", os.getpid())
    print("branch      :", branch)
    print("out_dir     :", out_dir)
    print("round_count :", ROUND_COUNT)
    print()

    from voice_assistant.config import load_config
    from voice_assistant.orchestrator import VoiceAssistant

    print("========== initialize VoiceAssistant once ==========")

    init_start = time.monotonic()

    config = load_config("config/default.yaml")
    assistant = VoiceAssistant(config)

    init_elapsed = time.monotonic() - init_start

    print(f"assistant_init_seconds={init_elapsed:.3f}")
    print()

    gc.collect()

    baseline = snapshot()
    baseline_photos = photo_set()

    print("========== same-process baseline ==========")
    print(json.dumps(
        baseline,
        ensure_ascii=False,
        indent=2,
    ))
    print()

    rows: List[Dict[str, Any]] = []
    stopped_early = False

    for index in range(1, ROUND_COUNT + 1):
        is_visual = index % 2 == 1

        route_name = (
            "visual"
            if is_visual
            else "text"
        )

        text = (
            VISUAL_TEXT
            if is_visual
            else TEXT_TEXT
        )

        expected_photo = (
            1
            if is_visual
            else 0
        )

        print()
        print("=" * 72)
        print(
            f" Round {index:02d}/{ROUND_COUNT} "
            f"[{route_name}]"
        )
        print("=" * 72)
        print("input:", text)

        before = snapshot()
        photos_before = photo_set()

        intent = assistant.intent.analyze(text)

        print("intent.need_photo :", intent.need_photo)
        print(
            "intent.matched_rule:",
            getattr(
                intent,
                "matched_rule",
                "",
            ),
        )

        start = time.monotonic()

        answer = ""
        exception_text = ""

        try:
            answer = assistant.run_once_from_text(
                text,
                speak=True,
                play=True,
                max_new_tokens=MAX_NEW_TOKENS,
            )
        except Exception:
            exception_text = traceback.format_exc()
            print(exception_text)

        elapsed = time.monotonic() - start

        # 尽量清理当前轮已经无引用对象，
        # 但不会影响真正仍被长期对象持有的泄漏。
        gc.collect()
        time.sleep(1.0)

        after = snapshot()
        photos_after = photo_set()

        new_photos = sorted(
            photos_after - photos_before,
            key=str,
        )

        residual_initial, residual, cleanup_seconds = (
            wait_for_residual_cleanup(
                timeout_seconds=10.0,
                interval_seconds=0.5,
            )
        )

        route_ok = (
            bool(intent.need_photo)
            == bool(expected_photo)
            and len(new_photos)
            == expected_photo
        )

        if is_visual:
            semantic_ok = (
                bool(answer.strip())
                and "无法查看" not in answer
                and "无法看到" not in answer
                and "不能查看" not in answer
                and "没有图片" not in answer
            )
        else:
            semantic_ok = any(
                token in answer
                for token in [
                    "2",
                    "二",
                    "两",
                ]
            )

        fd_delta = (
            after["fd_count"]
            - baseline["fd_count"]
        )

        thread_delta = (
            after["thread_count"]
            - baseline["thread_count"]
        )

        rss_delta_kb = (
            after["rss_kb"]
            - baseline["rss_kb"]
        )

        round_pass = all([
            not exception_text,
            route_ok,
            semantic_ok,
            len(residual) == 0,
        ])

        row = {
            "round": index,
            "route": route_name,
            "input": text,
            "expected_photo":
                expected_photo,
            "intent_need_photo":
                int(bool(intent.need_photo)),
            "matched_rule":
                getattr(
                    intent,
                    "matched_rule",
                    "",
                ),
            "new_photo_count":
                len(new_photos),
            "new_photo_paths":
                [
                    str(path)
                    for path in new_photos
                ],
            "answer_chars":
                len(answer.strip()),
            "answer":
                answer.strip(),
            "elapsed_seconds":
                round(elapsed, 3),
            "rss_before_kb":
                before["rss_kb"],
            "rss_after_kb":
                after["rss_kb"],
            "rss_delta_from_baseline_kb":
                rss_delta_kb,
            "fd_before":
                before["fd_count"],
            "fd_after":
                after["fd_count"],
            "fd_delta_from_baseline":
                fd_delta,
            "threads_before":
                before["thread_count"],
            "threads_after":
                after["thread_count"],
            "thread_delta_from_baseline":
                thread_delta,
            "mem_available_before_kb":
                before["mem_available_kb"],
            "mem_available_after_kb":
                after["mem_available_kb"],
            "temperature_before_c":
                before["temperature_c"],
            "temperature_after_c":
                after["temperature_c"],
            "residual_initial_count":
                len(residual_initial),
            "residual_initial_processes":
                residual_initial,
            "residual_cleanup_seconds":
                round(cleanup_seconds, 3),
            "residual_process_count":
                len(residual),
            "residual_processes":
                residual,
            "route_ok":
                int(route_ok),
            "semantic_ok":
                int(semantic_ok),
            "exception":
                exception_text,
            "round_result":
                "PASS"
                if round_pass
                else "FAIL",
        }

        rows.append(row)

        (out_dir / f"round_{index:02d}.json").write_text(
            json.dumps(
                row,
                ensure_ascii=False,
                indent=2,
            ) + "\n",
            encoding="utf-8",
        )

        (out_dir / f"round_{index:02d}_answer.txt").write_text(
            answer,
            encoding="utf-8",
        )

        print()
        print("---------- result ----------")
        print("answer_chars        :", row["answer_chars"])
        print("elapsed_seconds     :", row["elapsed_seconds"])
        print("new_photo_count     :", row["new_photo_count"])
        print("route_ok            :", row["route_ok"])
        print("semantic_ok         :", row["semantic_ok"])
        print("rss_after_kb        :", row["rss_after_kb"])
        print(
            "rss_delta_baseline  :",
            row["rss_delta_from_baseline_kb"],
        )
        print("fd_after            :", row["fd_after"])
        print(
            "fd_delta_baseline   :",
            row["fd_delta_from_baseline"],
        )
        print("threads_after       :", row["threads_after"])
        print(
            "thread_delta_baseline:",
            row["thread_delta_from_baseline"],
        )
        print(
            "residual_initial    :",
            row["residual_initial_count"],
        )
        print(
            "cleanup_seconds     :",
            row["residual_cleanup_seconds"],
        )
        print(
            "residual_after_wait :",
            row["residual_process_count"],
        )

        if row["residual_initial_processes"]:
            print(
                "initial_processes  :",
                row["residual_initial_processes"],
            )

        print(
            "temperature_after_c :",
            row["temperature_after_c"],
        )
        print("round_result        :", row["round_result"])

        if exception_text:
            print(
                "[STOP] exception occurred; "
                "later rounds are skipped"
            )
            stopped_early = True
            break

        if residual:
            print(
                "[STOP] residual child process "
                "detected"
            )

            for process in residual:
                print("  ", process)

            stopped_early = True
            break

    gc.collect()
    time.sleep(1.0)

    final = snapshot()

    (
        final_residual_initial,
        final_residual,
        final_cleanup_seconds,
    ) = wait_for_residual_cleanup(
        timeout_seconds=10.0,
        interval_seconds=0.5,
    )

    final_photos = photo_set()

    csv_fields = [
        "round",
        "route",
        "expected_photo",
        "intent_need_photo",
        "matched_rule",
        "new_photo_count",
        "answer_chars",
        "elapsed_seconds",
        "rss_before_kb",
        "rss_after_kb",
        "rss_delta_from_baseline_kb",
        "fd_before",
        "fd_after",
        "fd_delta_from_baseline",
        "threads_before",
        "threads_after",
        "thread_delta_from_baseline",
        "mem_available_before_kb",
        "mem_available_after_kb",
        "temperature_before_c",
        "temperature_after_c",
        "residual_initial_count",
        "residual_cleanup_seconds",
        "residual_process_count",
        "route_ok",
        "semantic_ok",
        "round_result",
    ]

    with (out_dir / "rounds.tsv").open(
        "w",
        newline="",
        encoding="utf-8",
    ) as file:
        writer = csv.DictWriter(
            file,
            fieldnames=csv_fields,
            delimiter="\t",
            extrasaction="ignore",
        )

        writer.writeheader()

        for row in rows:
            writer.writerow(row)

    visual_times = [
        float(row["elapsed_seconds"])
        for row in rows
        if row["route"] == "visual"
    ]

    text_times = [
        float(row["elapsed_seconds"])
        for row in rows
        if row["route"] == "text"
    ]

    pass_count = sum(
        row["round_result"] == "PASS"
        for row in rows
    )

    final_fd_delta = (
        final["fd_count"]
        - baseline["fd_count"]
    )

    final_thread_delta = (
        final["thread_count"]
        - baseline["thread_count"]
    )

    final_rss_delta_kb = (
        final["rss_kb"]
        - baseline["rss_kb"]
    )

    expected_total_photos = sum(
        1
        for i in range(1, ROUND_COUNT + 1)
        if i % 2 == 1
    )

    actual_total_new_photos = len(
        final_photos - baseline_photos
    )

    # FD 和线程是强判据。
    fd_ok = final_fd_delta <= 2
    thread_ok = final_thread_delta <= 1

    # RSS 不采用绝对严格 FAIL：
    # Python/ONNX allocator 可能保留已经释放的 heap。
    # 超过 200 MB 记为 warning。
    rss_warning = (
        final_rss_delta_kb
        > 200 * 1024
    )

    overall_pass = all([
        len(rows) == ROUND_COUNT,
        pass_count == ROUND_COUNT,
        not stopped_early,
        fd_ok,
        thread_ok,
        len(final_residual) == 0,
        actual_total_new_photos
            == expected_total_photos,
    ])

    summary = {
        "pid": os.getpid(),
        "branch": branch,
        "round_count_expected":
            ROUND_COUNT,
        "round_count_completed":
            len(rows),
        "round_pass_count":
            pass_count,
        "visual_round_count":
            len(visual_times),
        "text_round_count":
            len(text_times),
        "visual_median_seconds":
            round(
                median(visual_times),
                3,
            ),
        "text_median_seconds":
            round(
                median(text_times),
                3,
            ),
        "visual_first_seconds":
            visual_times[0]
            if visual_times else None,
        "visual_last_seconds":
            visual_times[-1]
            if visual_times else None,
        "text_first_seconds":
            text_times[0]
            if text_times else None,
        "text_last_seconds":
            text_times[-1]
            if text_times else None,
        "baseline_rss_kb":
            baseline["rss_kb"],
        "final_rss_kb":
            final["rss_kb"],
        "final_rss_delta_kb":
            final_rss_delta_kb,
        "rss_warning":
            int(rss_warning),
        "baseline_fd_count":
            baseline["fd_count"],
        "final_fd_count":
            final["fd_count"],
        "final_fd_delta":
            final_fd_delta,
        "fd_ok":
            int(fd_ok),
        "baseline_thread_count":
            baseline["thread_count"],
        "final_thread_count":
            final["thread_count"],
        "final_thread_delta":
            final_thread_delta,
        "thread_ok":
            int(thread_ok),
        "baseline_mem_available_kb":
            baseline["mem_available_kb"],
        "final_mem_available_kb":
            final["mem_available_kb"],
        "baseline_temperature_c":
            baseline["temperature_c"],
        "final_temperature_c":
            final["temperature_c"],
        "expected_total_new_photos":
            expected_total_photos,
        "actual_total_new_photos":
            actual_total_new_photos,
        "final_residual_initial_count":
            len(final_residual_initial),
        "final_residual_cleanup_seconds":
            round(final_cleanup_seconds, 3),
        "final_residual_process_count":
            len(final_residual),
        "result":
            "PASS"
            if overall_pass
            else "FAIL",
    }

    (out_dir / "summary.json").write_text(
        json.dumps(
            summary,
            ensure_ascii=False,
            indent=2,
        ) + "\n",
        encoding="utf-8",
    )

    lines = [
        f"out_dir                       : {out_dir}",
        f"pid                           : {summary['pid']}",
        f"branch                        : {branch}",
        f"round_count_expected          : {ROUND_COUNT}",
        f"round_count_completed         : {len(rows)}",
        f"round_pass_count              : {pass_count}",
        f"visual_median_seconds         : {summary['visual_median_seconds']}",
        f"text_median_seconds           : {summary['text_median_seconds']}",
        f"visual_first_seconds          : {summary['visual_first_seconds']}",
        f"visual_last_seconds           : {summary['visual_last_seconds']}",
        f"text_first_seconds            : {summary['text_first_seconds']}",
        f"text_last_seconds             : {summary['text_last_seconds']}",
        f"baseline_rss_kb               : {summary['baseline_rss_kb']}",
        f"final_rss_kb                  : {summary['final_rss_kb']}",
        f"final_rss_delta_kb            : {summary['final_rss_delta_kb']}",
        f"rss_warning                   : {summary['rss_warning']}",
        f"baseline_fd_count             : {summary['baseline_fd_count']}",
        f"final_fd_count                : {summary['final_fd_count']}",
        f"final_fd_delta                : {summary['final_fd_delta']}",
        f"fd_ok                         : {summary['fd_ok']}",
        f"baseline_thread_count         : {summary['baseline_thread_count']}",
        f"final_thread_count            : {summary['final_thread_count']}",
        f"final_thread_delta            : {summary['final_thread_delta']}",
        f"thread_ok                     : {summary['thread_ok']}",
        f"baseline_mem_available_kb     : {summary['baseline_mem_available_kb']}",
        f"final_mem_available_kb        : {summary['final_mem_available_kb']}",
        f"baseline_temperature_c        : {summary['baseline_temperature_c']}",
        f"final_temperature_c           : {summary['final_temperature_c']}",
        f"expected_total_new_photos     : {summary['expected_total_new_photos']}",
        f"actual_total_new_photos       : {summary['actual_total_new_photos']}",
        f"final_residual_initial_count  : {summary['final_residual_initial_count']}",
        f"final_cleanup_seconds         : {summary['final_residual_cleanup_seconds']}",
        f"final_residual_process_count  : {summary['final_residual_process_count']}",
        f"result                        : {summary['result']}",
    ]

    (out_dir / "summary.txt").write_text(
        "\n".join(lines) + "\n",
        encoding="utf-8",
    )

    print()
    print("=" * 72)
    print(" Experiment 12.2 Final Summary")
    print("=" * 72)

    for line in lines:
        print(line)

    if overall_pass:
        print()
        print("[RESULT] Experiment 12.2 PASSED")
    else:
        print()
        print(
            "[RESULT] Experiment 12.2 "
            "FAILED_OR_NEEDS_CHECK"
        )

    if rss_warning:
        print(
            "[WARN] same-process RSS increased "
            "by more than 200 MB"
        )

    # 避免关闭交互终端。
    return 0


if __name__ == "__main__":
    sys.exit(main())
