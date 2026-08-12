#!/usr/bin/env python3

from __future__ import annotations

import os
import subprocess
import time
from pathlib import Path


PROJECT = Path("/home/cat/ai/qwen3vl2b")


def get_demo_processes():
    result = subprocess.run(
        [
            "ps",
            "-eo",
            "pid=,ppid=,pgid=,sid=,stat=,etime=,comm=,args=",
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )

    rows = []

    for line in result.stdout.splitlines():
        if " demo " in f" {line} ":
            rows.append(line.strip())

    return rows


def dump_proc(pid: int):
    proc = Path(f"/proc/{pid}")

    print(f"----- /proc/{pid} -----")

    if not proc.exists():
        print("process_exists=0")
        return

    print("process_exists=1")

    status = proc / "status"

    if status.is_file():
        wanted = {
            "Name",
            "State",
            "Pid",
            "PPid",
            "TracerPid",
            "Threads",
        }

        for line in status.read_text(
            errors="replace"
        ).splitlines():
            key = line.split(":", 1)[0]

            if key in wanted:
                print(line)

    try:
        print(
            "wchan:",
            (proc / "wchan").read_text().strip(),
        )
    except Exception as exc:
        print("wchan_error:", repr(exc))

    try:
        data = (
            proc / "cmdline"
        ).read_bytes().replace(b"\0", b" ")

        print(
            "cmdline:",
            data.decode(
                "utf-8",
                errors="replace",
            ),
        )
    except Exception as exc:
        print("cmdline_error:", repr(exc))


def extract_pid(line: str):
    try:
        return int(line.split()[0])
    except Exception:
        return None


def main():
    os.chdir(PROJECT)

    from voice_assistant.config import load_config
    from voice_assistant.qwen_runner import QwenRunner

    config = load_config("config/default.yaml")

    print("=" * 70)
    print("Experiment 12.2b Qwen demo lifecycle probe")
    print("=" * 70)
    print("parent_pid:", os.getpid())

    before = get_demo_processes()

    print()
    print("========== demo before ==========")

    if before:
        for line in before:
            print(line)
    else:
        print("none")

    runner = QwenRunner(config)

    print()
    print("========== running Qwen ==========")

    start = time.monotonic()

    answer = runner.ask(
        PROJECT / "demo.jpg",
        "请简短回答：一加一等于几？",
    )

    elapsed = time.monotonic() - start

    print()
    print("========== Qwen returned ==========")
    print("elapsed_seconds:", round(elapsed, 3))
    print("answer:", answer)
    print("parent_pid:", os.getpid())

    for sec in [0, 1, 2, 5, 10, 15, 20]:
        if sec:
            previous = checkpoints[-1]
            time.sleep(sec - previous)

        checkpoints.append(sec)

        print()
        print(
            f"========== after return +{sec}s =========="
        )

        rows = get_demo_processes()

        if not rows:
            print("demo_count=0")
            continue

        print("demo_count:", len(rows))

        for line in rows:
            print("ps:", line)

            pid = extract_pid(line)

            if pid is not None:
                dump_proc(pid)

    print()
    print("========== parent exits now ==========")


checkpoints = []


if __name__ == "__main__":
    main()
