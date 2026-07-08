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
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / "src/platform/macos/ui/Settings/WWNWaypipeRunner.m"


def main() -> int:
    if not RUNNER.is_file():
        print(f"FAIL missing file: {RUNNER}", file=sys.stderr)
        return 1
    text = RUNNER.read_text(encoding="utf-8")

    # The fallback string builder must prefix the joined assignments with `env`.
    good = re.search(r'stringWithFormat:@"env %@ %@"', text)
    bad = re.search(r'stringWithFormat:@"%@ %@".*\n.*WWNLog\("WAYPIPE",\s*\n\s*@"Applied remote sway',
                    text)

    errors = []
    if not good:
        errors.append(
            "WWNWaypipeRunner.m: remote-sway env fallback must build "
            '`env %@ %@` so the first token is a real executable (issue #54).'
        )
    if bad:
        errors.append(
            "WWNWaypipeRunner.m: remote-sway env fallback still emits a bare "
            "`VAR=val cmd` prefix; wrap it with env(1)."
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
