#!/usr/bin/env python3
"""CI lint: ban `tar --wildcards` in Nix recipes.

macOS ships bsdtar (libarchive), which silently ignores GNU tar's
`--wildcards` flag: a glob-in-extract matches nothing and the derivation
produces an artifact missing files, with no error. This is one of the three
root causes of "not reproducible across hosts" (see the Compositor Bug Squash
Campaign, Phase 8). Extract a directory member instead and post-filter, as in
dependencies/wawona/android-weston-data.nix.

Fails (exit 1) if any *.nix file contains a `tar ... --wildcards` invocation.
Comments (lines whose first non-space char is `#`) are ignored so the recipes
may still *explain* why the flag is banned.
"""
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

# A real invocation: the token `tar` (word boundary) somewhere before
# `--wildcards` on the same logical line. We scan line-by-line and skip
# comment lines to avoid flagging explanatory prose.
INVOCATION = re.compile(r"(^|[\s;&|(])tar\b[^\n]*--wildcards\b")


def is_comment(line: str) -> bool:
    stripped = line.lstrip()
    return stripped.startswith("#")


# Only our own Nix recipes are in scope. Vendored reference trees (the
# `inspirational_projects/nixpkgs` checkout) and build outputs are excluded;
# the wwn-* recipe trees live in their own repos and lint themselves.
SCAN_DIRS = ["dependencies", ".github"]
EXCLUDE_INFIXES = ("result/", "target/", ".direnv/", "inspirational_projects/", "/nixpkgs/")


def iter_nix_files():
    yield from REPO_ROOT.glob("*.nix")
    for d in SCAN_DIRS:
        yield from (REPO_ROOT / d).rglob("*.nix")


def main() -> int:
    violations = []
    for nix_file in sorted(set(iter_nix_files())):
        rel = nix_file.relative_to(REPO_ROOT).as_posix()
        if any(seg in rel for seg in EXCLUDE_INFIXES):
            continue
        try:
            text = nix_file.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for lineno, line in enumerate(text.splitlines(), start=1):
            if is_comment(line):
                continue
            if INVOCATION.search(line):
                violations.append(f"{rel}:{lineno}: {line.strip()}")

    if violations:
        print("ERROR: `tar --wildcards` is banned in Nix recipes "
              "(no-op under macOS bsdtar). Extract a directory member instead.")
        for v in violations:
            print(f"  {v}")
        return 1

    print("OK: no `tar --wildcards` invocations found in *.nix recipes.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
