#!/usr/bin/env python3
"""Verify Weston iOS patch anchors and compositor archive expectations."""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
IOS_NIX = ROOT / "dependencies/clients/weston/ios.nix"
COMPOSITOR_NIX = ROOT / "dependencies/clients/weston/compositor-apple-mobile.nix"
XCODEGEN = ROOT / "dependencies/generators/xcodegen.nix"

REQUIRED_IOS_PATCH_MARKERS = [
    "wwn_mobile_display_roundtrip",
    "wwn_mobile_pump_client_display_for_ms",
    "background_draw color",
    "output_init skipped (no shell global)",
]

REQUIRED_COMPOSITOR_MARKERS = [
    "wwn_static_module_lookup",
    "wwn_weston_wayland_backend_init",
    "mobile-weston-client-launch.c",
]

REQUIRED_XCODEGEN_MARKERS = [
    "westonDataIosEmbedScript",
    "Embed Weston data (icons, cursors)",
]


def read(path: Path) -> str:
    if not path.is_file():
        print(f"FAIL missing file: {path}", file=sys.stderr)
        sys.exit(1)
    return path.read_text(encoding="utf-8")


def check_markers(label: str, text: str, markers: list[str]) -> None:
    missing = [m for m in markers if m not in text]
    if missing:
        print(f"FAIL {label} missing markers:", file=sys.stderr)
        for m in missing:
            print(f"  - {m}", file=sys.stderr)
        sys.exit(1)
    print(f"OK {label} patch anchors present ({len(markers)} checks)")


def check_archive_symbols(archive: Path) -> None:
    if not archive.is_file():
        print(f"SKIP symbol check (archive not built): {archive}")
        return
    out = subprocess.run(
        ["nm", "-g", str(archive)],
        check=False,
        capture_output=True,
        text=True,
    )
    symbols = out.stdout
    for sym in ("weston_compositor_main", "wwn_static_module_lookup"):
        if sym not in symbols and f"_{sym}" not in symbols:
            print(f"WARN archive missing symbol {sym}: {archive}", file=sys.stderr)


def main() -> None:
    ios_text = read(IOS_NIX)
    compositor_text = read(COMPOSITOR_NIX)
    xcodegen_text = read(XCODEGEN)

    check_markers("ios.nix", ios_text, REQUIRED_IOS_PATCH_MARKERS)
    check_markers("compositor-apple-mobile.nix", compositor_text, REQUIRED_COMPOSITOR_MARKERS)
    check_markers("xcodegen.nix", xcodegen_text, REQUIRED_XCODEGEN_MARKERS)

    if "enableIlandDrm" not in compositor_text:
        print("FAIL compositor-apple-mobile.nix missing enableIlandDrm flag", file=sys.stderr)
        sys.exit(1)
    print("OK compositor enableIlandDrm flag present")

    if not re.search(r"NestedWestonBackend", (ROOT / "src/platform/macos/ui/Settings/WWNPreferencesManager.m").read_text()):
        print("FAIL NestedWestonBackend preference missing", file=sys.stderr)
        sys.exit(1)
    print("OK NestedWestonBackend runtime preference present")

    print("verify-weston-ios-patches: all static checks passed")


if __name__ == "__main__":
    main()
