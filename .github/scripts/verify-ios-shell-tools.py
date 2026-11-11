#!/usr/bin/env python3
"""Verify Wawona flake + Xcode wiring for bundled shell tools.

Apple mobile SSH policy: libssh2 + ssh-cli (libwwn-ssh-cli.a). Never OpenSSH /
libssh-inprocess.a / openssh-ios.

uutils safe subset: authority is wwn-uutils-rs/.../safe-subset.txt (must match
Cargo.toml coreutils features). The old input name wwn-coreutils is still
accepted so a sibling checkout keeps working.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FLAKE = ROOT / "flake.nix"
FLAKE_LOCK = ROOT / "flake.lock"
CARGO_TOML = ROOT / "Cargo.toml"
DEPS = ROOT / "dependencies/wawona/deps.nix"
PREBUILD = ROOT / "scripts/xcode-prebuild.sh"
MOBILE_DEPS = ROOT / "dependencies/wawona/mobile-platform-deps.nix"

# In-app fastfetch lives under repo.wawona.io (not a wwn-fastfetch flake input).
FASTFETCH_CATALOG_MARKER = "catalog/deb/cli/fastfetch/in-app"
REPO_WAWONA_IO_MIN_LASTMODIFIED = 1782867491

REQUIRED_FLAKE_OUTPUTS = (
    "zsh-ios",
    "zsh-ios-sim",
    "zsh-android",
    "fastfetch-ios",
    "fastfetch-ios-device",
    "fastfetch-android",
    "phoon-ios",
    "phoon-ios-sim",
    "phoon-ios-device",
    "phoon-tvos",
    "phoon-watchos",
    "phoon-visionos",
    "phoon-android",
    "phoon-macos",
    "phoon",
    "wawona-pty-ios",
    "wawona-pty-ios-sim",
    "wawona-rootfs-ios",
    "wawona-rootfs-ios-sim",
)

FORBIDDEN_FLAKE_OUTPUTS = (
    "openssh-ios",
    "openssh-ios-sim",
)



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


def verify_deps(text: str) -> list[str]:
    errors = []
    for needle in ("libwawona-zsh.a", "libfastfetch.a", "libwwn-ssh-cli.a"):
        if needle not in text:
            errors.append(f"deps.nix missing shell-tool wiring: {needle}")
    if "libssh-inprocess.a" in text:
        errors.append("deps.nix must not reference forbidden libssh-inprocess.a")
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
        "libfastfetch.a",
    ):
        if needle not in text:
            errors.append(f"xcode-prebuild.sh missing: {needle}")
    # phoon (wwn-phoon-rs) is pure Rust like niri: it is force-loaded straight
    # from its nix-store archive by phoonLdflags, NOT privatized in prebuild.
    # So it must be ABSENT from the prebuild privatize path (mirrors niri).
    if "libphoon_rs.a" in text:
        errors.append(
            "xcode-prebuild.sh must NOT privatize libphoon_rs.a "
            "(pure-Rust: force-load the store archive via phoonLdflags instead)"
        )
    if "libssh-inprocess.a" in text and "never" not in text.lower():
        # comment mentioning never is OK
        pass
    if "require" in text and "libssh-inprocess" in text and "never" not in text:
        errors.append("xcode-prebuild.sh must not require libssh-inprocess.a")
    return errors


def verify_fastfetch_lock() -> list[str]:
    """Keep-set fastfetch comes from repo.wawona.io in-app catalog, not wwn-fastfetch."""
    errors: list[str] = []
    if not FLAKE_LOCK.is_file():
        return ["flake.lock missing"]
    data = json.loads(FLAKE_LOCK.read_text(encoding="utf-8"))
    if "wwn-fastfetch" in data.get("nodes", {}):
        errors.append(
            "flake.lock must not pin deleted wwn-fastfetch; use repo-wawona-io "
            f"{FASTFETCH_CATALOG_MARKER}"
        )
    node = data.get("nodes", {}).get("repo-wawona-io")
    if not node:
        errors.append("flake.lock missing repo-wawona-io input (hosts in-app fastfetch)")
        return errors
    locked = node.get("locked", {})
    last_modified = int(locked.get("lastModified", 0))
    if last_modified < REPO_WAWONA_IO_MIN_LASTMODIFIED:
        errors.append(
            f"repo-wawona-io lock too old (lastModified {last_modified} < "
            f"{REPO_WAWONA_IO_MIN_LASTMODIFIED})"
        )
    flake = read(FLAKE)
    if FASTFETCH_CATALOG_MARKER not in flake:
        errors.append(
            f"flake.nix missing in-app fastfetch path ({FASTFETCH_CATALOG_MARKER})"
        )
    if "wwn-fastfetch.url" in flake or 'inputs.wwn-fastfetch' in flake:
        errors.append("flake.nix must not re-add wwn-fastfetch input")
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
                # matching -Wl,-u,_<sym> in deps.nix on any
                # slice that links the real archive. watchOS's arm64_32 slice
                # has no arm64_32 libwwn-ssh-cli.a build (ASC 90733 fat-slice
                # requirement), so it keeps the weak fallback while arm64
                # still resolves to the real implementation. Only a *strong*
                # (non-weak) definition is the real policy violation. It can
                # never be overridden, so ssh would stay permanently stubbed.
                prev = lines[i - 1].strip() if i > 0 else ""
                if "__attribute__((weak))" not in prev:
                    errors.append(f"{rel} still defines stub {sym}; use libwwn-ssh-cli.a")
    return errors


def resolve_safe_subset_file() -> Path | None:
    """wwn-uutils-rs owns safe-subset.txt. Prefer sibling, env, then flake input."""
    env = os.environ.get("WWN_COREUTILS", "").strip() or os.environ.get(
        "WWN_UUTILS_RS", ""
    ).strip()
    candidates = []
    if env:
        candidates.append(Path(env) / "dependencies/libs/coreutils/safe-subset.txt")
    for repo in ("wwn-uutils-rs", "wwn-coreutils"):
        candidates.append(
            ROOT.parent / repo / "dependencies/libs/coreutils/safe-subset.txt"
        )
    for c in candidates:
        if c.is_file():
            return c
    for flake_input in ("wwn-uutils-rs", "wwn-coreutils"):
        try:
            r = subprocess.run(
                [
                    "nix",
                    "eval",
                    "--raw",
                    "--impure",
                    "--expr",
                    f'(builtins.getFlake "{ROOT}").inputs.{flake_input}.outPath',
                ],
                check=False,
                capture_output=True,
                text=True,
                timeout=120,
            )
        except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
            continue
        if r.returncode == 0 and r.stdout.strip():
            p = Path(r.stdout.strip()) / "dependencies/libs/coreutils/safe-subset.txt"
            if p.is_file():
                return p
    return None


def parse_safe_subset(text: str) -> list[str]:
    names = []
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        names.append(s)
    return names


def parse_cargo_coreutils_features(text: str) -> list[str] | None:
    m = re.search(
        r'^coreutils\s*=\s*\{[^}]*features\s*=\s*\[([^\]]*)\]',
        text,
        re.M | re.S,
    )
    if not m:
        return None
    return re.findall(r'"([a-z][a-z0-9-]*)"', m.group(1))


def verify_coreutils_safe_subset() -> list[str]:
    errors: list[str] = []
    subset_path = resolve_safe_subset_file()
    if subset_path is None:
        return [
            "cannot resolve wwn-uutils-rs/.../safe-subset.txt "
            "(set WWN_UUTILS_RS, keep sibling checkout, or ensure nix flake input)"
        ]
    authority = parse_safe_subset(read(subset_path))
    if not authority:
        return [f"safe-subset.txt empty: {subset_path}"]
    cargo_feats = parse_cargo_coreutils_features(read(CARGO_TOML))
    if cargo_feats is None:
        return ["Cargo.toml: missing optional coreutils features = [...]"]
    if cargo_feats != authority:
        errors.append(
            "Cargo.toml coreutils features must match "
            f"wwn-uutils-rs safe-subset.txt ({subset_path}): "
            f"cargo={cargo_feats} authority={authority}"
        )
    # flake must not re-pin uutils with a local fetchFromGitHub for coreutils
    flake = read(FLAKE)
    if re.search(
        r'coreutils-src\s*=\s*[^\n]*fetchFromGitHub',
        flake,
    ):
        errors.append(
            "flake.nix must use wwn-uutils-rs.lib.coreutilsSrc "
            "(not a local fetchFromGitHub for coreutils-src)"
        )
    if (
        "wwn-uutils-rs.lib.coreutilsSrc" not in flake
        and "wwn-coreutils.lib.coreutilsSrc" not in flake
    ):
        errors.append("flake.nix missing wwn-uutils-rs.lib.coreutilsSrc for coreutils-src")
    return errors


def verify_no_swift_shell_backends() -> list[str]:
    """Hard reject: SSH/zsh/system must not move into Swift product backends."""
    errors = []
    for rel in (
        "Sources/WawonaApple",
        "Sources/WawonaUI",
        "Darwin",
    ):
        base = ROOT / rel
        if not base.is_dir():
            continue
        for p in base.rglob("*.swift"):
            text = p.read_text(encoding="utf-8", errors="replace")
            # NIOSSH / ios_system as product shell backends
            for bad in (
                "import NIOSSH",
                "import IOSSystem",
                "ios_system/",
                "NIOSSHHandler",
            ):
                if bad in text:
                    errors.append(
                        f"{p.relative_to(ROOT)}: forbidden Swift shell backend ({bad})"
                    )
    return errors


def main() -> int:
    errors: list[str] = []
    errors.extend(verify_flake_outputs(read(FLAKE)))
    errors.extend(verify_deps(read(DEPS)))
    errors.extend(verify_ssh_cli_built(read(MOBILE_DEPS)))
    errors.extend(verify_prebuild(read(PREBUILD)))
    errors.extend(verify_fastfetch_lock())
    errors.extend(verify_no_ssh_stubs())
    errors.extend(verify_coreutils_safe_subset())
    errors.extend(verify_no_swift_shell_backends())

    if errors:
        print("iOS shell-tools wiring check FAILED:")
        for err in errors:
            print(f"- {err}")
        return 1

    print(
        "iOS shell-tools wiring check OK "
        "(libssh2 + ssh-cli; repo.wawona.io fastfetch; wwn-uutils-rs safe-subset; "
        "no Swift shell backends)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
