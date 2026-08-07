#!/usr/bin/env python3
"""SSH backend policy: Apple mobile = libssh2 CLI; Android = OpenSSH; never inprocess OpenSSH on Apple."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

CHECKS: list[tuple[Path, list[str], list[str]]] = [
    (
        ROOT / "dependencies/generators/xcodegen.nix",
        ["libwwn-ssh-cli.a", "ssh-cli"],
        ["libssh-inprocess.a"],
    ),
    (
        ROOT / "dependencies/wawona/mobile-platform-deps.nix",
        ['"ssh-cli"', "libssh2", "Never OpenSSH"],
        [],
    ),
    (
        ROOT / "src/platform/android/android_jni.c",
        ["StrictHostKeyChecking", "libssh_bin.so"],
        ["dropbearconvert"],
    ),
]


def main() -> int:
    errors: list[str] = []
    for path, required, forbidden in CHECKS:
        if not path.is_file():
            errors.append(f"missing {path.relative_to(ROOT)}")
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        rel = path.relative_to(ROOT)
        for needle in required:
            if needle not in text:
                errors.append(f"{rel}: missing required {needle!r}")
        for bad in forbidden:
            if bad in text:
                errors.append(f"{rel}: forbidden {bad!r}")

    for stub in (
        ROOT / "src/platform/ios/WWNAppleMobileOptionalStubs.c",
        ROOT / "src/platform/watchos/WWNWatchStubs.c",
    ):
        if not stub.is_file():
            continue
        lines = stub.read_text(encoding="utf-8", errors="replace").splitlines()
        for sym in ("ssh_main", "ssh_keygen_main", "scp_main"):
            pattern = re.compile(rf"\bint\s+{sym}\s*\(")
            for i, line in enumerate(lines):
                if not pattern.search(line):
                    continue
                # A __attribute__((weak)) definition is a legitimate link-time seam,
                # overridden by -force_load libwwn-ssh-cli.a + the matching
                # -Wl,-u,_<sym> on any slice that links the real archive. watchOS's
                # arm64_32 slice has no arm64_32 libwwn-ssh-cli.a build (ASC 90733
                # fat-slice requirement), so it keeps the weak fallback while arm64
                # still resolves to the real implementation. Only a *strong*
                # (non-weak) definition is the real policy violation.
                prev = lines[i - 1].strip() if i > 0 else ""
                if "__attribute__((weak))" not in prev:
                    errors.append(f"{stub.relative_to(ROOT)} must not define {sym} (strong stub)")

    for ghost in (
        ROOT / "src/platform/macos/WWNSSHClient.m",
        ROOT / "src/platform/macos/WWNSSHClient.h",
        ROOT / "src/platform/macos/ssh/WWNSSHClient.m",
        ROOT / "src/platform/macos/ssh/WWNSSHClient.h",
    ):
        if ghost.exists():
            errors.append(f"{ghost.relative_to(ROOT)} must stay deleted")

    if errors:
        print("verify-ssh-backends FAILED:")
        for e in errors:
            print(f"- {e}")
        return 1
    print("verify-ssh-backends OK (Apple libssh2-cli; Android OpenSSH)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
