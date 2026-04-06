#!/usr/bin/env python3
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEPENDENCIES = ROOT / "dependencies"


def main() -> int:
    offenders = []
    for path in DEPENDENCIES.rglob("*android.nix"):
        text = path.read_text(encoding="utf-8")
        if "__noChroot" in text:
            offenders.append(path.relative_to(ROOT).as_posix())

    if offenders:
        print("Android __noChroot policy check FAILED:")
        print("The following Android derivations contain __noChroot:")
        for path in offenders:
            print(f"- {path}")
        return 1

    print("Android __noChroot policy check OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
