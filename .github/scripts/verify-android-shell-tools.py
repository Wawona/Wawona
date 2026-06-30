#!/usr/bin/env python3
"""Verify Android packaging for bundled zsh, fastfetch, and neovim."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
# Shell-tool packaging was split out of android.nix into android-shell-tools.nix
# to keep android.nix under its maintainability budget; scan both.
ANDROID_NIX_FILES = (
    ROOT / "dependencies/wawona/android.nix",
    ROOT / "dependencies/wawona/android-shell-tools.nix",
)
FLAKE = ROOT / "flake.nix"
ANDROID_JNI = ROOT / "src/platform/android/android_jni.c"

REQUIRED_FLAKE_OUTPUTS = ("zsh-android", "fastfetch-android", "neovim-android")

REQUIRED_ANDROID_NIX = (
    "zshAndroid",
    "fastfetchAndroid",
    "neovimAndroid",
    "libzsh_bin.so",
    "libfastfetch_bin.so",
    "libnvim_bin.so",
    "assets/zsh",
)


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def main() -> int:
    errors: list[str] = []
    flake = read(FLAKE)
    for key in REQUIRED_FLAKE_OUTPUTS:
        if f'"{key}" =' not in flake and f"{key} =" not in flake:
            errors.append(f"flake.nix missing package output: {key}")

    android_nix = "\n".join(read(path) for path in ANDROID_NIX_FILES)
    for needle in REQUIRED_ANDROID_NIX:
        if needle not in android_nix:
            errors.append(f"android.nix missing shell-tool wiring: {needle}")

    if "libzsh_bin.so" not in read(ANDROID_JNI):
        errors.append("android_jni.c must resolve libzsh_bin.so from nativeLibDir")

    if errors:
        print("Android shell-tools wiring check FAILED:")
        for err in errors:
            print(f"- {err}")
        return 1

    print("Android shell-tools wiring check OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
