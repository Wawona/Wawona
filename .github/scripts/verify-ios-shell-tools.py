#!/usr/bin/env python3
"""Verify Wawona flake + Xcode wiring for bundled shell tools (zsh, fastfetch, neovim)."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FLAKE = ROOT / "flake.nix"
XCODEGEN = ROOT / "dependencies/generators/xcodegen.nix"
PREBUILD = ROOT / "scripts/xcode-prebuild.sh"
IOS_ROOTFS = ROOT / "dependencies/wawona/ios-rootfs.nix"

REQUIRED_FLAKE_OUTPUTS = (
    "zsh-ios",
    "zsh-ios-sim",
    "zsh-android",
    "fastfetch-ios",
    "fastfetch-ios-device",
    "fastfetch-android",
    "neovim-ios",
    "neovim-ios-device",
    "neovim-android",
    "neovim-rootfs-ios",
    "neovim-rootfs-ios-sim",
    "wawona-pty-ios",
    "wawona-pty-ios-sim",
    "wawona-rootfs-ios",
    "wawona-rootfs-ios-sim",
)

REQUIRED_INPROC_CLIENTS = {"fastfetch", "nvim", "vi", "vim", "waypipe"}


def read(path: Path) -> str:
    if not path.is_file():
        print(f"FAIL missing file: {path}", file=sys.stderr)
        sys.exit(1)
    return path.read_text(encoding="utf-8")


def verify_flake_outputs(text: str) -> list[str]:
    errors = []
    for key in REQUIRED_FLAKE_OUTPUTS:
        if f'"{key}" =' not in text and f"{key} =" not in text:
            errors.append(f"flake.nix missing package output: {key}")
    return errors


def verify_xcodegen(text: str) -> list[str]:
    errors = []
    for needle in (
        "libwawona-zsh.a",
        "libfastfetch.a",
        "libwawona-neovim.a",
        "fastfetchLdflags",
        "neovimLdflags",
        "neovimRootfsIosEmbedScript",
    ):
        if needle not in text:
            errors.append(f"xcodegen.nix missing shell-tool wiring: {needle}")
    return errors


def verify_prebuild(text: str) -> list[str]:
    errors = []
    for needle in (
        "libwawona-zsh.a",
        "libwawona-neovim.a",
        "libfastfetch.a",
        "neovim-ios",
        "fastfetch-ios",
    ):
        if needle not in text:
            errors.append(f"xcode-prebuild.sh missing: {needle}")
    return errors


def verify_inproc_clients(rootfs_text: str) -> list[str]:
    errors = []
    m = re.search(r"WAWONA_INPROC_CLIENTS=\((.*?)\)", rootfs_text, re.DOTALL)
    if not m:
        return ["ios-rootfs.nix: missing WAWONA_INPROC_CLIENTS"]
    listed = set(re.findall(r"\b([a-z][a-z0-9-]+)\b", m.group(1)))
    missing = REQUIRED_INPROC_CLIENTS - listed
    if missing:
        errors.append(
            f"ios-rootfs.nix WAWONA_INPROC_CLIENTS missing: {sorted(missing)}"
        )
    return errors


def main() -> int:
    errors: list[str] = []
    errors.extend(verify_flake_outputs(read(FLAKE)))
    errors.extend(verify_xcodegen(read(XCODEGEN)))
    errors.extend(verify_prebuild(read(PREBUILD)))
    if IOS_ROOTFS.is_file():
        errors.extend(verify_inproc_clients(read(IOS_ROOTFS)))
    else:
        errors.append("dependencies/wawona/ios-rootfs.nix missing (wwn-zsh rootfs)")

    if errors:
        print("iOS shell-tools wiring check FAILED:")
        for err in errors:
            print(f"- {err}")
        return 1

    print("iOS shell-tools wiring check OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
