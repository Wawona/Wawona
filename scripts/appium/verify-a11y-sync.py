#!/usr/bin/env python3
"""Fail if Swift / Kotlin / Linux a11y ids diverge from selectors.json."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SELECTORS = ROOT / "Tests/appium/selectors.json"
SWIFT = ROOT / "Sources/WawonaUI/Machines/Catalog/WWNAccessibilityIdentifiers.swift"
KOTLIN = ROOT / "android/app/src/main/java/com/aspauldingcode/wawona/WawonaTestTags.kt"
LINUX = ROOT / "src/linux/ui/a11y.rs"

ID_RE = re.compile(r'"wwn\.[^"]+"')


def ids_in(path: Path) -> set[str]:
    text = path.read_text(encoding="utf-8")
    # Strip surrounding quotes; ignore ellipsis placeholders in comments.
    out: set[str] = set()
    for match in ID_RE.findall(text):
        value = match.strip('"')
        if "…" in value or "..." in value:
            continue
        out.add(value)
    return out


def main() -> int:
    data = json.loads(SELECTORS.read_text(encoding="utf-8"))
    required = set(data.get("ids", []))
    sources = {
        "swift": ids_in(SWIFT),
        "kotlin": ids_in(KOTLIN),
        "linux": ids_in(LINUX),
    }
    failed = False
    for name, found in sources.items():
        missing = sorted(required - found)
        if missing:
            failed = True
            print(f"FAIL {name}: missing {len(missing)} required ids")
            for mid in missing[:40]:
                print(f"  - {mid}")
            if len(missing) > 40:
                print(f"  … and {len(missing) - 40} more")
        else:
            print(f"OK {name}: all {len(required)} cross-platform ids present")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
