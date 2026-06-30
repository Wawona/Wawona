#!/usr/bin/env python3
"""Verify the Linux bundled Wayland client catalog matches the canonical
Android/iOS catalog.

The Linux catalog lives in `src/linux/bundled_clients.rs` and must stay 1:1
with `android/.../BundledClients.kt` (which itself mirrors the iOS
kBundledClients list): same ids, same display names, same order.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ANDROID = ROOT / "android/app/src/main/java/com/aspauldingcode/wawona/BundledClients.kt"
LINUX = ROOT / "src/linux/bundled_clients.rs"


def android_catalog(src: str) -> list[tuple[str, str]]:
    # BundledClientOption("id", "Name", "desc", Icons...)
    out = []
    for m in re.finditer(r'BundledClientOption\(\s*"([^"]+)"\s*,\s*"([^"]+)"', src):
        out.append((m.group(1), m.group(2)))
    return out


def linux_catalog(src: str) -> list[tuple[str, str]]:
    # BundledClient { id: "id", name: "Name", ... }
    out = []
    for m in re.finditer(
        r'BundledClient\s*\{\s*id:\s*"([^"]+)"\s*,\s*name:\s*"([^"]+)"',
        src,
    ):
        out.append((m.group(1), m.group(2)))
    return out


def main() -> int:
    errors: list[str] = []

    if not ANDROID.is_file():
        errors.append(f"missing canonical Android catalog: {ANDROID}")
    if not LINUX.is_file():
        errors.append(f"missing Linux catalog: {LINUX}")
    if errors:
        for e in errors:
            print(f"- {e}")
        return 1

    android = android_catalog(ANDROID.read_text(encoding="utf-8"))
    linux = linux_catalog(LINUX.read_text(encoding="utf-8"))

    if len(android) != 19:
        errors.append(f"expected 19 Android bundled clients, found {len(android)}")
    if len(linux) != 19:
        errors.append(f"expected 19 Linux bundled clients, found {len(linux)}")

    if [c[0] for c in android] != [c[0] for c in linux]:
        errors.append(
            "Linux bundled client ids/order differ from Android:\n"
            f"  android={[c[0] for c in android]}\n"
            f"  linux  ={[c[0] for c in linux]}"
        )

    amap = dict(android)
    for cid, name in linux:
        if cid in amap and amap[cid] != name:
            errors.append(
                f"display name mismatch for '{cid}': android='{amap[cid]}' linux='{name}'"
            )

    if errors:
        print("Linux bundled client parity check FAILED:")
        for e in errors:
            print(f"- {e}")
        return 1

    print(f"Linux bundled client parity check OK ({len(linux)} clients)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
