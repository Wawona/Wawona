#!/usr/bin/env python3
"""Verify Wawona wires the Wawona Runtime (wwn-wasm) for Apple mobile + docs.

Static checks only (no Wasmtime build). Runtime Wayland smoke is
`.github/scripts/smoke-wawona-wasm-wayland.sh` / Gate: wasm-wayland.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FLAKE = ROOT / "flake.nix"
FLAKE_LOCK = ROOT / "flake.lock"
XCODEGEN = ROOT / "dependencies/generators/xcodegen.nix"
MOBILE_DEPS = ROOT / "dependencies/wawona/mobile-platform-deps.nix"
IOS_ROOTFS = ROOT / "dependencies/wawona/ios-rootfs.nix"
DAG = ROOT / "docs/wwn-repo-dag.md"
WASM_DOC = ROOT / "docs/wasm-wasi.md"


def read(path: Path) -> str:
    if not path.is_file():
        print(f"FAIL missing: {path}", file=sys.stderr)
        sys.exit(1)
    return path.read_text(encoding="utf-8")


def main() -> None:
    errors: list[str] = []
    flake = read(FLAKE)
    for needle in (
        "wwn-wasm.url",
        "wwn-wasm.registryFragment",
        "wawona-wasm-ios",
        "wawona-wasm-macos",
        "wawona-wasm-android",
    ):
        if needle not in flake:
            errors.append(f"flake.nix missing {needle}")

    lock = json.loads(read(FLAKE_LOCK))
    node = lock.get("nodes", {}).get("wwn-wasm")
    if not node:
        errors.append("flake.lock missing wwn-wasm input")
    else:
        locked = node.get("locked", {})
        if locked.get("type") not in ("github", "tarball", "indirect"):
            errors.append(f"wwn-wasm lock type unexpected: {locked.get('type')}")

    xg = read(XCODEGEN)
    for needle in ("wasmLdflags", "-lwawona_wasm", "_wawona_wasm_run"):
        if needle not in xg:
            errors.append(f"xcodegen.nix missing {needle}")
    if "wasmLdflags watchosDeps" in xg or "wasmLdflags watchosSimDeps" in xg:
        errors.append("watchOS must not link wawona-wasm (size-gated off)")

    mobile = read(MOBILE_DEPS)
    if 'buildFn "wawona-wasm"' not in mobile and '"wawona-wasm" = buildFn' not in mobile:
        errors.append('mobile-platform-deps.nix must build "wawona-wasm" on mobile/tv/vision')

    rootfs = read(IOS_ROOTFS)
    for needle in ("help wawona wasm", "help()", 'echo "20"'):
        if needle not in rootfs:
            errors.append(f"ios-rootfs.nix missing catalog/stub marker: {needle}")
    if "wawona-dispatch" not in rootfs and "in-process" not in rootfs:
        errors.append("ios-rootfs.nix must mention in-process / wawona-dispatch stubs")

    dag = read(DAG)
    if "wwn-wasm" not in dag:
        errors.append("docs/wwn-repo-dag.md must cite wwn-wasm (L3′)")

    if not WASM_DOC.is_file():
        errors.append("docs/wasm-wasi.md missing")

    if errors:
        for e in errors:
            print(f"FAIL {e}", file=sys.stderr)
        sys.exit(1)
    print("OK Wawona Runtime (wwn-wasm) wiring")


if __name__ == "__main__":
    main()
