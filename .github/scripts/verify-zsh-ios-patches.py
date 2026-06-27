#!/usr/bin/env python3
"""Verify the zsh in-process external-command dispatch hook and its wiring.

Static, source-only checks (no build required):
  * patch-zsh-exec.py contains the expected anchors/markers.
  * Applying it to a fresh copy of the pinned zsh exec.c succeeds (when the
    zsh source is available in the Nix store) and is idempotent.
  * zsh/ios.nix invokes the patch before `make -C Src`.
  * The dispatch shim + header export the dispatcher symbols.
  * The Cargo wiring keeps the `coreutils` feature reachable.
"""

from __future__ import annotations

import re
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PATCH = ROOT / "dependencies/libs/zsh/patches/patch-zsh-exec.py"
ZSH_IOS_NIX = ROOT / "dependencies/libs/zsh/ios.nix"
DISPATCH_C = ROOT / "dependencies/libs/wawona-pty/src/wawona-dispatch.c"
PTY_HEADER = ROOT / "dependencies/libs/wawona-pty/include/wwn_pty.h"
PTY_IOS_NIX = ROOT / "dependencies/libs/wawona-pty/ios.nix"
CARGO_TOML = ROOT / "Cargo.toml"
LIB_RS = ROOT / "src/lib.rs"
ROOTFS_NIX = ROOT / "dependencies/wawona/ios-rootfs.nix"

REQUIRED_PATCH_MARKERS = [
    "WWN_INPROC_DISPATCH",
    "wawona_dispatch_inprocess",
    "wawona_dispatch_can_handle",
    "wwn_inproc = 1",
    "!wwn_inproc &&",
    "} else if (wwn_inproc) {",
    "makecline(args)",
    "unmetafy(*wwn_pp, NULL)",
    "fixfds(save)",
    "goto done;",
]

REQUIRED_DISPATCH_MARKERS = [
    "wawona_coreutils_main",
    "__attribute__((weak))",
    "WWN_DISPATCH_NOT_HANDLED",
    "wwn_safe_subset",
    "wawona_dispatch_can_handle",
]

REQUIRED_HEADER_MARKERS = [
    "wawona_dispatch_inprocess",
    "wawona_dispatch_can_handle",
    "WWN_DISPATCH_NOT_HANDLED",
]


def read(path: Path) -> str:
    if not path.is_file():
        print(f"FAIL missing file: {path}", file=sys.stderr)
        sys.exit(1)
    return path.read_text(encoding="utf-8")


def check_markers(label: str, text: str, markers: list[str]) -> None:
    missing = [m for m in markers if m not in text]
    if missing:
        print(f"FAIL {label} missing markers:", file=sys.stderr)
        for m in missing:
            print(f"  - {m}", file=sys.stderr)
        sys.exit(1)
    print(f"OK {label} ({len(markers)} checks)")


# --- Safe-subset consistency (Cargo.toml ↔ dispatch shim ↔ .zshrc) ----------

def _cargo_coreutils_subset(cargo: str) -> set[str]:
    """Parse the explicit features = [ ... ] of the optional `coreutils` dep."""
    m = re.search(r'coreutils\s*=\s*\{[^}]*features\s*=\s*\[(.*?)\]',
                  cargo, re.DOTALL)
    if not m:
        print("FAIL Cargo.toml: cannot find coreutils dependency feature list",
              file=sys.stderr)
        sys.exit(1)
    return set(re.findall(r'"([a-z0-9-]+)"', m.group(1)))


def _dispatch_safe_subset(dispatch: str) -> set[str]:
    m = re.search(r'wwn_safe_subset\[\]\s*=\s*\{(.*?)\};', dispatch, re.DOTALL)
    if not m:
        print("FAIL wawona-dispatch.c: cannot find wwn_safe_subset[] table",
              file=sys.stderr)
        sys.exit(1)
    return set(re.findall(r'"([a-z0-9-]+)"', m.group(1)))


def _zshrc_inproc_tools(rootfs: str) -> set[str]:
    m = re.search(r'WAWONA_INPROC_TOOLS=\((.*?)\)', rootfs, re.DOTALL)
    if not m:
        print("FAIL ios-rootfs.nix: cannot find WAWONA_INPROC_TOOLS list",
              file=sys.stderr)
        sys.exit(1)
    return set(re.findall(r'\b([a-z][a-z0-9-]+)\b', m.group(1)))


def check_safe_subset_consistency() -> None:
    cargo_set = _cargo_coreutils_subset(read(CARGO_TOML))
    dispatch_set = _dispatch_safe_subset(read(DISPATCH_C))
    zshrc_set = _zshrc_inproc_tools(read(ROOTFS_NIX))
    if not (cargo_set == dispatch_set == zshrc_set):
        print("FAIL in-process safe subset is out of sync:", file=sys.stderr)
        print(f"  Cargo.toml only:   {sorted(cargo_set - dispatch_set - zshrc_set)}",
              file=sys.stderr)
        print(f"  dispatch.c only:   {sorted(dispatch_set - cargo_set - zshrc_set)}",
              file=sys.stderr)
        print(f"  .zshrc only:       {sorted(zshrc_set - cargo_set - dispatch_set)}",
              file=sys.stderr)
        sys.exit(1)
    print(f"OK safe subset consistent across Cargo/dispatch/.zshrc "
          f"({len(cargo_set)} utils)")


