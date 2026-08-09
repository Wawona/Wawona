#!/usr/bin/env python3
"""Verify Wawona flake + Xcode wiring for bundled shell tools.

Apple mobile SSH policy: libssh2 + ssh-cli (libwwn-ssh-cli.a). Never OpenSSH /
libssh-inprocess.a / openssh-ios.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FLAKE = ROOT / "flake.nix"
FLAKE_LOCK = ROOT / "flake.lock"
XCODEGEN = ROOT / "dependencies/generators/xcodegen.nix"
PREBUILD = ROOT / "scripts/xcode-prebuild.sh"
IOS_ROOTFS = ROOT / "dependencies/wawona/ios-rootfs.nix"
MOBILE_DEPS = ROOT / "dependencies/wawona/mobile-platform-deps.nix"

FASTFETCH_MIN_LASTMODIFIED = 1782867491
FASTFETCH_KNOWN_BAD_REV = "104cf2284ad161ecb82b3d182123ff2e437e3a34"

REQUIRED_FLAKE_OUTPUTS = (
    "zsh-ios",
    "zsh-ios-sim",
    "zsh-android",
    "fastfetch-ios",
    "fastfetch-ios-device",
    "fastfetch-android",
    "phoon-ios",
    "phoon-ios-device",
    "phoon-android",
    "phoon-macos",
    "neovim-ios",
    "neovim-ios-device",
    "neovim-android",
    "neovim-rootfs-ios",
    "neovim-rootfs-ios-sim",
    "wawona-pty-ios",
    "wawona-pty-ios-sim",
    "wawona-rootfs-ios",
    "wawona-rootfs-ios-sim",
)

FORBIDDEN_FLAKE_OUTPUTS = (
    "openssh-ios",
    "openssh-ios-sim",
)

REQUIRED_INPROC_CLIENTS = {
    "fastfetch",
    "phoon",
    "nvim",
    "vi",
    "vim",
    "waypipe",
    "waypipe-rs",
    "ssh",
    "ssh-keygen",
    "scp",
}


def read(path: Path) -> str:
    if not path.is_file():
        print(f"FAIL missing file: {path}", file=sys.stderr)
        sys.exit(1)
    return path.read_text(encoding="utf-8")


def verify_flake_outputs(text: str) -> list[str]:
    errors = []
    for key in REQUIRED_FLAKE_OUTPUTS:
        if f'"{key}" =' not in text and f"{key} =" not in text:
            errors.append(f"flake.nix missing package output: {key}")
    for key in FORBIDDEN_FLAKE_OUTPUTS:
        # Allow comments mentioning the name; forbid attribute assignment.
        if re.search(rf'^\s*"{re.escape(key)}"\s*=', text, re.M) or re.search(
            rf"^\s*{re.escape(key)}\s*=", text, re.M
        ):
            errors.append(f"flake.nix must not expose product output: {key}")
    return errors


def verify_xcodegen(text: str) -> list[str]:
    errors = []
    for needle in (
        "libwawona-zsh.a",
        "libfastfetch.a",
        "libphoon_rs.a",
        "libwawona-neovim.a",
        "fastfetchLdflags",
        "phoonLdflags",
        "neovimLdflags",
        "sshCliLdflags",
        "libwwn-ssh-cli.a",
    ):
        if needle not in text:
            errors.append(f"xcodegen.nix missing shell-tool wiring: {needle}")
    for bad in ("libssh-inprocess.a", "opensshInprocessLdflags"):
        if bad in text:
            errors.append(f"xcodegen.nix must not reference forbidden {bad}")
    return errors


def verify_ssh_cli_built(text: str) -> list[str]:
    if 'buildFn "ssh-cli"' not in text and "buildFn \"ssh-cli\"" not in text:
        # also allow "ssh-cli" = buildFn
        if '"ssh-cli" = buildFn' not in text and "'ssh-cli' = buildFn" not in text:
            return [
                'mobile-platform-deps.nix must build ssh-cli '
                '(`"ssh-cli" = buildFn "ssh-cli" { ... }`)'
            ]
    if 'openssh = buildFn "openssh"' in text:
        return [
            "mobile-platform-deps.nix must NOT build openssh on Apple mobile "
            "(use ssh-cli + libssh2 only)"
        ]
    return []


def verify_prebuild(text: str) -> list[str]:
    errors = []
    for needle in (
        "libwawona-zsh.a",
        "libwawona-neovim.a",
        "libfastfetch.a",
        "libphoon_rs.a",
        "neovim-ios",
        "fastfetch-ios",
        "phoon-ios",
    ):
        if needle not in text:
            errors.append(f"xcode-prebuild.sh missing: {needle}")
    if "libssh-inprocess.a" in text and "never" not in text.lower():
        # comment mentioning never is OK
        pass
    if "require" in text and "libssh-inprocess" in text and "never" not in text:
        errors.append("xcode-prebuild.sh must not require libssh-inprocess.a")
    return errors


def verify_fastfetch_lock() -> list[str]:
    if not FLAKE_LOCK.is_file():
        return ["flake.lock missing"]
    data = json.loads(FLAKE_LOCK.read_text(encoding="utf-8"))
    node = data.get("nodes", {}).get("wwn-fastfetch")
    if not node:
        return ["flake.lock missing wwn-fastfetch input"]
    locked = node.get("locked", {})
    rev = locked.get("rev", "")
    last_modified = int(locked.get("lastModified", 0))
    if rev == FASTFETCH_KNOWN_BAD_REV:
        return [
            "flake.lock pins wwn-fastfetch@104cf22 which lacks the in-process "
            "exit()/signal safety wrapper; update wwn-fastfetch"
        ]
    if last_modified < FASTFETCH_MIN_LASTMODIFIED:
        return [
            f"wwn-fastfetch lock too old (lastModified {last_modified} < "
            f"{FASTFETCH_MIN_LASTMODIFIED})"
        ]
    return []


def verify_inproc_clients(rootfs_text: str) -> list[str]:
    errors = []
    m = re.search(r"WAWONA_INPROC_CLIENTS=\((.*?)\)", rootfs_text, re.DOTALL)
    if not m:
        return ["ios-rootfs.nix: missing WAWONA_INPROC_CLIENTS"]
    listed = set(re.findall(r"\b([a-z][a-z0-9-]+)\b", m.group(1)))
    missing = REQUIRED_INPROC_CLIENTS - listed
    if missing:
        errors.append(
            f"ios-rootfs.nix WAWONA_INPROC_CLIENTS missing: {sorted(missing)}"
        )
    return errors


def verify_no_ssh_stubs() -> list[str]:
    errors = []
    for rel in (
        "src/platform/ios/WWNAppleMobileOptionalStubs.c",
        "src/platform/watchos/WWNWatchStubs.c",
    ):
        p = ROOT / rel
        if not p.is_file():
            continue
        lines = p.read_text(encoding="utf-8").splitlines()
        for sym in ("ssh_main", "ssh_keygen_main", "scp_main"):
            pattern = re.compile(rf"\bint\s+{sym}\s*\(")
            for i, line in enumerate(lines):
                if not pattern.search(line):
                    continue
                # A __attribute__((weak)) definition is a legitimate link-time
                # seam, overridden by -force_load libwwn-ssh-cli.a + the
                # matching -Wl,-u,_<sym> in sshCliLdflags (xcodegen.nix) on any
                # slice that links the real archive. watchOS's arm64_32 slice
                # has no arm64_32 libwwn-ssh-cli.a build (ASC 90733 fat-slice
                # requirement), so it keeps the weak fallback while arm64
                # still resolves to the real implementation. Only a *strong*
                # (non-weak) definition is the real policy violation — it can
                # never be overridden, so ssh would stay permanently stubbed.
                prev = lines[i - 1].strip() if i > 0 else ""
                if "__attribute__((weak))" not in prev:
                    errors.append(f"{rel} still defines stub {sym}; use libwwn-ssh-cli.a")
    return errors


def main() -> int:
    errors: list[str] = []
    errors.extend(verify_flake_outputs(read(FLAKE)))
    errors.extend(verify_xcodegen(read(XCODEGEN)))
    errors.extend(verify_ssh_cli_built(read(MOBILE_DEPS)))
    errors.extend(verify_prebuild(read(PREBUILD)))
    errors.extend(verify_fastfetch_lock())
    errors.extend(verify_no_ssh_stubs())
    if IOS_ROOTFS.is_file():
        errors.extend(verify_inproc_clients(read(IOS_ROOTFS)))
    else:
        errors.append("dependencies/wawona/ios-rootfs.nix missing")

    if errors:
        print("iOS shell-tools wiring check FAILED:")
        for err in errors:
            print(f"- {err}")
        return 1

    print("iOS shell-tools wiring check OK (libssh2 + ssh-cli; no OpenSSH-inprocess)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
