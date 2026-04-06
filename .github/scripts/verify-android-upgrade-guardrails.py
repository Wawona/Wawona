#!/usr/bin/env python3
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CHECKLIST = ROOT / "docs/android-upgrade-guardrails.md"
BASELINE_SCRIPT = ROOT / ".github/scripts/ci-failure-baseline.py"

REQUIRED_CHECKLIST_MARKERS = [
    "## Scope Triggers",
    "## Pre-upgrade Checklist",
    "## Platform Smoke Validation",
    "## Blocker Signatures",
    "## Acceptance Criteria",
    "`linux-x86_64`",
    "`linux-arm64`",
    "`darwin-arm64`",
    "`darwin-x86_64`",
]

REQUIRED_SIGNATURE_KEYS = [
    "toolchain_path_missing",
    "neon_builtin_mismatch",
    "gradle_daemon",
    "gradle_oom",
]


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def main() -> int:
    errors = []

    if not CHECKLIST.exists():
        errors.append(f"Missing upgrade checklist: {CHECKLIST}")
        checklist = ""
    else:
        checklist = read(CHECKLIST)
        for marker in REQUIRED_CHECKLIST_MARKERS:
            if marker not in checklist:
                errors.append(f"Checklist missing marker: {marker}")

    if not BASELINE_SCRIPT.exists():
        errors.append(f"Missing baseline script: {BASELINE_SCRIPT}")
        baseline_script = ""
    else:
        baseline_script = read(BASELINE_SCRIPT)
        for key in REQUIRED_SIGNATURE_KEYS:
            if key not in baseline_script:
                errors.append(f"Baseline script missing required signature key: {key}")

    if errors:
        print("Android upgrade guardrails check FAILED:")
        for err in errors:
            print(f"- {err}")
        return 1

    print("Android upgrade guardrails check OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
