#!/usr/bin/env python3
"""Run the interactive Relay guest only until its first SHM commit."""

from __future__ import annotations

import os
import selectors
import subprocess
import sys
import time


COMMIT_MARKER = b"wayland-shm: 256x256 XRGB8888 committed"
SMOKE_TIMEOUT_SECONDS = 60
TERMINATE_TIMEOUT_SECONDS = 5


def stop(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=TERMINATE_TIMEOUT_SECONDS)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()


def main() -> int:
    runner = os.environ.get("WAWONA_REAL_WASM_BIN")
    if not runner:
        print("error: WAWONA_REAL_WASM_BIN is required", file=sys.stderr)
        return 2

    process = subprocess.Popen(
        [runner, *sys.argv[1:]],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=0,
    )
    assert process.stdout is not None
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    deadline = time.monotonic() + SMOKE_TIMEOUT_SECONDS
    recent_output = bytearray()

    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not selector.select(remaining):
            stop(process)
            print(
                f"error: guest did not commit an SHM buffer within {SMOKE_TIMEOUT_SECONDS}s",
                file=sys.stderr,
            )
            return 124

        chunk = os.read(process.stdout.fileno(), 4096)
        if not chunk:
            selector.unregister(process.stdout)
            return process.wait()

        sys.stdout.buffer.write(chunk)
        sys.stdout.buffer.flush()
        recent_output.extend(chunk)
        if COMMIT_MARKER in recent_output:
            stop(process)
            return 0
        if len(recent_output) > len(COMMIT_MARKER):
            del recent_output[: -len(COMMIT_MARKER)]


if __name__ == "__main__":
    raise SystemExit(main())
