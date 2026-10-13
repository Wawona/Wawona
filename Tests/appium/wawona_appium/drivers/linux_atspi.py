"""Thin AT-SPI helpers when Appium Linux driver cannot resolve widget names.

Prefer appium-linux-driver. This module is a fallback that uses `busctl` /
`gdbus` introspection only for smoke verification, not for full UI driving.
"""

from __future__ import annotations

import shutil
import subprocess


def atspi_available() -> bool:
    return shutil.which("busctl") is not None or shutil.which("gdbus") is not None


def list_accessible_names(timeout: float = 5.0) -> list[str]:
    """Best-effort dump of accessible names from the session bus (debug)."""
    if not shutil.which("busctl"):
        return []
    try:
        out = subprocess.check_output(
            [
                "busctl",
                "--user",
                "call",
                "org.a11y.Bus",
                "/org/a11y/bus",
                "org.a11y.Bus",
                "GetAddress",
            ],
            text=True,
            timeout=timeout,
            stderr=subprocess.DEVNULL,
        )
        return [line.strip() for line in out.splitlines() if line.strip()]
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError):
        return []
