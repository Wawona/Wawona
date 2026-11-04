#!/usr/bin/env python3
"""Stage libghostty-rs workspace members as expanded path crates.

crate2nix `cargo vendor` extracts git workspace members with
`edition.workspace = true` still set, then `cargo metadata` fails (no
workspace root). Copy the two product crates, expand workspace pins, and
point Wawona Cargo.toml / Cargo.lock at `vendor/libghostty-*` paths.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import stat
import sys
from pathlib import Path

# Minimal copies of expand_uutils_workspace_deps helpers. Nix copies this
# file alone into the store, so do not import the sibling module.


def _extract_table(text: str, header: str) -> dict[str, str]:
    lines = text.splitlines(True)
    deps: dict[str, str] = {}
    grab = False
    i = 0
    while i < len(lines):
        s = lines[i].strip()
        if s == header:
            grab = True
            i += 1
            continue
        if grab:
            if s.startswith("["):
                break
            if not s or s.startswith("#"):
                i += 1
                continue
            if "=" not in lines[i]:
                i += 1
                continue
            key, _, rest = lines[i].partition("=")
            key = key.strip()
            rest = rest.lstrip()
            if rest.startswith("{") and rest.count("{") > rest.count("}"):
                buf = [rest]
                i += 1
                while i < len(lines):
                    buf.append(lines[i])
                    joined = "".join(buf)
                    if joined.count("{") <= joined.count("}"):
                        break
                    i += 1
                deps[key] = "".join(buf).strip()
            else:
                deps[key] = rest.strip()
        i += 1
    return deps


def extract_workspace_deps(text: str) -> dict[str, str]:
    return _extract_table(text, "[workspace.dependencies]")


def extract_workspace_package(text: str) -> dict[str, str]:
    return _extract_table(text, "[workspace.package]")


def strip_nested_workspace(text: str) -> str:
    lines = text.splitlines(True)
    out, skip = [], False
    for line in lines:
        s = line.strip()
        if s == "[workspace]" or s.startswith("[workspace."):
            skip = True
            continue
        if skip:
            if s.startswith("[") and not s.startswith("[workspace"):
                skip = False
            else:
                continue
        if not skip:
            out.append(line)
    return "".join(out)


_PKG_WORKSPACE = re.compile(r"^(\s*)([A-Za-z0-9_-]+)\.workspace\s*=\s*true\s*$")


def expand_package_workspace(text: str, pkg: dict[str, str]) -> str:
    out: list[str] = []
    section: str | None = None
    for line in text.splitlines(True):
        header = line.strip()
        if header.startswith("[") and header.endswith("]") and not header.startswith("[["):
            section = header
        if section != "[package]":
            out.append(line)
            continue
        m = _PKG_WORKSPACE.match(line.rstrip("\n"))
        if not m:
            out.append(line)
            continue
        indent, name = m.group(1), m.group(2)
        if name not in pkg:
            continue
        out.append(f"{indent}{name} = {pkg[name]}\n")
    return "".join(out)


def _expand_dep_workspace(text: str, workspace_deps: dict[str, str]) -> str:
    """Replace `name.workspace = true` / `{ workspace = true }` with concrete RHS."""
    lines = text.splitlines(True)
    out: list[str] = []
    section: str | None = None
    for line in lines:
        header = line.strip()
        if header.startswith("[") and header.endswith("]") and not header.startswith("[["):
            section = header
        if section not in ("[dependencies]", "[build-dependencies]", "[dev-dependencies]"):
            out.append(line)
            continue
        m = re.match(r"^(\s*)([A-Za-z0-9_-]+)\.workspace\s*=\s*true\s*$", line.rstrip("\n"))
        if m:
            indent, name = m.group(1), m.group(2)
            if name not in workspace_deps:
                continue
            rhs = workspace_deps[name]
            # Path deps from the upstream workspace point at crates/; rewrite later.
            out.append(f"{indent}{name} = {rhs}\n")
            continue
        m2 = re.match(
            r'^(\s*)([A-Za-z0-9_-]+)\s*=\s*\{\s*workspace\s*=\s*true([^}]*)\}\s*$',
            line.rstrip("\n"),
        )
        if m2:
            indent, name, extra = m2.group(1), m2.group(2), m2.group(3)
            if name not in workspace_deps:
                continue
            base = workspace_deps[name].strip()
            if base.startswith("{") and base.endswith("}"):
                inner = base[1:-1].strip()
                if extra.strip():
                    # Keep feature extras from the member line.
                    inner = f"{inner}{extra}"
                out.append(f"{indent}{name} = {{ {inner} }}\n")
            else:
                out.append(f"{indent}{name} = {base}\n")
            continue
        out.append(line)
    return "".join(out)


def _rewrite_sys_path(text: str, relative: str) -> str:
    """Force libghostty-vt-sys to a relative path next to this crate."""
    # Match `libghostty-vt-sys = { path = "…", version = "…" }` or bare path.
    def repl(m: re.Match[str]) -> str:
        rest = m.group(1) or ""
        # Drop any prior path= field; keep version / other keys.
        fields = [f.strip() for f in rest.split(",") if f.strip()]
        kept = [f for f in fields if not f.startswith("path")]
        kept.insert(0, f'path = "{relative}"')
        return "libghostty-vt-sys = { " + ", ".join(kept) + " }"

    return re.sub(
        r"libghostty-vt-sys\s*=\s*\{\s*([^}]*)\}",
        repl,
        text,
    )


def stage(src_root: Path, dest_vendor: Path) -> None:
    root_toml = (src_root / "Cargo.toml").read_text()
    pkg = extract_workspace_package(root_toml)
    deps = extract_workspace_deps(root_toml)

    crates = {
        "libghostty-vt": src_root / "crates" / "libghostty-vt",
        "libghostty-vt-sys": src_root / "crates" / "libghostty-vt-sys",
    }
    dest_vendor.mkdir(parents=True, exist_ok=True)
    for name, crate_src in crates.items():
        if not crate_src.is_dir():
            raise SystemExit(f"missing {crate_src}")
        dest = dest_vendor / name
        if dest.exists():
            def _writable(p: Path) -> None:
                try:
                    os.chmod(p, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR)
                except OSError:
                    pass

            for root, dirs, files in os.walk(dest):
                for d in dirs:
                    _writable(Path(root) / d)
                for f in files:
                    _writable(Path(root) / f)
            shutil.rmtree(dest)
        shutil.copytree(
            crate_src,
            dest,
            ignore=shutil.ignore_patterns("target", ".git"),
        )
        # Nix store sources are mode 444; make writable before rewrite.
        for root, dirs, files in os.walk(dest):
            for d in dirs:
                os.chmod(Path(root) / d, 0o755)
            for f in files:
                os.chmod(Path(root) / f, 0o644)
        toml_path = dest / "Cargo.toml"
        text = toml_path.read_text()
        text = expand_package_workspace(text, pkg)
        text = _expand_dep_workspace(text, deps)
        text = strip_nested_workspace(text)
        if name == "libghostty-vt":
            text = _rewrite_sys_path(text, "../libghostty-vt-sys")
            # Drop optional deps not in Wawona's Cargo.lock. crate2nix vendors
            # from the lock only; path-crate metadata otherwise demands them.
            text = _slim_libghostty_vt_manifest(text)
        if name == "libghostty-vt-sys":
            text = _slim_libghostty_vt_sys_manifest(text)
        toml_path.write_text(text)
        print(f"staged {dest}")


def _slim_libghostty_vt_manifest(text: str) -> str:
    """Keep default kitty-graphics path only; drop unused optional crates."""
    # Features: keep default + kitty-graphics; drop allocator/png/log/tracing.
    text = re.sub(
        r"(?ms)^\[features\].*?(?=^\[|\Z)",
        "[features]\n"
        'default = ["kitty-graphics"]\n'
        'kitty-graphics = ["libghostty-vt-sys/kitty-graphics"]\n'
        "link-dynamic = [\"libghostty-vt-sys/link-dynamic\"]\n\n",
        text,
        count=1,
    )
    text = re.sub(
        r"(?ms)^\[dependencies\].*?(?=^\[|\Z)",
        "[dependencies]\n"
        'bitflags = "2.11.0"\n'
        'libghostty-vt-sys = { path = "../libghostty-vt-sys", version = "0.2.1" }\n'
        'int-enum = "1.2.0"\n\n',
        text,
        count=1,
    )
    text = re.sub(
        r"(?ms)^\[dev-dependencies\].*?(?=^\[|\Z)",
        "[dev-dependencies]\n"
        'libghostty-vt-sys = { path = "../libghostty-vt-sys", version = "0.2.1" }\n\n',
        text,
        count=1,
    )
    text = re.sub(r"(?ms)^\[package\.metadata\.docs\.rs\].*?(?=^\[|\Z)", "", text)
    return text


def _slim_libghostty_vt_sys_manifest(text: str) -> str:
    """Keep vendored/pkg-config/kitty-graphics; drop bindgen-tool dep graph."""
    text = re.sub(
        r"(?ms)^\[features\].*?(?=^\[|\Z)",
        "[features]\n"
        'default = ["vendored"]\n'
        "vendored = []\n"
        'pkg-config = ["dep:pkg-config"]\n'
        "link-dynamic = []\n"
        "kitty-graphics = []\n\n",
        text,
        count=1,
    )
    text = re.sub(
        r"(?ms)^\[dependencies\].*?(?=^\[|\Z)",
        "[dependencies]\n\n",
        text,
        count=1,
    )
    text = re.sub(
        r"(?ms)^\[build-dependencies\].*?(?=^\[|\Z)",
        "[build-dependencies]\n"
        'pkg-config = { version = "0.3", optional = true }\n\n',
        text,
        count=1,
    )
    # Drop gen-bindings binary (needs bindgen-tool).
    text = re.sub(r"(?ms)^\[\[bin\]\].*?(?=^\[|\Z)", "", text)
    return text


def patch_wawona_manifest(workspace: Path) -> None:
    cargo = workspace / "Cargo.toml"
    text = cargo.read_text()
    text = re.sub(
        r'^libghostty-vt\s*=\s*\{[^\}]*\}\s*$',
        'libghostty-vt = { path = "./vendor/libghostty-vt", optional = true }',
        text,
        flags=re.MULTILINE,
    )
    text = re.sub(
        r'^libghostty-vt-sys\s*=\s*\{[^\}]*\}\s*$',
        'libghostty-vt-sys = { path = "./vendor/libghostty-vt-sys", optional = true }',
        text,
        flags=re.MULTILINE,
    )
    cargo.write_text(text)
    print(f"patched {cargo} → vendor path deps")


def patch_wawona_lock(workspace: Path) -> None:
    lock = workspace / "Cargo.lock"
    if not lock.exists():
        return
    lines = lock.read_text().splitlines(True)
    out: list[str] = []
    i = 0
    while i < len(lines):
        if lines[i].strip() == "[[package]]":
            block = [lines[i]]
            i += 1
            while i < len(lines) and lines[i].strip() != "[[package]]":
                block.append(lines[i])
                i += 1
            name = next((l for l in block if l.startswith("name = ")), "")
            if 'name = "libghostty-vt"' in name or 'name = "libghostty-vt-sys"' in name:
                # Drop git source line; path crates have no source.
                block = [l for l in block if not l.startswith("source = ")]
            out.extend(block)
            continue
        out.append(lines[i])
        i += 1
    lock.write_text("".join(out))
    print(f"patched {lock} (dropped libghostty git sources)")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("libghostty_rs_src", type=Path)
    ap.add_argument("workspace_root", type=Path)
    args = ap.parse_args()
    vendor = args.workspace_root / "vendor"
    stage(args.libghostty_rs_src, vendor)
    patch_wawona_manifest(args.workspace_root)
    patch_wawona_lock(args.workspace_root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
