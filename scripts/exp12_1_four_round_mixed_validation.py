#!/usr/bin/env python3

from __future__ import annotations

import csv
import json
import os
import re
import selectors
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple


PROJECT_DIR = Path("/home/cat/ai/qwen3vl2b")
PHOTO_DIR = Path("/home/cat/图片")
PYTHON = PROJECT_DIR / ".venv/bin/python"

ROUNDS = [
    {
        "number": 1,
        "name": "visual_1",
        "expected_text": "看一下画面",
        "expected_photo": 1,
    },
    {
        "number": 2,
        "name": "text_math",
        "expected_text": "一加一等于几",
        "expected_photo": 0,
    },
    {
        "number": 3,
        "name": "visual_2",
        "expected_text": "拍照描述当前画面",
        "expected_photo": 1,
    },
    {
        "number": 4,
        "name": "text_identity",
        "expected_text": "你是谁",
        "expected_photo": 0,
    },
]


def read_text(path: Path) -> str:
    if not path.is_file():
        return ""
    return path.read_text(
        encoding="utf-8",
        errors="replace",
    ).strip()


def load_json(path: Path) -> Dict[str, Any]:
    if not path.is_file():
        return {}

    try:
        data = json.loads(
            path.read_text(
                encoding="utf-8",
                errors="replace",
            )
        )
    except Exception:
        return {}

    if isinstance(data, dict):
        return data

    return {"value": data}


def find_json_value(
    obj: Any,
    target_key: str,
) -> Any:
    if isinstance(obj, dict):
        if target_key in obj:
            return obj[target_key]

        for value in obj.values():
            result = find_json_value(
                value,
                target_key,
            )
            if result is not None:
                return result

    elif isinstance(obj, list):
        for value in obj:
            result = find_json_value(
                value,
                target_key,
            )
            if result is not None:
                return result

    return None


def first_json_value(
    obj: Any,
    keys: List[str],
) -> Any:
    for key in keys:
        value = find_json_value(obj, key)
        if value is not None:
            return value

    return None


def normalize_bool(value: Any) -> Optional[int]:
    if isinstance(value, bool):
        return int(value)

    if isinstance(value, int):
        return int(value != 0)

    if isinstance(value, str):
        normalized = value.strip().lower()

        if normalized in {
            "1",
            "true",
            "yes",
            "y",
        }:
            return 1

        if normalized in {
            "0",
            "false",
            "no",
            "n",
        }:
            return 0

    return None


def safe_float(value: Any) -> Optional[float]:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def photo_paths() -> Set[Path]:
    if not PHOTO_DIR.is_dir():
        return set()

    return {
        path.resolve()
        for path in PHOTO_DIR.glob("voice_*.jpg")
        if path.is_file()
    }


def mem_available_kb() -> int:
    path = Path("/proc/meminfo")

    if not path.is_file():
        return -1

    for line in path.read_text().splitlines():
        if line.startswith("MemAvailable:"):
            fields = line.split()
            if len(fields) >= 2:
                return int(fields[1])

    return -1


def allocated_file_handles() -> int:
    path = Path("/proc/sys/fs/file-nr")

    if not path.is_file():
        return -1

    fields = path.read_text().split()

    if not fields:
        return -1

    return int(fields[0])


def max_temperature_c() -> float:
    values: List[float] = []

    for path in Path(
        "/sys/class/thermal"
    ).glob("thermal_zone*/temp"):
        try:
            value = float(path.read_text().strip())
        except Exception:
            continue

        if value > 1000:
            value /= 1000.0

        values.append(value)

    if not values:
        return -1.0

    return max(values)


def residual_processes() -> List[str]:
    commands = [
        ["pgrep", "-a", "-x", "demo"],
        ["pgrep", "-a", "-x", "imgenc"],
        ["pgrep", "-a", "-x", "v4l2-ctl"],
        ["pgrep", "-a", "-x", "ffmpeg"],
        ["pgrep", "-a", "-x", "arecord"],
        ["pgrep", "-a", "-x", "aplay"],
        ["pgrep", "-a", "-f", "[v]oice_assistant.py"],
    ]

    results: List[str] = []

    for command in commands:
        completed = subprocess.run(
            command,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
        )

        for line in completed.stdout.splitlines():
            line = line.strip()
            if line and line not in results:
                results.append(line)

    return results