def check_no_reachable_spawn() -> None:
    """The in-process dispatch shim must never fork/exec/system/dlopen/JIT.

    It may only forward to the statically linked Rust entry point.
    """
    dispatch = read(DISPATCH_C)
    # Strip comments so prose mentioning fork/exec doesn't trip the guard.
    no_block = re.sub(r"/\*.*?\*/", "", dispatch, flags=re.DOTALL)
    no_line = re.sub(r"//[^\n]*", "", no_block)
    banned = ["fork(", "execve(", "execv(", "execvp(", "execl(",
              "posix_spawn", "system(", "dlopen(", "mmap(",
              "MAP_JIT", "vfork("]
    hits = [b for b in banned if b in no_line]
    if hits:
        print("FAIL wawona-dispatch.c references a forbidden spawn/JIT primitive:",
              file=sys.stderr)
        for h in hits:
            print(f"  - {h}", file=sys.stderr)
        sys.exit(1)
    if "wawona_coreutils_main" not in no_line:
        print("FAIL wawona-dispatch.c does not forward to wawona_coreutils_main",
              file=sys.stderr)
        sys.exit(1)
    print("OK dispatch shim has no reachable fork/exec/system/dlopen/JIT")


def try_apply_against_pinned_zsh() -> None:
    """Best-effort: fetch the pinned zsh src and apply the patch to exec.c."""
    try:
        src = subprocess.run(
            [
                "nix", "build", "--no-link", "--print-out-paths", "--impure",
                "--accept-flake-config", "--expr",
                f'with import (builtins.getFlake "{ROOT}").inputs.nixpkgs '
                "{ system = builtins.currentSystem; }; zsh.src",
            ],
            check=True, capture_output=True, text=True,
        ).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("SKIP live patch apply (nix/zsh.src unavailable)")
        return

    with tempfile.TemporaryDirectory() as td:
        work = Path(td)
        with tarfile.open(src) as tf:
            member = next((m for m in tf.getmembers()
                           if m.name.endswith("/Src/exec.c")), None)
            if member is None:
                print("SKIP live patch apply (exec.c not found in tarball)")
                return
            try:
                tf.extract(member, work, filter="data")
            except TypeError:
                tf.extract(member, work)  # Python < 3.12
            extracted = work / member.name
        srcroot = extracted.parents[1]
        (srcroot / "patch.py").write_bytes(PATCH.read_bytes())
        first = subprocess.run([sys.executable, "patch.py"], cwd=srcroot,
                               capture_output=True, text=True)
        if first.returncode != 0:
            print("FAIL patch-zsh-exec.py did not apply to pinned zsh:",
                  file=sys.stderr)
            print(first.stdout + first.stderr, file=sys.stderr)
            sys.exit(1)
        second = subprocess.run([sys.executable, "patch.py"], cwd=srcroot,
                                capture_output=True, text=True)
        if second.returncode != 0 or "already applied" not in second.stdout:
            print("FAIL patch-zsh-exec.py is not idempotent", file=sys.stderr)
            print(second.stdout + second.stderr, file=sys.stderr)
            sys.exit(1)
        print("OK patch-zsh-exec.py applies to pinned zsh + idempotent")


def main() -> None:
    check_markers("patch-zsh-exec.py", read(PATCH), REQUIRED_PATCH_MARKERS)
    check_markers("wawona-dispatch.c", read(DISPATCH_C), REQUIRED_DISPATCH_MARKERS)
    check_markers("wwn_pty.h", read(PTY_HEADER), REQUIRED_HEADER_MARKERS)

    ios_nix = read(ZSH_IOS_NIX)
    if "patch-zsh-exec.py" not in ios_nix:
        print("FAIL zsh/ios.nix does not invoke patch-zsh-exec.py", file=sys.stderr)
        sys.exit(1)
    # The patch must run before the Src build.
    if ios_nix.index("patch-zsh-exec.py") > ios_nix.index("make -C Src"):
        print("FAIL patch-zsh-exec.py must run before `make -C Src`", file=sys.stderr)
        sys.exit(1)
    print("OK zsh/ios.nix invokes the exec patch before build")

    pty_nix = read(PTY_IOS_NIX)
    if "wawona-dispatch.c" not in pty_nix:
        print("FAIL wawona-pty ios.nix does not compile wawona-dispatch.c",
              file=sys.stderr)
        sys.exit(1)
    print("OK wawona-pty ios.nix compiles the dispatch shim")

    cargo = read(CARGO_TOML)
    if 'coreutils = ["dep:coreutils"]' not in cargo:
        print("FAIL Cargo.toml missing coreutils feature", file=sys.stderr)
        sys.exit(1)
    if "extern crate coreutils;" not in read(LIB_RS):
        print("FAIL src/lib.rs missing `extern crate coreutils`", file=sys.stderr)
        sys.exit(1)
    print("OK Cargo coreutils feature + extern crate wired")

    check_safe_subset_consistency()
    check_no_reachable_spawn()
    try_apply_against_pinned_zsh()
    print("verify-zsh-ios-patches: all static checks passed")


if __name__ == "__main__":
    main()
