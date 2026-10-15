#!/usr/bin/env python3
"""Every catalog client in matrix.toml must map in launch-wayland-client.sh."""

from __future__ import annotations

import os
import re
import socket
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib  # type: ignore

ROOT = Path(__file__).resolve().parents[2]
MATRIX = ROOT / "Tests/appium/matrix.toml"
LAUNCH = ROOT / "scripts/appium/launch-wayland-client.sh"
# Catalog matrix rows are Colima. Nested is only a Linux CI override via env,
# not a matrix guest value.
ALLOWED_GUESTS = {"colima"}


def main() -> int:
    with MATRIX.open("rb") as f:
        data = tomllib.load(f)
    catalog = data.get("catalog", {})
    clients: list[tuple[str, str, dict]] = []
    for kind in ("compositors", "applications"):
        for name, entry in catalog.get(kind, {}).items():
            clients.append((kind, name, entry))

    if not clients:
        print("FAIL: empty catalog")
        return 1

    text = LAUNCH.read_text(encoding="utf-8")
    mapped: set[str] = set()
    for m in re.finditer(
        r"^\s*([a-z0-9_|]+)\)\s*echo\s+\"(?:container|colima|nested):",
        text,
        re.M,
    ):
        for part in m.group(1).split("|"):
            mapped.add(part.strip())

    failed = 0
    for kind, name, entry in clients:
        status = entry.get("status")
        guest = entry.get("guest")
        if status != "available":
            print(f"FAIL catalog.{kind}.{name}: status must be available (got {status!r})")
            failed += 1
            continue
        if guest not in ALLOWED_GUESTS:
            print(f"FAIL catalog.{kind}.{name}: guest must be one of {sorted(ALLOWED_GUESTS)}")
            failed += 1
            continue
        if name not in mapped:
            print(f"FAIL catalog.{kind}.{name}: missing from launch-wayland-client.sh recipe_for")
            failed += 1
            continue
        print(f"OK {kind}.{name} guest={guest}")

    with tempfile.TemporaryDirectory() as td:
        runtime = Path(td)
        display = "wayland-0"
        sock_path = runtime / display
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.bind(str(sock_path))
        s.listen(1)
        env = os.environ.copy()
        env["WAWONA_RUNTIME"] = str(runtime)
        env["XDG_RUNTIME_DIR"] = str(runtime)
        env["WAYLAND_DISPLAY"] = display
        proc = subprocess.run(
            ["bash", str(LAUNCH), "__no_such_client__"],
            capture_output=True,
            text=True,
            check=False,
            env=env,
        )
        s.close()
        if proc.returncode != 3:
            print(f"FAIL launcher should exit 3 on unknown client, got {proc.returncode}")
            print(proc.stderr)
            failed += 1
        else:
            print("OK launcher rejects unknown client (exit 3)")

    if failed:
        print(f"FAIL {failed} guest-map check(s)")
        return 1
    print(f"OK wayland guest map ({len(clients)} clients)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
