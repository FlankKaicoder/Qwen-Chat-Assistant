from __future__ import annotations

import argparse
import sys
from pathlib import Path


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Local Chinese voice-photo Qwen assistant")
    parser.add_argument("--config", default=None, help="Path to YAML config")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("record", help="Record one temporary command WAV")
    p.add_argument("--seconds", type=int, default=None)
    p.add_argument("--out", default=None)

    p = sub.add_parser("stt", help="Transcribe a WAV file")
    p.add_argument("wav")

    p = sub.add_parser("tts-stream", help="Synthesize text and stream raw PCM to speaker")
    p.add_argument("text")

    sub.add_parser("camera", help="Capture one photo")

    p = sub.add_parser("wake", help="Wait for wake keyword")
    p.add_argument("--mode", choices=("kws", "stt"), default="kws")
    p.add_argument("--timeout", type=int, default=None)

    p = sub.add_parser("kws-file", help="Detect configured wake keyword in a WAV file")
    p.add_argument("wav")

    p = sub.add_parser("ask", help="Ask Qwen from text")
    p.add_argument("text")
    p.add_argument("--image", default=None)
    p.add_argument("--force-photo", action="store_true")
    p.add_argument("--no-speak", action="store_true")
    p.add_argument("--no-play", action="store_true")

    p = sub.add_parser("once", help="Record, transcribe, ask Qwen, synthesize and play")
    p.add_argument("--seconds", type=int, default=None)
    p.add_argument("--no-speak", action="store_true")
    p.add_argument("--no-play", action="store_true")

    p = sub.add_parser("listen", help="Wait for wake keyword, then run one command")
    p.add_argument("--wake-mode", choices=("kws", "stt"), default="kws")
    p.add_argument("--wake-timeout", type=int, default=None)
    p.add_argument("--seconds", type=int, default=None)
    p.add_argument("--no-speak", action="store_true")
    p.add_argument("--no-play", action="store_true")

    p = sub.add_parser("listen-forever", help="Keep waiting for wake keyword and run commands")
    p.add_argument("--wake-mode", choices=("kws", "stt"), default="kws")
    p.add_argument("--wake-timeout", type=int, default=None)
    p.add_argument("--seconds", type=int, default=None)
    p.add_argument("--no-speak", action="store_true")
    p.add_argument("--no-play", action="store_true")

    p = sub.add_parser(
        "listen-controlled",
        help="Stable KWS -> record -> ASR -> Qwen/TTS session with debug artifacts",
    )
    p.add_argument("--wake-mode", choices=["kws", "stt"], default="kws")
    p.add_argument("--wake-timeout", type=int, default=25)
    p.add_argument("--seconds", type=int, default=5)
    p.add_argument("--prepare-delay", type=float, default=0.8)
    p.add_argument("--skip-wake", action="store_true")
    p.add_argument("--out-dir")
    p.add_argument("--no-speak", action="store_true")
    p.add_argument("--no-play", action="store_true")
    p.add_argument(
        "--answer-mode",
        choices=["normal", "concise"],
        default="normal",
        help="Use normal or concise Qwen response prompt",
    )
    p.add_argument(
        "--answer-max-chars",
        type=int,
        default=80,
        help="Suggested maximum Chinese characters in concise mode",
    )
    p.add_argument(
        "--concise-max-new-tokens",
        type=int,
        default=128,
        help="Qwen generation token limit used by concise mode",
    )

    sub.add_parser("cleanup", help="Clean temporary files")
    return parser


def _record_without_heavy_import(args: argparse.Namespace) -> None:
    """Lightweight record command.

    目的：
    record 子命令只验证录音链路，不应该提前导入 ASR / Qwen / TTS。
    因此这里不导入 orchestrator.py，也不依赖 sherpa_onnx。
    """
    import subprocess
    import wave
    import yaml

    config_path = Path(args.config) if args.config else Path("config/default.yaml")
    cfg = yaml.safe_load(config_path.read_text())
    audio = cfg.get("audio", {})

    mic_device = str(audio.get("mic_device", "plughw:2,0"))
    sample_rate = int(audio.get("sample_rate", 16000))
    channels = int(audio.get("channels", 1))
    input_channel = str(audio.get("input_channel", "left"))
    gain = float(audio.get("asr_input_gain", 1.0))

    seconds = int(args.seconds) if args.seconds is not None else int(audio.get("command_seconds", 5))

    if args.out:
        out = Path(args.out)
    else:
        out = Path(cfg.get("paths", {}).get("temp_dir", "/tmp/qwen_voice_assistant")) / "command.wav"

    out.parent.mkdir(parents=True, exist_ok=True)
    raw = out.with_name(out.stem + ".raw_capture.wav")

    print("========== lightweight record ==========")
    print("config       :", config_path)
    print("mic_device   :", mic_device)
    print("sample_rate  :", sample_rate)
    print("channels     :", channels)
    print("input_channel:", input_channel)
    print("asr_gain     :", gain)
    print("seconds      :", seconds)
    print("raw          :", raw)
    print("out          :", out)

    cmd = [
        "arecord",
        "-D", mic_device,
        "-f", "S16_LE",
        "-r", str(sample_rate),
        "-c", str(channels),
        "-d", str(seconds),
        str(raw),
    ]
    print("[CMD]", " ".join(cmd), flush=True)
    subprocess.run(cmd, check=True)

    if channels == 1:
        if gain != 1.0:
            cmd = [
                "ffmpeg", "-y", "-hide_banner",
                "-i", str(raw),
                "-af", f"volume={gain}",
                "-ar", str(sample_rate),
                "-ac", "1",
                str(out),
            ]
            print("[CMD]", " ".join(cmd), flush=True)
            subprocess.run(cmd, check=True)
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

        cmd = [
            "ffmpeg", "-y", "-hide_banner",
            "-i", str(raw),
            "-af", f"pan={pan},volume={gain}",
            "-ar", str(sample_rate),
            "-ac", "1",
            str(out),
        ]
        print("[CMD]", " ".join(cmd), flush=True)
        subprocess.run(cmd, check=True)

    with wave.open(str(out), "rb") as w:
        print("========== output wav ==========")
        print("path        :", out)
        print("channels    :", w.getnchannels())
        print("sample_rate :", w.getframerate())
        print("sample_width:", w.getsampwidth())
        print("frames      :", w.getnframes())
        print("duration_s  :", round(w.getnframes() / float(w.getframerate()), 3))

    print(out)