def snapshot() -> Dict[str, Any]:
    return {
        "time": time.strftime(
            "%Y-%m-%d %H:%M:%S"
        ),
        "mem_available_kb": mem_available_kb(),
        "allocated_file_handles":
            allocated_file_handles(),
        "max_temperature_c":
            round(max_temperature_c(), 1),
        "photo_count": len(photo_paths()),
        "residual_processes":
            residual_processes(),
    }


def run_streaming_command(
    command: List[str],
    log_path: Path,
    timeout_seconds: float,
) -> Tuple[int, float, bool]:
    log_path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    start = time.monotonic()
    timed_out = False

    process = subprocess.Popen(
        command,
        cwd=str(PROJECT_DIR),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        start_new_session=True,
        env=os.environ.copy(),
    )

    assert process.stdout is not None

    selector = selectors.DefaultSelector()
    selector.register(
        process.stdout,
        selectors.EVENT_READ,
    )

    with log_path.open(
        "w",
        encoding="utf-8",
    ) as log_file:
        while True:
            elapsed = time.monotonic() - start

            if (
                elapsed > timeout_seconds
                and process.poll() is None
            ):
                timed_out = True

                message = (
                    "\n[EXP12] command timeout; "
                    "terminating process group\n"
                )

                print(message, end="")
                log_file.write(message)
                log_file.flush()

                try:
                    os.killpg(
                        process.pid,
                        signal.SIGTERM,
                    )
                except ProcessLookupError:
                    pass

                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    try:
                        os.killpg(
                            process.pid,
                            signal.SIGKILL,
                        )
                    except ProcessLookupError:
                        pass

                break

            events = selector.select(timeout=0.5)

            for key, _ in events:
                line = key.fileobj.readline()

                if line:
                    print(line, end="", flush=True)
                    log_file.write(line)
                    log_file.flush()

            if process.poll() is not None:
                for line in process.stdout:
                    print(line, end="", flush=True)
                    log_file.write(line)

                break

    selector.close()

    if process.poll() is None:
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            pass

    elapsed = time.monotonic() - start

    if timed_out:
        return 124, elapsed, True

    return int(process.returncode or 0), elapsed, False


def format_optional_float(
    value: Optional[float],
) -> str:
    if value is None:
        return ""

    return f"{value:.3f}"


def get_git_branch() -> str:
    completed = subprocess.run(
        ["git", "branch", "--show-current"],
        cwd=str(PROJECT_DIR),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )

    return completed.stdout.strip()


