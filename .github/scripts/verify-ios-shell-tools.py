#!/usr/bin/env python3
"""Verify Wawona flake + Xcode wiring for bundled shell tools (zsh, fastfetch, neovim, waypipe, openssh)."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FLAKE = ROOT / "flake.nix"
FLAKE_LOCK = ROOT / "flake.lock"
XCODEGEN = ROOT / "dependencies/generators/xcodegen.nix"
PREBUILD = ROOT / "scripts/xcode-prebuild.sh"
IOS_ROOTFS = ROOT / "dependencies/wawona/ios-rootfs.nix"

# Floor for the pinned wwn-fastfetch input. 104cf22 (lastModified 1782867490)
# shipped the IOKit/SMC crash fix but NOT the in-process exit()/signal/atexit
# safety wrapper or the per-platform framework tiering. Require a strictly newer
# lock so Wawona cannot build against a fastfetch that would terminate the app
# on --help/bad-flag or fail to link on watchOS.
FASTFETCH_MIN_LASTMODIFIED = 1782867491
FASTFETCH_KNOWN_BAD_REV = "104cf2284ad161ecb82b3d182123ff2e437e3a34"

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

REQUIRED_INPROC_CLIENTS = {"fastfetch", "nvim", "vi", "vim", "waypipe", "waypipe-rs", "ssh", "ssh-keygen", "scp"}


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


def verify_fastfetch_lock() -> list[str]:
    if not FLAKE_LOCK.is_file():
        return ["flake.lock missing"]
    data = json.loads(FLAKE_LOCK.read_text(encoding="utf-8"))
    node = data.get("nodes", {}).get("wwn-fastfetch")
    if not node:
        return ["flake.lock missing wwn-fastfetch input"]
    locked = node.get("locked", {})
    rev = locked.get("rev", "")
    last_modified = int(locked.get("lastModified", 0))
    if rev == FASTFETCH_KNOWN_BAD_REV:
        return [
            "flake.lock pins wwn-fastfetch@104cf22 which lacks the in-process "
            "exit()/signal safety wrapper and watchOS framework tiering; "
            "run `nix flake lock --update-input wwn-fastfetch`"
        ]
    if last_modified < FASTFETCH_MIN_LASTMODIFIED:
        return [
            f"wwn-fastfetch lock too old (lastModified {last_modified} < "
            f"{FASTFETCH_MIN_LASTMODIFIED}); update the input to include the "
            "in-process safety + framework-tiering fixes"
        ]
    return []


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
    errors.extend(verify_fastfetch_lock())
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
