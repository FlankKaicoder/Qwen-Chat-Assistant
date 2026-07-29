from __future__ import annotations

import os
import shutil
import signal
import subprocess
from datetime import datetime
from pathlib import Path


class CameraAdapter:
    def __init__(self, config: dict):
        paths = config["paths"]
        self.capture_script = Path(paths["capture_script"])
        self.capture_timeout = int(config.get("camera", {}).get("capture_timeout", 35))
        self.temp_dir = Path(paths["temp_dir"])
        self.photo_dir = Path(paths["photo_dir"])

    def capture(self) -> Path:
        work_dir = self.temp_dir / "capture_work"
        work_dir.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

        cmd = [
            str(self.capture_script),
            "--out-dir",
            str(work_dir),
            "--prefix",
            "voice",
            "--timestamp",
            timestamp,
        ]

        stdout, stderr, returncode = self._run_capture_script(cmd)

        parsed = self._parse_key_values(stdout)
        jpg = Path(parsed["jpg"])
        raw = Path(parsed.get("raw", ""))

        if not jpg.exists():
            raise RuntimeError(
                "capture script reported jpg path but file does not exist: "
                f"{jpg}\nstdout:\n{stdout}\nstderr:\n{stderr}"
            )

        self.photo_dir.mkdir(parents=True, exist_ok=True)
        final_jpg = self.photo_dir / jpg.name
        shutil.move(str(jpg), str(final_jpg))

        if raw:
            raw.unlink(missing_ok=True)

        return final_jpg

    def _run_capture_script(self, cmd: list[str]) -> tuple[str, str, int]:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
        )

        try:
            stdout, stderr = proc.communicate(timeout=self.capture_timeout)
        except subprocess.TimeoutExpired as exc:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass

            stdout, stderr = proc.communicate()

            raise RuntimeError(
                f"capture script timed out after {self.capture_timeout}s\n"
                f"cmd: {' '.join(cmd)}\n"
                f"stdout:\n{stdout}\n"
                f"stderr:\n{stderr}"
            ) from exc

        if proc.returncode != 0:
            raise RuntimeError(
                f"capture script failed with return code {proc.returncode}\n"
                f"cmd: {' '.join(cmd)}\n"
                f"stdout:\n{stdout}\n"
                f"stderr:\n{stderr}"
            )

        return stdout, stderr, proc.returncode

    @staticmethod
    def _parse_key_values(text: str) -> dict[str, str]:
        result: dict[str, str] = {}
        for line in text.splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                result[key.strip()] = value.strip()

        if "jpg" not in result:
            raise RuntimeError(f"capture script did not report jpg path: {text}")

        return result
