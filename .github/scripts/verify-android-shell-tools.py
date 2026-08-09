#!/usr/bin/env python3
"""Verify Android packaging for bundled zsh, fastfetch, neovim, and waypipe."""

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

REQUIRED_FLAKE_OUTPUTS = ("zsh-android", "fastfetch-android", "phoon-android", "neovim-android", "waypipe-android")

REQUIRED_ANDROID_NIX = (
    "zshAndroid",
    "fastfetchAndroid",
    "phoonAndroid",
    "neovimAndroid",
    "waypipeAndroid",
    "libzsh_bin.so",
    "libfastfetch_bin.so",
    "libphoon_bin.so",
    "libnvim_bin.so",
    "libwaypipe_bin.so",
    "libssh_bin.so",
    "libssh_keygen_bin.so",
    "assets/zsh",
)

FORBIDDEN_ANDROID_NIX = (
    "dropbearconvert",
    "libdropbearconvert_bin.so",
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
    for bad in FORBIDDEN_ANDROID_NIX:
        if bad in android_nix:
            errors.append(f"android.nix must not ship Dropbear leftover: {bad}")

    jni = read(ANDROID_JNI)
    if "libzsh_bin.so" not in jni:
        errors.append("android_jni.c must resolve libzsh_bin.so from nativeLibDir")
    if "libwaypipe_bin.so" not in jni:
        errors.append("android_jni.c must install libwaypipe_bin.so into usr/bin")
    if "libphoon_bin.so" not in jni:
        errors.append("android_jni.c must install libphoon_bin.so into usr/bin")
    if "StrictHostKeyChecking=accept-new" not in jni:
        errors.append("android_jni.c must use OpenSSH argv (StrictHostKeyChecking)")
    if '"-y"' in jni or "'-y'" in jni:
        # Dropbear-only accept-new hostkey flag must not remain for product SSH.
        if "Dropbear" in jni and "OpenSSH" not in jni:
            errors.append("android_jni.c still looks Dropbear-only")

    if errors:
        print("Android shell-tools wiring check FAILED:")
        for err in errors:
            print(f"- {err}")
        return 1

    print("Android shell-tools wiring check OK (OpenSSH portable; no Dropbear)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
