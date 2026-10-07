#!/usr/bin/env python3
"""Mode A Darwin CLI sources must stay on public APIs.

Scans the in-process shell command files that ship in the App Store app.
Mode B packaging (Procursus, private LaunchServices) lives under
packaging/mode-b-darwin and must not appear here.
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FILES = (
    ROOT / "src/platform/ios/WWNDarwinCli.swift",
    ROOT / "src/darwin_cli/mod.rs",
    ROOT / "src/darwin_cli/commands.rs",
    ROOT / "src/darwin_cli/host.rs",
    ROOT / "src/darwin_cli/capability.rs",
    ROOT / "src/darwin_cli/state.rs",
)

FORBIDDEN = (
    "LSApplicationWorkspace",
    "FrontBoardServices",
    "BackBoardServices",
    "MobileGestalt",
    "libroot",
    "/var/jb",
    "jbroot",
    "_CFCopySystemVersionDictionary",
    "objc_getClass",
    "dlopen(",
    "SpringBoard",
    "IOMobileFramebuffer",
    "procursus",
)


def main() -> int:
    errors: list[str] = []
    for path in FILES:
        if not path.is_file():
            errors.append(f"missing Mode A CLI source: {path}")
            continue
        text = path.read_text(encoding="utf-8")
        for needle in FORBIDDEN:
            if needle in text:
                errors.append(f"{path.name} contains forbidden Mode B token: {needle}")
    ios = ROOT / "src/platform/ios"
    for path in ios.rglob("*"):
        if path.is_file() and "jailbreak" in path.name.lower():
            errors.append(f"jailbreak source must not live in the app target: {path}")
        if path.suffix == ".m" and path.name in ("WWNHostCommands.m", "WWNDarwinCli.m"):
            errors.append(f"interim Objective-C CLI must stay deleted: {path}")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("darwin-cli Mode A sources: public APIs only")
    return 0


if __name__ == "__main__":
    sys.exit(main())
