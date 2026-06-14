#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_DIR))

from voice_assistant.camera import CameraAdapter
from voice_assistant.config import load_config


def sha256sum(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            block = f.read(1024 * 1024)
            if not block:
                break
            h.update(block)
    return h.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Test CameraAdapter without importing orchestrator/ASR."
    )
    parser.add_argument(
        "--config",
        default="config/default.yaml",
        help="Project YAML configuration path.",
    )
    args = parser.parse_args()

    config_path = Path(args.config).resolve()
    print("========== CameraAdapter direct test ==========")
    print(f"project_dir   : {PROJECT_DIR}")
    print(f"config        : {config_path}")

    config = load_config(config_path)

    paths = config["paths"]
    print(f"capture_script: {paths['capture_script']}")
    print(f"temp_dir      : {paths['temp_dir']}")
    print(f"photo_dir     : {paths['photo_dir']}")

    adapter = CameraAdapter(config)

    print()
    print("[RUN] CameraAdapter.capture()")
    image_path = adapter.capture().resolve()

    if not image_path.exists():
        raise RuntimeError(f"CameraAdapter returned missing file: {image_path}")

    size = image_path.stat().st_size
    if size <= 0:
        raise RuntimeError(f"CameraAdapter returned empty file: {image_path}")

    print()
    print("========== output ==========")
    print(f"image_path : {image_path}")
    print(f"size_bytes : {size}")
    print(f"sha256     : {sha256sum(image_path)}")
    print("[OK] CameraAdapter.capture() passed")


if __name__ == "__main__":
    main()