def _ask_without_heavy_import(args: argparse.Namespace) -> None:
    """Lightweight ask command.

    目的：
    ask --no-speak --no-play 只验证 QwenRunner / Qwen3-VL 推理链路，
    不应该提前构造完整 VoiceAssistant，
    也不应该导入 orchestrator -> asr -> sherpa_onnx。
    """
    from .config import load_config
    from .qwen_runner import QwenRunner

    config = load_config(args.config)
    qwen = config.get("qwen", {})
    paths = config.get("paths", {})

    image_path = args.image

    if args.force_photo:
        from .camera import CameraAdapter
        image_path = str(CameraAdapter(config).capture())

    if not image_path:
        image_path = paths.get("placeholder_image", "demo.jpg")

    text = args.text

    # 当前 demo 的图像触发标记是 <image>。
    # 当用户显式传入 --image 或 --force-photo 时，如果文本里还没有 <image>，
    # 这里自动补上，避免图像没有真正被模型使用。
    marker = qwen.get("demo_image_marker", "<image>")
    if (args.image or args.force_photo) and marker and marker not in text:
        text = marker + text

    print("========== lightweight ask ==========")
    print("image :", image_path)
    print("text  :", text)
    print()

    answer = QwenRunner(config).ask(image_path, text)
    print(answer)

def main() -> None:
    args = build_parser().parse_args()

    # 关键修复：
    # record 命令提前处理，不构造 VoiceAssistant，
    # 避免导入 orchestrator -> asr -> sherpa_onnx。
    if args.cmd == "record":
        _record_without_heavy_import(args)
        return

    # Lightweight STT: do not construct the full VoiceAssistant.
    # stt only needs config + SherpaAsr. It must not import Qwen/TTS/KWS.
    if args.cmd == "stt":
        from .asr import SherpaAsr
        from .config import load_config

        config = load_config(args.config)
        text = SherpaAsr(config).transcribe_wav(args.wav)
        print(text)
        return

    # Lightweight ASK:
    # ask --no-speak --no-play 只验证 QwenRunner，不构造完整助手，
    # 避免导入 orchestrator -> asr -> sherpa_onnx。
    if args.cmd == "ask" and args.no_speak and args.no_play:
        _ask_without_heavy_import(args)
        return

    from .config import load_config
    from .orchestrator import VoiceAssistant

    assistant = VoiceAssistant(load_config(args.config))

    try:
        _run_command(args, assistant)
    except KeyboardInterrupt:
        print("\n已收到 Ctrl+C，中断当前流程并退出。", file=sys.stderr)
        raise SystemExit(130) from None


def _run_command(args: argparse.Namespace, assistant) -> None:
    if args.cmd == "record":
        out = Path(args.out) if args.out else assistant.temp_dir / "command.wav"
        wav = assistant.record_command(args.seconds)
        if out != wav:
            out.parent.mkdir(parents=True, exist_ok=True)
            wav.replace(out)
            wav = out
        print(wav)
    elif args.cmd == "stt":
        print(assistant.transcribe_wav(args.wav))
    elif args.cmd == "tts-stream":
        from .streaming_tts import StreamingTtsPlayer

        player = StreamingTtsPlayer(assistant.config)
        try:
            player.enqueue(args.text)
        finally:
            player.close()
    elif args.cmd == "camera":
        print(assistant.capture_photo())
    elif args.cmd == "wake":
        print(assistant.wait_for_wake(mode=args.mode, timeout=args.timeout))
    elif args.cmd == "kws-file":
        print(assistant.detect_wake_wav(args.wav))
    elif args.cmd == "ask":
        answer = assistant.run_once_from_text(
            args.text,
            image_path=args.image,
            force_photo=args.force_photo,
            speak=not args.no_speak,
            play=not args.no_play,
        )
        print(answer)
    elif args.cmd == "once":
        answer = assistant.run_once_from_microphone(
            seconds=args.seconds,
            speak=not args.no_speak,
            play=not args.no_play,
        )
        print(answer)
    elif args.cmd == "listen":
        answer = assistant.listen_once(
            wake_mode=args.wake_mode,
            wake_timeout=args.wake_timeout,
            seconds=args.seconds,
            speak=not args.no_speak,
            play=not args.no_play,
        )
        print(answer)
    elif args.cmd == "listen-forever":
        assistant.listen_forever(
            wake_mode=args.wake_mode,
            wake_timeout=args.wake_timeout,
            seconds=args.seconds,
            speak=not args.no_speak,
            play=not args.no_play,
        )
    elif args.cmd == "listen-controlled":
        from .controlled_session import run_controlled_session

        raise SystemExit(run_controlled_session(assistant, args))

    elif args.cmd == "cleanup":
        assistant.cleanup_temp()


if __name__ == "__main__":
    main()
