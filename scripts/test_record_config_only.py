#!/usr/bin/env python3
import argparse
import os
import subprocess
import sys
import wave
from pathlib import Path

import yaml


def run(cmd):
    print("[CMD]", " ".join(str(x) for x in cmd), flush=True)
    return subprocess.run(cmd, check=True)


def wav_info(path: Path):
    with wave.open(str(path), "rb") as w:
        print("----- wav info by python wave -----")
        print("path       :", path)
        print("channels   :", w.getnchannels())
        print("sample_rate:", w.getframerate())
        print("sample_width:", w.getsampwidth())
        print("frames     :", w.getnframes())
        print("duration_s :", round(w.getnframes() / float(w.getframerate()), 3))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default="config/default.yaml")
    ap.add_argument("--seconds", type=int, default=5)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    cfg_path = Path(args.config)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)

    cfg = yaml.safe_load(cfg_path.read_text())
    audio = cfg["audio"]

    mic_device = str(audio.get("mic_device", "plughw:2,0"))
    sample_rate = int(audio.get("sample_rate", 16000))
    channels = int(audio.get("channels", 1))
    input_channel = str(audio.get("input_channel", "left"))
    gain = float(audio.get("asr_input_gain", 1.0))

    print("========== config audio ==========")
    print("mic_device   :", mic_device)
    print("sample_rate  :", sample_rate)
    print("channels     :", channels)
    print("input_channel:", input_channel)
    print("asr_gain     :", gain)
    print("seconds      :", args.seconds)
    print("out          :", out)

    raw = out.with_suffix(".raw_capture.wav")

    # 先严格按 config 里的 channels 录原始音频。
    run([
        "arecord",
        "-D", mic_device,
        "-f", "S16_LE",
        "-r", str(sample_rate),
        "-c", str(channels),
        "-d", str(args.seconds),
        str(raw),
    ])

    # 如果项目配置是双声道，按照 input_channel 提取单声道。
    # 这一步模拟项目里“channels: 2 + input_channel: left”的设计意图。
    if channels == 1:
        if gain != 1.0:
            run([
                "ffmpeg", "-y", "-hide_banner",
                "-i", str(raw),
                "-af", f"volume={gain}",
                str(out),
            ])
        else:
            raw.replace(out)
    else:
        if input_channel.lower() in ("left", "l", "0"):
            pan = "mono|c0=c0"
        elif input_channel.lower() in ("right", "r", "1"):
            pan = "mono|c0=c1"
        else:
            print(f"[WARN] unknown input_channel={input_channel}, fallback to left")
            pan = "mono|c0=c0"

        run([
            "ffmpeg", "-y", "-hide_banner",
            "-i", str(raw),
            "-af", f"pan={pan},volume={gain}",
            "-ar", str(sample_rate),
            "-ac", "1",
            str(out),
        ])

    if not out.exists():
        raise RuntimeError(f"output wav not found: {out}")

    wav_info(out)
    print("[OK] record config only done")


if __name__ == "__main__":
    main()
