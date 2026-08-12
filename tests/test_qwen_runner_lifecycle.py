import os
import time
import unittest
from pathlib import Path

import pexpect

from voice_assistant.qwen_runner import QwenRunner


class QwenRunnerLifecycleTest(unittest.TestCase):
    def assert_process_reaped(
        self,
        pid: int,
        timeout: float = 2.0,
    ) -> None:
        proc_path = Path(f"/proc/{pid}")

        deadline = time.monotonic() + timeout

        while (
            proc_path.exists()
            and time.monotonic() < deadline
        ):
            time.sleep(0.05)

        self.assertFalse(
            proc_path.exists(),
            msg=(
                f"child pid {pid} still exists "
                "after QwenRunner._close_child()"
            ),
        )

        # 一个已经被父进程正确 reap 的直接子进程，
        # 再次 waitpid() 时应提示已经没有可等待子进程。
        with self.assertRaises(ChildProcessError):
            os.waitpid(
                pid,
                os.WNOHANG,
            )

    def test_close_child_reaps_exited_child(self) -> None:
        child = pexpect.spawn(
            "/bin/sh",
            [
                "-c",
                "exit 0",
            ],
            encoding="utf-8",
            timeout=5,
        )

        pid = child.pid

        # 等待程序自己结束，但此时不要主动调用 waitpid。
        child.expect(pexpect.EOF)

        QwenRunner._close_child(child)

        self.assert_process_reaped(pid)

    def test_close_child_terminates_and_reaps_live_child(
        self,
    ) -> None:
        child = pexpect.spawn(
            "/bin/sh",
            [
                "-c",
                "exec sleep 30",
            ],
            encoding="utf-8",
            timeout=5,
        )

        pid = child.pid

        time.sleep(0.1)

        self.assertTrue(
            Path(f"/proc/{pid}").exists()
        )

        QwenRunner._close_child(child)

        self.assert_process_reaped(pid)


if __name__ == "__main__":
    unittest.main()
