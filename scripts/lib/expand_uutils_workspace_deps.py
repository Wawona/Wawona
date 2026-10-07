#!/usr/bin/env python3
"""Expand uutils `{ workspace = true }` pins to concrete versions in-place.

Used by workspace-src.nix and scripts/prepare-cargo-path-deps.sh so the Wawona
root Cargo.toml / Cargo.lock stay unchanged (CI `--locked` stays valid).
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


def _extract_table(text: str, header: str) -> dict[str, str]:
    """Map key -> RHS for a TOML table header (handles multi-line `{ ... }`)."""
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


def _merge_table(concrete: str, extra_fields: str) -> str:
    """Merge `extra_fields` (comma-separated key = value) into a `{ ... }` table."""
    concrete = concrete.strip()
    if concrete.startswith("{"):
        inner = concrete[1:-1].strip() if concrete.endswith("}") else concrete.strip("{").strip()
        parts = [p.strip() for p in _split_fields(inner) if p.strip()]
        have = {p.split("=", 1)[0].strip() for p in parts if "=" in p}
        for part in _split_fields(extra_fields):
            part = part.strip()
            if not part or "=" not in part:
                continue
            k = part.split("=", 1)[0].strip()
            if k in have or k == "workspace":
                continue
            parts.append(part)
            have.add(k)
        return "{ " + ", ".join(parts) + " }"
    # Bare version / pin string.
    ver = concrete.strip().strip('"')
    ver_expr = ver if ver.startswith("=") else f'"{ver}"'
    parts = [f"version = {ver_expr}"]
    for part in _split_fields(extra_fields):
        part = part.strip()
        if not part or "=" not in part:
            continue
        k = part.split("=", 1)[0].strip()
        if k == "workspace":
            continue
        parts.append(part)
    return "{ " + ", ".join(parts) + " }"


def _split_fields(s: str) -> list[str]:
    """Split top-level comma-separated TOML fields (respect brackets/braces)."""
    parts: list[str] = []
    depth = 0
    cur: list[str] = []
    for ch in s:
        if ch in "[{":
            depth += 1
        elif ch in "]}":
            depth = max(0, depth - 1)
        if ch == "," and depth == 0:
            parts.append("".join(cur))
            cur = []
            continue
        cur.append(ch)
    if cur:
        parts.append("".join(cur))
    return parts


_PKG_WORKSPACE = re.compile(
    r"^(\s*)([A-Za-z0-9_-]+)\.workspace\s*=\s*true\s*$"
)


def expand_package_workspace(text: str, pkg: dict[str, str]) -> str:
    out: list[str] = []
    for line in text.splitlines(True):
        m = _PKG_WORKSPACE.match(line.rstrip("\n"))
        if not m:
            out.append(line)
            continue
        indent, name = m.group(1), m.group(2)
        if name not in pkg:
            # Drop unknown inherited keys rather than leave a broken pin.
            continue
        out.append(f"{indent}{name} = {pkg[name]}\n")
    return "".join(out)


def expand_workspace_true(text: str, deps: dict[str, str]) -> str:
    lines = text.splitlines(True)
    out: list[str] = []
    i = 0
    assign_re = re.compile(r"^(\s*)([A-Za-z0-9_-]+)\s*=\s*\{\s*(.*)$")
    while i < len(lines):
        line = lines[i]
        m = assign_re.match(line.rstrip("\n"))
        if not m or "workspace" not in line:
            out.append(line)
            i += 1
            continue
        indent, name, rest = m.group(1), m.group(2), m.group(3)
        if name not in deps:
            out.append(line)
            i += 1
            continue
        # Collect full `{ ... }` value (may span lines).
        buf = ["{ " + rest]
        if rest.count("{") + 1 > rest.count("}"):  # opening brace already counted in rest? 
            # line was `name = { ...` so brace depth starts at 1 for the value.
            pass
        depth = buf[0].count("{") - buf[0].count("}")
        while depth > 0 and i + 1 < len(lines):
            i += 1
            buf.append(lines[i])
            depth += lines[i].count("{") - lines[i].count("}")
        joined = "".join(buf)
        # Extract inside of outermost braces.
        inner = joined.strip()
        if inner.startswith("{"):
            inner = inner[1:]
        if inner.rstrip().endswith("}"):
            inner = inner.rstrip()[:-1]
        fields = [
            p.strip()
            for p in _split_fields(inner)
            if p.strip() and not p.strip().startswith("workspace")
        ]
        extra = ", ".join(fields)
        out.append(f"{indent}{name} = {_merge_table(deps[name], extra)}\n")
        i += 1
    return "".join(out)


def coreutils_tree_tomls(root: Path):
    yield root / "Cargo.toml"
    for p in sorted(root.rglob("Cargo.toml")):
        if p != root / "Cargo.toml":
            yield p


def process_coreutils_tree(coreutils_root: Path) -> None:
    root_toml = coreutils_root / "Cargo.toml"
    if not root_toml.is_file():
        print(f"note: missing {root_toml}", file=sys.stderr)
        return
    original = root_toml.read_text()
    deps = extract_workspace_deps(original)
    pkg = extract_workspace_package(original)
    count = 0
    for toml in coreutils_tree_tomls(coreutils_root):
        text = toml.read_text()
        # Expand before strip so we still see [workspace.*] tables on the root.
        if deps:
            text = expand_workspace_true(text, deps)
        if pkg:
            text = expand_package_workspace(text, pkg)
        text = strip_nested_workspace(text)
        toml.write_text(text)
        count += 1
    print(
        f"Expanded uutils workspace pins under {coreutils_root} "
        f"({len(deps)} deps, {len(pkg)} package fields, {count} manifests)"
    )


def strip_file(path: Path) -> None:
    if not path.is_file():
        return
    path.write_text(strip_nested_workspace(path.read_text()))
    print(f"stripped nested workspace: {path}")


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(
            "usage: expand_uutils_workspace_deps.py <coreutils-dir>",
            file=sys.stderr,
        )
        return 2
    process_coreutils_tree(Path(argv[1]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
