#!/usr/bin/env python3
"""Verify the Linux app exposes the shell tools and bundled-client runtimes.

The Linux run wrapper (`dependencies/wawona/linux.nix`) must carry the same
launchable tools as the other platforms: the shell stack (zsh, fastfetch,
neovim) plus the bundled Wayland client runtimes (weston, foot, kmscube,
waypipe, openssh) that the launcher can spawn.
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LINUX_NIX = ROOT / "dependencies/wawona/linux.nix"

REQUIRED_RUNTIME_INPUTS = (
    # Shell tools (installable on Linux, surfaced as launchers).
    "pkgs.zsh",
    "pkgs.fastfetch",
    "pkgs.neovim",
    # Bundled Wayland client runtimes + transport.
    "pkgs.weston",
    "pkgs.foot",
    "pkgs.kmscube",
    "pkgs.waypipe",
    "pkgs.openssh",
)


def main() -> int:
    errors: list[str] = []

    if not LINUX_NIX.is_file():
        print(f"- missing {LINUX_NIX}")
        return 1

    src = LINUX_NIX.read_text(encoding="utf-8")
    for dep in REQUIRED_RUNTIME_INPUTS:
        if dep not in src:
            errors.append(f"linux.nix runtimeInputs must include {dep}")

    if errors:
        print("Linux shell-tool wiring check FAILED:")
        for e in errors:
            print(f"- {e}")
        return 1

    print("Linux shell-tool wiring check OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