def write_round_summary(
    path: Path,
    result: Dict[str, Any],
) -> None:
    lines = [
        f"round_number          : "
        f"{result['round_number']}",
        f"round_name            : "
        f"{result['round_name']}",
        f"expected_spoken_text  : "
        f"{result['expected_spoken_text']}",
        f"recognized_text       : "
        f"{result['recognized_text']}",
        f"expected_photo        : "
        f"{result['expected_photo']}",
        f"need_photo            : "
        f"{result['need_photo']}",
        f"actual_new_photo_count: "
        f"{result['actual_new_photo_count']}",
        f"new_photo_paths       : "
        f"{result['new_photo_paths']}",
        f"status                : "
        f"{result['status']}",
        f"return_code           : "
        f"{result['return_code']}",
        f"timed_out             : "
        f"{result['timed_out']}",
        f"answer_chars          : "
        f"{result['answer_chars']}",
        f"wall_elapsed_seconds  : "
        f"{result['wall_elapsed_seconds']}",
        f"pipeline_seconds      : "
        f"{result['pipeline_seconds']}",
        f"tts_seconds           : "
        f"{result['tts_seconds']}",
        f"underrun_count        : "
        f"{result['underrun_count']}",
        f"residual_process_count: "
        f"{result['residual_process_count']}",
        f"mem_before_kb         : "
        f"{result['mem_before_kb']}",
        f"mem_after_kb          : "
        f"{result['mem_after_kb']}",
        f"mem_delta_kb          : "
        f"{result['mem_delta_kb']}",
        f"fd_before             : "
        f"{result['fd_before']}",
        f"fd_after              : "
        f"{result['fd_after']}",
        f"temperature_before_c  : "
        f"{result['temperature_before_c']}",
        f"temperature_after_c   : "
        f"{result['temperature_after_c']}",
        f"manual_audio_ok       : "
        f"{result['manual_audio_ok']}",
        f"route_ok              : "
        f"{result['route_ok']}",
        f"round_result          : "
        f"{result['round_result']}",
    ]

    path.write_text(
        "\n".join(lines) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    if not PROJECT_DIR.is_dir():
        print(
            "[ERROR] project directory missing:",
            PROJECT_DIR,
        )
        return 0

    if not PYTHON.is_file():
        print(
            "[ERROR] project Python missing:",
            PYTHON,
        )
        return 0

    branch = get_git_branch()

    if branch != "exp/12-multiturn-stability":
        print(
            "[STOP] Current branch is not "
            "exp/12-multiturn-stability"
        )
        print("current_branch:", branch)
        return 0

    timestamp = time.strftime("%Y%m%d_%H%M%S")
    out_dir = (
        PROJECT_DIR
        / "output"
        / f"exp12_1_four_round_mixed_{timestamp}"
    )

    out_dir.mkdir(
        parents=True,
        exist_ok=False,
    )

    os.environ["PYTHONPATH"] = (
        f"{PROJECT_DIR}:"
        f"{PROJECT_DIR / '.python_packages'}"
    )

    results_jsonl = out_dir / "round_results.jsonl"
    results_tsv = out_dir / "round_results.tsv"

    overall_before = snapshot()
    all_results: List[Dict[str, Any]] = []

    print("=" * 68)
    print(
        " Experiment 12.1: Four-Round Mixed "
        "Voice Interaction Validation"
    )
    print("=" * 68)
    print("branch :", branch)
    print("out_dir:", out_dir)
    print()
    print("固定顺序：")
    print("  1. 看一下画面")
    print("  2. 一加一等于几")
    print("  3. 拍照描述当前画面")
    print("  4. 你是谁")
    print()
    print(
        "本实验跳过 KWS。每轮看到 RECORDING "
        "或录音提示后，再说出指定指令。"
    )
    print()

    tsv_fields = [
        "round_number",
        "round_name",
        "expected_spoken_text",
        "recognized_text",
        "expected_photo",
        "need_photo",
        "actual_new_photo_count",
        "status",
        "return_code",
        "timed_out",
        "answer_chars",
        "wall_elapsed_seconds",
        "pipeline_seconds",
        "tts_seconds",
        "underrun_count",
        "residual_process_count",
        "mem_before_kb",
        "mem_after_kb",
        "mem_delta_kb",
        "fd_before",
        "fd_after",
        "temperature_before_c",
        "temperature_after_c",
        "manual_audio_ok",
        "route_ok",
        "round_result",
    ]

    with results_tsv.open(
        "w",
        newline="",
        encoding="utf-8",
    ) as tsv_file:
        writer = csv.DictWriter(
            tsv_file,
            fieldnames=tsv_fields,
            delimiter="\t",
            extrasaction="ignore",
        )
        writer.writeheader()

    for specification in ROUNDS:
        round_number = int(specification["number"])
        round_name = str(specification["name"])
        expected_text = str(
            specification["expected_text"]
        )
        expected_photo = int(
            specification["expected_photo"]
        )

        round_dir = (
            out_dir
            / f"round_{round_number:02d}_{round_name}"
        )
        session_dir = round_dir / "session"

        round_dir.mkdir(
            parents=True,
            exist_ok=False,
        )
        session_dir.mkdir(
            parents=True,
            exist_ok=False,
        )

        print()
        print("=" * 68)
        print(
            f" Round {round_number}/4: "
            f"{round_name}"
        )
        print("=" * 68)
        print("请说：", expected_text)
        print(
            "按回车启动本轮。启动后不要马上说，"
            "看到 RECORDING 或录音提示后再说。"
        )

        try:
            input()
        except EOFError:
            print(
                "[STOP] Standard input closed; "
                "stopping experiment."
            )
            break

        before = snapshot()
        before_photos = photo_paths()

        command = [
            str(PYTHON),
            "voice_assistant.py",
            "listen-controlled",
            "--skip-wake",
            "--seconds",
            "5",
            "--prepare-delay",
            "2.0",
            "--out-dir",
            str(session_dir),
            "--answer-mode",
            "concise",
            "--answer-max-chars",
            "80",
            "--concise-max-new-tokens",
            "128",
        ]

        (round_dir / "command.txt").write_text(
            " ".join(command) + "\n",
            encoding="utf-8",
        )

        print()
        print("command:")
        print(" ".join(command))
        print()

        return_code, wall_elapsed, timed_out = (
            run_streaming_command(
                command=command,
                log_path=round_dir / "console.log",
                timeout_seconds=300,
            )
        )

        time.sleep(1.0)

        after = snapshot()
        after_photos = photo_paths()

        new_photos = sorted(
            after_photos - before_photos,
            key=lambda path: str(path),
        )

        summary_json = load_json(
            session_dir / "summary.json"
        )
        intent_json = load_json(
            session_dir / "intent_debug.json"
        )

        recognized_text = read_text(
            session_dir / "recognized_text.txt"
        ).replace("\n", " ")

        answer_text = read_text(
            session_dir / "qwen_answer.txt"
        )

        status_value = first_json_value(
            summary_json,
            ["status"],
        )
        status = (
            str(status_value)
            if status_value is not None
            else ""
        )

        need_photo_value = first_json_value(
            intent_json,
            [
                "need_photo",
                "photo_intent_hint",
                "heuristic_photo_hint",
            ],
        )
        need_photo = normalize_bool(
            need_photo_value
        )

        pipeline_seconds = safe_float(
            first_json_value(
                summary_json,
                ["pipeline_elapsed_seconds"],
            )
        )

        tts_seconds = safe_float(
            first_json_value(
                summary_json,
                ["tts_elapsed_seconds"],
            )
        )

        console_text = read_text(
            round_dir / "console.log"
        )

        underrun_count = len(
            re.findall(
                r"underrun!!!",
                console_text,
                flags=re.IGNORECASE,
            )
        )

        residual = after["residual_processes"]

        route_ok = int(
            need_photo == expected_photo
            and len(new_photos) == expected_photo
        )

        answer_chars = len(answer_text.strip())

        print()
        print("========== round automatic result ==========")
        print("recognized_text       :", recognized_text)
        print("expected_photo        :", expected_photo)
        print("need_photo            :", need_photo)
        print(
            "actual_new_photo_count:",
            len(new_photos),
        )
        print("new_photo_paths       :", [
            str(path)
            for path in new_photos
        ])
        print("answer_chars          :", answer_chars)
        print("status                :", status)
        print("return_code           :", return_code)
        print(
            "wall_elapsed_seconds  :",
            f"{wall_elapsed:.3f}",
        )
        print(
            "pipeline_seconds      :",
            format_optional_float(
                pipeline_seconds
            ),
        )
        print(
            "tts_seconds           :",
            format_optional_float(
                tts_seconds
            ),
        )
        print("underrun_count        :", underrun_count)
        print(
            "residual_process_count:",
            len(residual),
        )
        print("route_ok              :", route_ok)

        print()
        print(
            "是否听到语音回答，并且内容基本正确？"
            " 输入 y 或 n："
        )

        try:
            manual_value = input().strip().lower()
        except EOFError:
            manual_value = "n"

        manual_audio_ok = int(
            manual_value in {"y", "yes", "1"}
        )

        status_ok = status.upper() == "PASSED"

        round_pass = all([
            return_code == 0,
            not timed_out,
            status_ok,
            bool(recognized_text),
            answer_chars > 0,
            route_ok == 1,
            underrun_count == 0,
            len(residual) == 0,
            manual_audio_ok == 1,
        ])

        result: Dict[str, Any] = {
            "round_number": round_number,
            "round_name": round_name,
            "expected_spoken_text": expected_text,
            "recognized_text": recognized_text,
            "expected_photo": expected_photo,
            "need_photo": need_photo,
            "actual_new_photo_count":
                len(new_photos),
            "new_photo_paths": [
                str(path)
                for path in new_photos
            ],
            "status": status,
            "return_code": return_code,
            "timed_out": int(timed_out),
            "answer_chars": answer_chars,
            "wall_elapsed_seconds":
                round(wall_elapsed, 3),
            "pipeline_seconds":
                pipeline_seconds,
            "tts_seconds":
                tts_seconds,
            "underrun_count":
                underrun_count,
            "residual_process_count":
                len(residual),
            "residual_processes":
                residual,
            "mem_before_kb":
                before["mem_available_kb"],
            "mem_after_kb":
                after["mem_available_kb"],
            "mem_delta_kb":
                (
                    after["mem_available_kb"]
                    - before["mem_available_kb"]
                ),
            "fd_before":
                before["allocated_file_handles"],
            "fd_after":
                after["allocated_file_handles"],
            "temperature_before_c":
                before["max_temperature_c"],
            "temperature_after_c":
                after["max_temperature_c"],
            "manual_audio_ok":
                manual_audio_ok,
            "route_ok":
                route_ok,
            "round_result":
                "PASS" if round_pass else "FAIL",
        }

        all_results.append(result)

        with results_jsonl.open(
            "a",
            encoding="utf-8",
        ) as jsonl_file:
            jsonl_file.write(
                json.dumps(
                    result,
                    ensure_ascii=False,
                )
                + "\n"
            )

        with results_tsv.open(
            "a",
            newline="",
            encoding="utf-8",
        ) as tsv_file:
            writer = csv.DictWriter(
                tsv_file,
                fieldnames=tsv_fields,
                delimiter="\t",
                extrasaction="ignore",
            )
            writer.writerow(result)

        write_round_summary(
            round_dir / "round_summary.txt",
            result,
        )

        print()
        print(
            "[ROUND RESULT]",
            result["round_result"],
        )

        if return_code != 0 or timed_out:
            print(
                "[STOP] Command failure or timeout. "
                "Later rounds are not started."
            )
            break

        if residual:
            print(
                "[STOP] Residual processes detected. "
                "Later rounds are not started."
            )
            for line in residual:
                print("  ", line)
            break

    overall_after = snapshot()

    completed_count = len(all_results)
    pass_count = sum(
        result["round_result"] == "PASS"
        for result in all_results
    )

    visual_results = [
        result
        for result in all_results
        if result["expected_photo"] == 1
    ]
    text_results = [
        result
        for result in all_results
        if result["expected_photo"] == 0
    ]

    def average_wall(
        values: List[Dict[str, Any]],
    ) -> Optional[float]:
        if not values:
            return None

        return sum(
            float(value["wall_elapsed_seconds"])
            for value in values
        ) / len(values)

    visual_average = average_wall(
        visual_results
    )
    text_average = average_wall(
        text_results
    )

    visual_drift: Optional[float] = None
    text_drift: Optional[float] = None

    if len(visual_results) == 2:
        visual_drift = (
            float(
                visual_results[1][
                    "wall_elapsed_seconds"
                ]
            )
            - float(
                visual_results[0][
                    "wall_elapsed_seconds"
                ]
            )
        )

    if len(text_results) == 2:
        text_drift = (
            float(
                text_results[1][
                    "wall_elapsed_seconds"
                ]
            )
            - float(
                text_results[0][
                    "wall_elapsed_seconds"
                ]
            )
        )

    overall_result = (
        "PASS"
        if completed_count == 4
        and pass_count == 4
        and not overall_after[
            "residual_processes"
        ]
        else "FAIL"
    )

    summary = {
        "out_dir": str(out_dir),
        "branch": branch,
        "completed_round_count":
            completed_count,
        "passed_round_count":
            pass_count,
        "expected_round_count": 4,
        "visual_round_count":
            len(visual_results),
        "text_round_count":
            len(text_results),
        "visual_average_wall_seconds":
            visual_average,
        "text_average_wall_seconds":
            text_average,
        "visual_wall_drift_seconds":
            visual_drift,
        "text_wall_drift_seconds":
            text_drift,
        "mem_available_before_kb":
            overall_before["mem_available_kb"],
        "mem_available_after_kb":
            overall_after["mem_available_kb"],
        "mem_available_delta_kb":
            (
                overall_after["mem_available_kb"]
                - overall_before[
                    "mem_available_kb"
                ]
            ),
        "allocated_file_handles_before":
            overall_before[
                "allocated_file_handles"
            ],
        "allocated_file_handles_after":
            overall_after[
                "allocated_file_handles"
            ],
        "max_temperature_before_c":
            overall_before[
                "max_temperature_c"
            ],
        "max_temperature_after_c":
            overall_after[
                "max_temperature_c"
            ],
        "final_residual_process_count":
            len(
                overall_after[
                    "residual_processes"
                ]
            ),
        "result": overall_result,
    }

    (out_dir / "summary.json").write_text(
        json.dumps(
            summary,
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )

    summary_lines = [
        f"out_dir                       : "
        f"{summary['out_dir']}",
        f"branch                        : "
        f"{summary['branch']}",
        f"completed_round_count         : "
        f"{completed_count}",
        f"passed_round_count            : "
        f"{pass_count}",
        f"expected_round_count          : 4",
        f"visual_average_wall_seconds   : "
        f"{format_optional_float(visual_average)}",
        f"text_average_wall_seconds     : "
        f"{format_optional_float(text_average)}",
        f"visual_wall_drift_seconds     : "
        f"{format_optional_float(visual_drift)}",
        f"text_wall_drift_seconds       : "
        f"{format_optional_float(text_drift)}",
        f"mem_available_before_kb       : "
        f"{summary['mem_available_before_kb']}",
        f"mem_available_after_kb        : "
        f"{summary['mem_available_after_kb']}",
        f"mem_available_delta_kb        : "
        f"{summary['mem_available_delta_kb']}",
        f"allocated_file_handles_before : "
        f"{summary['allocated_file_handles_before']}",
        f"allocated_file_handles_after  : "
        f"{summary['allocated_file_handles_after']}",
        f"max_temperature_before_c      : "
        f"{summary['max_temperature_before_c']}",
        f"max_temperature_after_c       : "
        f"{summary['max_temperature_after_c']}",
        f"final_residual_process_count  : "
        f"{summary['final_residual_process_count']}",
        f"result                        : "
        f"{overall_result}",
    ]

    (out_dir / "summary.txt").write_text(
        "\n".join(summary_lines) + "\n",
        encoding="utf-8",
    )

    print()
    print("=" * 68)
    print(" Experiment 12.1 Final Summary")
    print("=" * 68)

    for line in summary_lines:
        print(line)

    print()

    if overall_result == "PASS":
        print(
            "[RESULT] Experiment 12.1 PASSED"
        )
    else:
        print(
            "[RESULT] Experiment 12.1 "
            "FAILED_OR_NEEDS_CHECK"
        )

    print()
    print("summary:", out_dir / "summary.txt")
    print("rounds :", results_tsv)

    # 始终返回 0，避免关闭用户当前交互终端。
    return 0


if __name__ == "__main__":
    sys.exit(main())
