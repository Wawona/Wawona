#!/usr/bin/env python3
"""Sanity-check Tests/appium/matrix.toml platform and catalog keys."""

from __future__ import annotations

import sys
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib  # type: ignore

ROOT = Path(__file__).resolve().parents[2]
MATRIX = ROOT / "Tests/appium/matrix.toml"

REQUIRED_PLATFORMS = {
    "ios",
    "ipados",
    "tvos",
    "watchos",
    "visionos",
    "macos",
    "android",
    "linux",
}
REQUIRED_FEATURES = {
    "vm",
    "container",
    "multi_window",
    "toolbar_keys",
    "device_rotation",
    "gpu_driver_picker",
    "ssh",
    "waypipe",
    "wasm",
    "native_shell",
}
ALLOWED_GUESTS = {"container", "colima", "nested"}


def main() -> int:
    with MATRIX.open("rb") as f:
        data = tomllib.load(f)
    platforms = set(data.get("platforms", {}))
    if platforms != REQUIRED_PLATFORMS:
        print(f"FAIL platforms mismatch: {platforms ^ REQUIRED_PLATFORMS}")
        return 1
    for name, row in data["platforms"].items():
        missing = REQUIRED_FEATURES - set(row)
        if missing:
            print(f"FAIL {name}: missing features {missing}")
            return 1
        if row["vm"] == "forbidden" and name not in {"tvos", "watchos"}:
            print(f"WARN {name}: vm=forbidden unexpected")
    catalog = data.get("catalog", {})
    if "compositors" not in catalog or "applications" not in catalog:
        print("FAIL catalog.compositors / applications missing")
        return 1
    for kind in ("compositors", "applications"):
        for name, entry in catalog[kind].items():
            if entry.get("status") != "available":
                print(f"FAIL catalog.{kind}.{name}: must be available Wayland guest")
                return 1
            if entry.get("guest") not in ALLOWED_GUESTS:
                print(f"FAIL catalog.{kind}.{name}: guest missing/invalid")
                return 1
    for host in ("macos", "linux"):
        if data["platforms"][host].get("catalog_clients") != "available":
            print(f"FAIL platforms.{host}.catalog_clients must be available")
            return 1
    print(
        f"OK matrix.toml platforms={len(platforms)} "
        f"compositors={len(catalog['compositors'])} "
        f"apps={len(catalog['applications'])}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
