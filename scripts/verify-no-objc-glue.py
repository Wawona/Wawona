#!/usr/bin/env python3
"""Fail if Wawona-owned Apple ObjC glue returns or grows.

Ratchets:
1. No @implementation / @interface outside the allowlist.
2. Allowlist path max lines; totals only shrink.
3. No new .swift under src/platform/{macos,ios,watchos}.
4. Sources/WawonaApple files stay under 400 lines.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKSPACE = ROOT.parent

# path relative to WORKSPACE -> max lines (inclusive). Empty dict = zero ObjC.
# Shrink this map as files migrate. Never grow a max or add a path.
ALLOWLIST: dict[str, int] = {
    # Empty: zero Wawona-owned Apple ObjC glue.
}

SCAN_ROOTS = [
    WORKSPACE / "Wawona" / "src",
    WORKSPACE / "Wawona" / "scripts",
    WORKSPACE / "Wawona" / "dependencies" / "clients",
    WORKSPACE / "Wawona" / "dependencies" / "tools",
    WORKSPACE / "wwn-iland",
    WORKSPACE / "wwn-iomfb-rs",
    WORKSPACE / "wwn-igetty",
    WORKSPACE / "Wawona-Swinging-Bridge",
    WORKSPACE / "doorman",
    WORKSPACE / "wwn-fastfetch",
    WORKSPACE / "wwn-vphone" / "patches",
    WORKSPACE / "agent-device" / "apple-runner",
    WORKSPACE / "wwn-vms",
]

IGNORE_DIR_PARTS = {
    ".git",
    "node_modules",
    "target",
    "build",
    ".derivedData",
    "vendor-research",
    "inspirational_projects",
    "data/corpus",
    ".cache",
    "chess-for-linux",
}

OBJC_MARK = re.compile(r"@(implementation|interface)\b")
APPLE_SWIFT_CAP = 400


def should_ignore(path: Path) -> bool:
    parts = set(path.parts)
    if parts & IGNORE_DIR_PARTS:
        return True
    for part in path.parts:
        if part.startswith(".derivedData"):
            return True
    return False


def line_count(path: Path) -> int:
    try:
        return sum(1 for _ in path.open("r", encoding="utf-8", errors="replace"))
    except OSError:
        return 0


def collect_objc() -> list[Path]:
    found: list[Path] = []
    for root in SCAN_ROOTS:
        if not root.is_dir():
            continue
        for path in root.rglob("*"):
            if not path.is_file():
                continue
            if path.suffix not in {".m", ".mm"}:
                continue
            if should_ignore(path):
                continue
            found.append(path)
    return sorted(found)


def collect_objc_marks() -> list[tuple[Path, int]]:
    """Catch @implementation/@interface smuggled into .c/.swift/.h under scan roots."""
    hits: list[tuple[Path, int]] = []
    for root in SCAN_ROOTS:
        if not root.is_dir():
            continue
        for path in root.rglob("*"):
            if not path.is_file():
                continue
            if path.suffix not in {".c", ".cc", ".cpp", ".h", ".hpp", ".swift", ".m", ".mm"}:
                continue
            if should_ignore(path):
                continue
            # Thin ObjC headers kept for bridging may declare @interface; forbid @implementation only.
            try:
                text = path.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            for i, line in enumerate(text.splitlines(), 1):
                if "@implementation" in line:
                    hits.append((path, i))
                    break
    return hits


def rel(path: Path) -> str:
    try:
        return str(path.relative_to(WORKSPACE))
    except ValueError:
        return str(path)


def main() -> int:
    errors: list[str] = []
    objc_files = collect_objc()
    allow = dict(ALLOWLIST)
    total_allowed = sum(allow.values())
    total_actual = 0

    for path, line in collect_objc_marks():
        # Bridging .h may keep @interface; @implementation is never allowed.
        if path.suffix in {".h", ".hpp"}:
            errors.append(
                f"@implementation in header under scan roots: {rel(path)}:{line}"
            )
        else:
            errors.append(
                f"@implementation outside allowlist: {rel(path)}:{line}"
            )

    for path in objc_files:
        key = rel(path)
        n = line_count(path)
        total_actual += n
        text = path.read_text(encoding="utf-8", errors="replace")
        if key not in allow:
            if OBJC_MARK.search(text) or path.suffix in {".m", ".mm"}:
                errors.append(f"ObjC not on allowlist: {key} ({n} lines)")
            continue
        max_n = allow.pop(key)
        if n > max_n:
            errors.append(f"grew past ratchet: {key} has {n} lines (max {max_n})")

    for leftover, max_n in sorted(allow.items()):
        # Missing allowlisted file is progress (deletion). Only fail if present elsewhere.
        p = WORKSPACE / leftover
        if p.is_file():
            errors.append(f"allowlist path not scanned (check SCAN_ROOTS): {leftover}")
        # else: deleted; OK. Drop from future commits.

    # Swift under old platform trees must not grow new files beyond existing.
    for plat in ("macos", "ios", "watchos"):
        tree = ROOT / "src" / "platform" / plat
        if not tree.is_dir():
            continue
        for path in tree.rglob("*.swift"):
            errors.append(
                f"Swift under src/platform/{plat} forbidden; use Sources/WawonaApple: "
                f"{rel(path)}"
            )

    apple = ROOT / "Sources" / "WawonaApple"
    if apple.is_dir():
        for path in apple.rglob("*.swift"):
            n = line_count(path)
            if n > APPLE_SWIFT_CAP:
                errors.append(
                    f"WawonaApple file over {APPLE_SWIFT_CAP} lines: "
                    f"{rel(path)} ({n})"
                )

    # Ban UTM ObjC leftovers
    for ghost in (
        WORKSPACE / "wwn-vms/dependencies/vms/utm/sources/UTMProcess.m",
        WORKSPACE / "wwn-vms/dependencies/vms/utm/sources/UTMQemuSystem.m",
    ):
        if ghost.is_file():
            errors.append(f"dead UTM ObjC must stay deleted: {rel(ghost)}")

    if errors:
        print("verify-no-objc-glue FAILED:")
        for e in errors:
            print(f"- {e}")
        print(f"allowlist budget lines={total_allowed} actual_scanned={total_actual}")
        return 1

    print(
        f"verify-no-objc-glue OK "
        f"(allowlisted={len(ALLOWLIST)} budget_lines={total_allowed} "
        f"scanned={len(objc_files)} actual_lines={total_actual})"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
