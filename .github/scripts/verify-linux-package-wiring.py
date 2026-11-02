#!/usr/bin/env python3
"""Fail closed on Linux packaging regressions that break install/run.

Checks:
1. flake.nix wires wawonaLinuxUiBin into wawona / default / host / tray / wawona-linux.
2. No hardcoded /home/alex/Wawona flake path in Linux service/tray sources.
3. Linux wrapper .nix files are LF and strip CR (issue #164).
4. Autostart policy keeps compositor host, not the GTK Machines UI.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FLAKE = ROOT / "flake.nix"
SERVICE = ROOT / "src/linux/service.rs"
TRAY = ROOT / "src/bin/wawona-linux-tray.rs"
LINUX_NIX_FILES = (
    ROOT / "dependencies/wawona/linux.nix",
    ROOT / "dependencies/wawona/linux-host.nix",
    ROOT / "dependencies/wawona/linux-tray.nix",
)

REQUIRED_BIN_WIRED = (
    "wawona-linux",
    "wawona-linux-compositor-host",
    "wawona-linux-tray",
    "default",
    "wawona",
)


def package_window(flake: str, attr: str) -> str | None:
    """Return the callPackage block for a Linux wrapper attr."""
    pat = (
        rf"{re.escape(attr)}\s*=\s*pkgs\.callPackage\s+"
        rf"\./dependencies/wawona/linux(?:-host|-tray)?\.nix\s*"
        rf"\{{(.*?)\n\s*\}};"
    )
    m = re.search(pat, flake, flags=re.S)
    return m.group(0) if m else None


def main() -> int:
    errors: list[str] = []

    flake = FLAKE.read_text(encoding="utf-8")
    for attr in REQUIRED_BIN_WIRED:
        window = package_window(flake, attr)
        if window is None:
            errors.append(
                f"flake.nix missing pkgs.callPackage linux* site for {attr}"
            )
            continue
        if "wawonaLinuxUiBin" not in window:
            errors.append(
                f"flake.nix {attr} must pass wawonaLinuxUiBin "
                "(otherwise the wrapper exits 1 at runtime)"
            )

    for path in (SERVICE, TRAY):
        src = path.read_text(encoding="utf-8")
        if "/home/alex/Wawona" in src:
            errors.append(
                f"{path.relative_to(ROOT)} must not hardcode /home/alex/Wawona"
            )

    service_src = SERVICE.read_text(encoding="utf-8")
    # Production unit bodies must not target default.target. Tests may mention
    # the forbidden string in assertions.
    production = "\n".join(
        line
        for line in service_src.splitlines()
        if "WantedBy=default.target" in line and "assert" not in line
    )
    if production.strip():
        errors.append(
            "src/linux/service.rs must WantedBy=graphical-session.target "
            "(not default.target)"
        )
    if "render_autostart_desktop" not in service_src:
        errors.append("src/linux/service.rs must expose render_autostart_desktop")
    if "wawona-linux-compositor-host" not in service_src:
        errors.append(
            "autostart / units must target wawona-linux-compositor-host"
        )
    if "fn resolve_flake_ref" not in service_src:
        errors.append("src/linux/service.rs must expose resolve_flake_ref")

    for path in LINUX_NIX_FILES:
        raw = path.read_bytes()
        if b"\r" in raw:
            errors.append(
                f"{path.relative_to(ROOT)} contains CR (issue #164); keep LF"
            )
        text = raw.decode("utf-8")
        if "builtins.replaceStrings" not in text or r'["\r"]' not in text:
            errors.append(
                f"{path.relative_to(ROOT)} must strip \\r via "
                'builtins.replaceStrings ["\\r"] [""] (issue #164)'
            )
        if "wawonaLinuxUiBin" not in text:
            errors.append(
                f"{path.relative_to(ROOT)} must take wawonaLinuxUiBin"
            )

    gitattributes = ROOT / ".gitattributes"
    if not gitattributes.is_file():
        errors.append("missing .gitattributes (issue #164 LF policy)")
    else:
        ga = gitattributes.read_text(encoding="utf-8")
        if "*.nix text eol=lf" not in ga:
            errors.append(".gitattributes must set *.nix text eol=lf")

    if errors:
        print("Linux package wiring check FAILED:")
        for e in errors:
            print(f"- {e}")
        return 1

    print("Linux package wiring check OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
