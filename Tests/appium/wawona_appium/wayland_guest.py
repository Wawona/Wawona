"""Launch real Wayland clients into Wawona via container / Colima / nested guest."""

from __future__ import annotations

import os
import subprocess
import time
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[3]
_LAUNCH = _ROOT / "scripts" / "appium" / "launch-wayland-client.sh"


def launch_client(client_id: str, *, timeout: float = 180.0) -> subprocess.CompletedProcess[str]:
    """Run launch-wayland-client.sh. Requires a live host Wayland socket."""
    if not _LAUNCH.is_file():
        raise FileNotFoundError(_LAUNCH)
    env = os.environ.copy()
    env.setdefault(
        "WAWONA_RUNTIME",
        env.get("XDG_RUNTIME_DIR", f"/tmp/wawona-{os.getuid()}"),
    )
    env.setdefault("WAYLAND_DISPLAY", "wayland-0")
    return subprocess.run(
        ["bash", str(_LAUNCH), client_id],
        check=False,
        capture_output=True,
        text=True,
        timeout=timeout,
        env=env,
        cwd=str(_ROOT),
    )


def wait_for_socket(*, timeout: float = 30.0) -> Path:
    runtime = Path(
        os.environ.get(
            "WAWONA_RUNTIME",
            os.environ.get("XDG_RUNTIME_DIR", f"/tmp/wawona-{os.getuid()}"),
        )
    )
    display = os.environ.get("WAYLAND_DISPLAY", "wayland-0")
    sock = runtime / display
    end = time.time() + timeout
    while time.time() < end:
        if sock.is_socket():
            return sock
        time.sleep(0.5)
    raise FileNotFoundError(f"Wayland socket missing: {sock}")


def guest_backend() -> str:
    return os.environ.get("WAWONA_WAYLAND_GUEST", "")
