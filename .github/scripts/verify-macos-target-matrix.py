#!/usr/bin/env python3
"""Validate required macOS-host build/run outputs exist in flake.nix."""

from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
FLAKE = ROOT / "flake.nix"

REQUIRED_PACKAGE_KEYS = {
    "wawona-ios",
    "wawona-ipados",
    "wawona-tvos",
    "wawona-watchos",
    "wawona-visionos",
    "wawona-ios-app-sim",
    "wawona-ipados-app-sim",
    "wawona-tvos-app-sim",
    "wawona-watchos-app-sim",
    "wawona-visionos-app-sim",
    "wawona-ios-app-device",
    "wawona-ipados-app-device",
    "wawona-tvos-app-device",
    "wawona-watchos-app-device",
    "wawona-ios-backend",
    "wawona-ios-sim-backend",
    "wawona-ipados-backend",
    "wawona-ipados-sim-backend",
    "wawona-tvos-backend",
    "wawona-tvos-sim-backend",
    "wawona-watchos-backend",
    "wawona-watchos-sim-backend",
    "wawona-visionos-backend",
    "wawona-visionos-sim-backend",
    "wawona-macos-backend",
}

REQUIRED_APP_KEYS = {
    "wawona-ios",
    "wawona-ipados",
    "wawona-tvos",
    "wawona-watchos",
    "wawona-visionos",
}


def _missing_keys(text: str, keys: set[str]) -> list[str]:
    missing = []
    for key in sorted(keys):
        needle = f"{key} ="
        if needle not in text:
            missing.append(key)
    return missing


def main() -> int:
    text = FLAKE.read_text(encoding="utf-8")
    missing_packages = _missing_keys(text, REQUIRED_PACKAGE_KEYS)
    missing_apps = _missing_keys(text, REQUIRED_APP_KEYS)
    if missing_packages:
        print(f"missing package outputs: {missing_packages}", file=sys.stderr)
        return 1
    if missing_apps:
        print(f"missing app outputs: {missing_apps}", file=sys.stderr)
        return 1
    print("macOS target matrix validation passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
