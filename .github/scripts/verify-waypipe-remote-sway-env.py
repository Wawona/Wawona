#!/usr/bin/env python3
"""Guard the remote-sway software-render fallback against the issue #54 regression.

Remote sway over waypipe needs `WLR_RENDERER=pixman` /
`WLR_NO_HARDWARE_CURSORS=1` to avoid blank windows, but a bare `VAR=val cmd`
prefix is only honored when a shell interprets it. When waypipe exec()s the
remote command directly, the first token (`WLR_RENDERER=pixman`) is taken as the
program name and the launch fails with "No such file or directory" (issue #54).

The fallback must therefore route the assignments through `env`, which is always
a valid argv[0]. This check fails if the fallback ever emits a bare assignment
prefix again.

Owner after the zero-ObjC cutover: Sources/WawonaApple/Runners/WaypipeRunner.swift
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / "Sources/WawonaApple/Runners/WaypipeRunner.swift"


def main() -> int:
    if not RUNNER.is_file():
        print(f"FAIL missing file: {RUNNER}", file=sys.stderr)
        return 1
    text = RUNNER.read_text(encoding="utf-8")

    # Swift String(format:) must keep `env` as argv[0].
    good = re.search(r'String\(format:\s*"env %@ %@"', text)
    # Reject a bare assignment-format helper that lost the env(1) wrapper.
    bad = re.search(
        r'String\(format:\s*"%@ %@"[\s\S]{0,200}WLR_RENDERER',
        text,
    )

    errors = []
    if not good:
        errors.append(
            "WaypipeRunner.swift: remote-sway env fallback must build "
            '`env %@ %@` so the first token is a real executable (issue #54).'
        )
    if bad:
        errors.append(
            "WaypipeRunner.swift: remote-sway env fallback still emits a bare "
            "`VAR=val cmd` prefix; wrap it with env(1)."
        )
    if "WLR_RENDERER=pixman" not in text or "WLR_NO_HARDWARE_CURSORS=1" not in text:
        errors.append(
            "WaypipeRunner.swift: must keep WLR_RENDERER=pixman and "
            "WLR_NO_HARDWARE_CURSORS=1 in the remote-sway fallback."
        )

    if errors:
        print("waypipe remote-sway env check FAILED:")
        for err in errors:
            print(f"- {err}")
        return 1

    print("waypipe remote-sway env check OK (issue #54 guard)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
