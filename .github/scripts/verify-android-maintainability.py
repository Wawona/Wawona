#!/usr/bin/env python3
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEPENDENCIES = ROOT / "dependencies"

DEFAULT_MAX_LINES = 400
LINE_BUDGET_OVERRIDES = {
    "dependencies/libs/libwayland/android.nix": 650,
    "dependencies/libs/waypipe/android.nix": 900,
    "dependencies/wawona/android.nix": 850,
}

# Runtime app wrappers are allowed to ignore best-effort cleanup commands.
SILENT_FAILURE_ALLOWLIST = {
    "dependencies/wawona/android.nix",
}


def line_count(path: Path) -> int:
    return sum(1 for _ in path.open(encoding="utf-8"))


def main() -> int:
    errors = []

    for path in sorted(DEPENDENCIES.rglob("*android.nix")):
        rel = path.relative_to(ROOT).as_posix()
        # Ignore generated gradle mirror trees; maintainability gates apply to
        # canonical dependency definitions checked into the workspace root.
        if rel.startswith("dependencies/generators/") and "/output/" in rel:
            continue
        content = path.read_text(encoding="utf-8")

        max_lines = LINE_BUDGET_OVERRIDES.get(rel, DEFAULT_MAX_LINES)
        lines = line_count(path)
        if lines > max_lines:
            errors.append(f"{rel}: {lines} lines exceeds budget {max_lines}")

        if rel not in SILENT_FAILURE_ALLOWLIST and re.search(r"\|\|\s*true", content):
            errors.append(f"{rel}: contains forbidden '|| true' silent fallback")

    if errors:
        print("Android maintainability check FAILED:")
        for err in errors:
            print(f"- {err}")
        return 1

    print("Android maintainability check OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
