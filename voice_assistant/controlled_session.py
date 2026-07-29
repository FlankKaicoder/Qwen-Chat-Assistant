from __future__ import annotations

import json
import math
import shutil
import sys
import time
import traceback
import wave
from array import array
from datetime import datetime
from pathlib import Path
from typing import Any


def _now_text() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]


def _session_timestamp() -> str:
    return datetime.now().strftime("%Y%m%d_%H%M%S")


def _state(out_dir: Path, name: str, detail: str = "") -> None:
    line = f"{_now_text()} [STATE] {name}"
    if detail:
        line += f" | {detail}"

    print(line, flush=True)

    with (out_dir / "state.log").open("a", encoding="utf-8") as f:
        f.write(line + "\n")


def _write_text(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")


def _audio_stats(wav_path: Path) -> dict[str, Any]:
    result: dict[str, Any] = {
        "wav_path": str(wav_path),
        "channels": 0,
        "sample_rate": 0,
        "sample_width": 0,
        "frames": 0,
        "duration_seconds": 0.0,
        "sample_count": 0,
        "peak": 0,
        "peak_ratio": 0.0,
        "rms": 0.0,
        "rms_ratio": 0.0,
        "mean_volume_dbfs": None,
        "max_volume_dbfs": None,
    }

    with wave.open(str(wav_path), "rb") as wf:
        channels = wf.getnchannels()
        sample_rate = wf.getframerate()
        sample_width = wf.getsampwidth()
        frames = wf.getnframes()
        raw = wf.readframes(frames)

    result["channels"] = channels
    result["sample_rate"] = sample_rate
    result["sample_width"] = sample_width
    result["frames"] = frames

    if sample_rate > 0:
        result["duration_seconds"] = frames / sample_rate

    if sample_width != 2:
        result["note"] = (
            f"Only 16-bit PCM statistics are implemented; "
            f"sample_width={sample_width}"
        )
        return result

    samples = array("h")
    samples.frombytes(raw)

    if sys.byteorder == "big":
        samples.byteswap()

    count = len(samples)
    result["sample_count"] = count

    if count == 0:
        return result

    peak = max(abs(int(x)) for x in samples)
    square_sum = sum(float(x) * float(x) for x in samples)
    rms = math.sqrt(square_sum / count)

    full_scale = 32768.0
    peak_ratio = peak / full_scale
    rms_ratio = rms / full_scale

    result["peak"] = peak
    result["peak_ratio"] = peak_ratio
    result["rms"] = rms
    result["rms_ratio"] = rms_ratio

    if rms_ratio > 0:
        result["mean_volume_dbfs"] = 20.0 * math.log10(rms_ratio)

    if peak_ratio > 0:
        result["max_volume_dbfs"] = 20.0 * math.log10(peak_ratio)

    return result


def _photo_snapshot(photo_dir: Path) -> dict[str, int]:
    result: dict[str, int] = {}

    if not photo_dir.exists():
        return result

    suffixes = {".jpg", ".jpeg", ".png", ".bmp"}

    for path in photo_dir.iterdir():
        if not path.is_file():
            continue
        if path.suffix.lower() not in suffixes:
            continue

        try:
            result[str(path.resolve())] = path.stat().st_mtime_ns
        except FileNotFoundError:
            continue

    return result


def _new_photos(
    before: dict[str, int],
    after: dict[str, int],
) -> list[str]:
    changed: list[str] = []

    for path, mtime_ns in after.items():
        old_mtime = before.get(path)
        if old_mtime is None or mtime_ns > old_mtime:
            changed.append(path)

    changed.sort(key=lambda p: after.get(p, 0))
    return changed


def _photo_intent_hint(text: str) -> bool:
    keywords = (
        "拍照",
        "照片",
        "画面",
        "摄像头",
        "看一下",
        "看下",
        "看看",
        "描述一下",
        "前面有什么",
    )
    return any(keyword in text for keyword in keywords)


def _format_optional_float(value: Any) -> str:
    if value is None:
        return ""
    return f"{float(value):.3f}"


def _write_summary(out_dir: Path, summary: dict[str, Any]) -> None:
    json_path = out_dir / "summary.json"
    txt_path = out_dir / "summary.txt"

    json_path.write_text(
        json.dumps(summary, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    ordered_keys = [
        "status",
        "exit_code",
        "out_dir",
        "wake_mode",
        "wake_timeout",
        "wake_text",
        "skip_wake",
        "prepare_delay",
        "record_seconds",
        "command_wav",
        "audio_duration_seconds",
        "mean_volume_dbfs",
        "max_volume_dbfs",
        "recognized_text",
        "recognized_chars",
        "photo_intent_hint",
        "new_photo_count",
        "new_photo_path",
        "answer_chars",
        "speak",
        "play",
        "elapsed_seconds",
        "error",
    ]

    lines: list[str] = []

    for key in ordered_keys:
        value = summary.get(key, "")

        if key in {
            "audio_duration_seconds",
            "mean_volume_dbfs",
            "max_volume_dbfs",
            "elapsed_seconds",
        }:
            value = _format_optional_float(value)

        lines.append(f"{key:<23}: {value}")

    txt_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def run_controlled_session(assistant: Any, args: Any) -> int:
    start_monotonic = time.monotonic()

    project_dir = Path(
        assistant.config.get("paths", {}).get(
            "project_dir",
            "/home/cat/ai/qwen3vl2b",
        )
    )

    if args.out_dir:
        out_dir = Path(args.out_dir)
        if not out_dir.is_absolute():
            out_dir = project_dir / out_dir
    else:
        out_dir = (
            project_dir
            / "output"
            / f"exp10_controlled_session_{_session_timestamp()}"
        )

    out_dir.mkdir(parents=True, exist_ok=True)

    photo_dir = Path(
        assistant.config.get("paths", {}).get(
            "photo_dir",
            "/home/cat/图片",
        )
    )

    summary: dict[str, Any] = {
        "status": "RUNNING",
        "exit_code": 1,
        "out_dir": str(out_dir),
        "wake_mode": args.wake_mode,
        "wake_timeout": args.wake_timeout,
        "wake_text": "",
        "skip_wake": int(bool(args.skip_wake)),
        "prepare_delay": float(args.prepare_delay),
        "record_seconds": int(args.seconds),
        "command_wav": str(out_dir / "command.wav"),
        "audio_duration_seconds": None,
        "mean_volume_dbfs": None,
        "max_volume_dbfs": None,
        "recognized_text": "",
        "recognized_chars": 0,
        "photo_intent_hint": 0,
        "new_photo_count": 0,
        "new_photo_path": "",
        "answer_chars": 0,
        "speak": int(not args.no_speak),
        "play": int(not args.no_play),
        "elapsed_seconds": None,
        "error": "",
    }

    command_wav = out_dir / "command.wav"
    recognized_text_path = out_dir / "recognized_text.txt"
    answer_path = out_dir / "qwen_answer.txt"
    error_path = out_dir / "error.log"

    exit_code = 1

    try:
        if args.skip_wake:
            summary["wake_text"] = "SKIPPED"
            _state(out_dir, "WAKE_SKIPPED")
        else:
            _state(
                out_dir,
                "WAIT_WAKE",
                f"mode={args.wake_mode}, timeout={args.wake_timeout}s",
            )
            print("[PROMPT] 请说唤醒词。", flush=True)

            wake_text = assistant.wait_for_wake(
                mode=args.wake_mode,
                timeout=args.wake_timeout,
            )

            wake_text = str(wake_text or "").strip()
            summary["wake_text"] = wake_text

            if not wake_text:
                summary["status"] = "WAKE_TIMEOUT"
                exit_code = 2
                _state(out_dir, "WAKE_TIMEOUT")
                return exit_code

            _state(out_dir, "WAKE_DETECTED", wake_text)

        _state(
            out_dir,
            "PREPARE_RECORD",
            f"delay={float(args.prepare_delay):.3f}s",
        )

        print(
            f"[PROMPT] 唤醒成功，"
            f"{float(args.prepare_delay):.1f} 秒后开始录音。",
            flush=True,
        )

        if args.prepare_delay > 0:
            time.sleep(float(args.prepare_delay))

        _state(
            out_dir,
            "RECORDING",
            f"seconds={int(args.seconds)}",
        )
        print("[PROMPT] 请现在说出命令。", flush=True)

        temp_wav = Path(assistant.record_command(int(args.seconds)))

        if not temp_wav.exists():
            raise FileNotFoundError(
                f"record command returned missing WAV: {temp_wav}"
            )

        if temp_wav.resolve() != command_wav.resolve():
            shutil.copy2(temp_wav, command_wav)
            temp_wav.unlink(missing_ok=True)
        else:
            command_wav = temp_wav

        summary["command_wav"] = str(command_wav)

        audio_stats = _audio_stats(command_wav)

        (out_dir / "audio_stats.json").write_text(
            json.dumps(audio_stats, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

        summary["audio_duration_seconds"] = audio_stats.get(
            "duration_seconds"
        )
        summary["mean_volume_dbfs"] = audio_stats.get(
            "mean_volume_dbfs"
        )
        summary["max_volume_dbfs"] = audio_stats.get(
            "max_volume_dbfs"
        )

        print(
            "[AUDIO] "
            f"duration={audio_stats.get('duration_seconds', 0):.3f}s, "
            f"mean={_format_optional_float(audio_stats.get('mean_volume_dbfs'))} dBFS, "
            f"max={_format_optional_float(audio_stats.get('max_volume_dbfs'))} dBFS",
            flush=True,
        )

        _state(out_dir, "ASR", str(command_wav))

        recognized_text = str(
            assistant.transcribe_wav(command_wav) or ""
        ).strip()

        summary["recognized_text"] = recognized_text
        summary["recognized_chars"] = len(recognized_text)
        summary["photo_intent_hint"] = int(
            _photo_intent_hint(recognized_text)
        )

        _write_text(recognized_text_path, recognized_text + "\n")

        print(f"[ASR] {recognized_text}", flush=True)

        if not recognized_text:
            summary["status"] = "EMPTY_ASR"
            exit_code = 3
            _state(out_dir, "EMPTY_ASR")
            return exit_code

        photo_before = _photo_snapshot(photo_dir)

        _state(
            out_dir,
            "INTENT_DISPATCH",
            f"photo_hint={summary['photo_intent_hint']}",
        )
        _state(out_dir, "QWEN_TTS")

        answer = assistant.run_once_from_text(
            recognized_text,
            speak=not args.no_speak,
            play=not args.no_play,
        )

        answer = str(answer or "").strip()
        summary["answer_chars"] = len(answer)
        _write_text(answer_path, answer + "\n")

        photo_after = _photo_snapshot(photo_dir)
        new_photos = _new_photos(photo_before, photo_after)

        summary["new_photo_count"] = len(new_photos)

        if new_photos:
            summary["new_photo_path"] = new_photos[-1]

        print("[ANSWER]", flush=True)
        print(answer, flush=True)

        if not answer:
            summary["status"] = "EMPTY_ANSWER"
            exit_code = 4
            _state(out_dir, "EMPTY_ANSWER")
            return exit_code

        summary["status"] = "PASSED"
        exit_code = 0

        _state(
            out_dir,
            "COMPLETED",
            (
                f"answer_chars={len(answer)}, "
                f"new_photo_count={len(new_photos)}"
            ),
        )

        return exit_code

    except KeyboardInterrupt:
        summary["status"] = "INTERRUPTED"
        summary["error"] = "KeyboardInterrupt"
        exit_code = 130
        _state(out_dir, "INTERRUPTED")
        return exit_code

    except BaseException as exc:
        summary["status"] = "FAILED"
        summary["error"] = f"{type(exc).__name__}: {exc}"
        exit_code = 1

        tb = traceback.format_exc()
        _write_text(error_path, tb)

        print(tb, file=sys.stderr, flush=True)
        _state(
            out_dir,
            "FAILED",
            summary["error"],
        )

        return exit_code

    finally:
        summary["exit_code"] = exit_code
        summary["elapsed_seconds"] = (
            time.monotonic() - start_monotonic
        )

        _write_summary(out_dir, summary)

        print(
            f"[SUMMARY] {out_dir / 'summary.txt'}",
            flush=True,
        )

        if summary["status"] == "PASSED":
            print(
                "[RESULT] listen-controlled PASSED",
                flush=True,
            )
        else:
            print(
                f"[RESULT] listen-controlled {summary['status']}",
                flush=True,
            )
