#!/usr/bin/env python3
"""Ensure Android meson cross recipes use androidMesonSandbox.apply."""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

MESON_ANDROID_REL = (
    "dependencies/libs/fontconfig/android.nix",
    "dependencies/libs/freetype/android.nix",
    "dependencies/libs/pixman/android.nix",
    "dependencies/libs/cairo/android.nix",
    "dependencies/libs/glib/android.nix",
    "dependencies/libs/harfbuzz/android.nix",
    "dependencies/libs/fribidi/android.nix",
    "dependencies/libs/pango/android.nix",
    "dependencies/libs/xkbcommon/android.nix",
    "dependencies/libs/libwayland/android.nix",
)

WESTON_COMPOSITOR_REL = "dependencies/clients/weston/compositor-android.nix"

APPLY_NEEDLE = "androidMesonSandbox.apply"
SANDBOX_MODULE_REL = "dependencies/toolchains/android-meson-sandbox.nix"
TOOLCHAIN_DEFAULT_NIX = "dependencies/toolchains/default.nix"

# Duplicated inline patchShebangs should live only in the shared helper.
FORBIDDEN_INLINE = re.compile(
    r"postPatch\s*=\s*''[^'']*patchShebangs\s+\.",
    re.MULTILINE | re.DOTALL,
)


def resolve_root(env_name: str, sibling: str) -> Path | None:
    candidates: list[Path] = []
    env = os.environ.get(env_name, "").strip()
    if env:
        candidates.append(Path(env))
    candidates.append(ROOT.parent / sibling)
    candidates.append(ROOT / sibling)
    for candidate in candidates:
        if candidate.is_dir():
            return candidate
    return None


def check_meson_recipe(path: Path, rel: str, errors: list[str]) -> None:
    if not path.is_file():
        errors.append(f"missing meson android recipe: {rel}")
        return
    content = path.read_text(encoding="utf-8")
    if APPLY_NEEDLE not in content:
        errors.append(f"{rel}: must wrap mkDerivation with {APPLY_NEEDLE}")
    if FORBIDDEN_INLINE.search(content):
        errors.append(f"{rel}: inline postPatch patchShebangs; use androidMesonSandbox.apply")


def main() -> int:
    errors: list[str] = []
    toolchain = resolve_root("WWN_TOOLCHAIN_ROOT", "wwn-toolchain")
    weston = resolve_root("WWN_WESTON_ROOT", "wwn-weston")

    if toolchain is None:
        errors.append(
            "wwn-toolchain not found (set WWN_TOOLCHAIN_ROOT or checkout sibling wwn-toolchain/)"
        )
    else:
        sandbox = toolchain / SANDBOX_MODULE_REL
        if not sandbox.is_file():
            errors.append(f"missing shared helper: {sandbox}")
        default_nix = toolchain / TOOLCHAIN_DEFAULT_NIX
        if default_nix.is_file():
            default = default_nix.read_text(encoding="utf-8")
            if "androidMesonSandbox" not in default:
                errors.append(f"{TOOLCHAIN_DEFAULT_NIX}: androidMesonSandbox not threaded in androidArgs")
        for rel in MESON_ANDROID_REL:
            check_meson_recipe(toolchain / rel, rel, errors)

    if weston is None:
        errors.append(
            "wwn-weston not found (set WWN_WESTON_ROOT or checkout sibling wwn-weston/)"
        )
    else:
        check_meson_recipe(weston / WESTON_COMPOSITOR_REL, WESTON_COMPOSITOR_REL, errors)

    if errors:
        print("Android meson sandbox wiring check FAILED:")
        for err in errors:
            print(f"- {err}")
        return 1

    print("Android meson sandbox wiring check OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
