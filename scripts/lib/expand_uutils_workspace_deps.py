#!/usr/bin/env python3
"""Expand uutils `{ workspace = true }` pins to concrete versions in-place.

Used by workspace-src.nix and scripts/prepare-cargo-path-deps.sh so the Wawona
root Cargo.toml / Cargo.lock stay unchanged (CI `--locked` stays valid).
"""

from __future__ import annotations

import os
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
    # Bare version / pin string: `"1.0"`, `= 0.5.0`, or `"=0.5.0"`.
    # Never emit `version = = 0.5.0` (invalid TOML). Quote caret/exact pins.
    ver = concrete.strip()
    if (ver.startswith('"') and ver.endswith('"')) or (
        ver.startswith("'") and ver.endswith("'")
    ):
        ver_expr = ver
    else:
        ver_expr = f'"{ver}"'
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


_PATH_FIELD = re.compile(r'path\s*=\s*"([^"]+)"')


def relativize_dep_paths(concrete: str, crate_toml: Path, coreutils_root: Path) -> str:
    """Rewrite path = "src/…" (rooted at coreutils) for a nested crate manifest."""
    crate_dir = crate_toml.parent.resolve()
    root = coreutils_root.resolve()

    def repl(m: re.Match) -> str:
        rel_from_root = m.group(1)
        if os.path.isabs(rel_from_root):
            return m.group(0)
        target = (root / rel_from_root).resolve()
        rel = os.path.relpath(target, crate_dir)
        if os.sep != "/":
            rel = rel.replace(os.sep, "/")
        return f'path = "{rel}"'

    return _PATH_FIELD.sub(repl, concrete)


def expand_workspace_true(
    text: str,
    deps: dict[str, str],
    *,
    crate_toml: Path,
    coreutils_root: Path,
) -> str:
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
        concrete = relativize_dep_paths(deps[name], crate_toml, coreutils_root)
        if not extra and not concrete.strip().startswith("{"):
            # Keep bare pins as-is: selinux = "= 0.5.0"
            out.append(f"{indent}{name} = {concrete}\n")
        else:
            out.append(f"{indent}{name} = {_merge_table(concrete, extra)}\n")
        i += 1
    return "".join(out)


def coreutils_tree_tomls(root: Path):
    yield root / "Cargo.toml"
    for p in sorted(root.rglob("Cargo.toml")):
        if p != root / "Cargo.toml":
            yield p


# Wawona path-dep features (Cargo.toml `coreutils = { features = [...] }`).
# Drop other uu_* optional path deps so cargo --locked does not pull their
# crates.io graphs (selinux, blake3, …) into the root lockfile.
WAWONA_COREUTILS_UTILS = frozenset(
    {
        "ls",
        "cat",
        "cp",
        "mv",
        "rm",
        "mkdir",
        "rmdir",
        "ln",
        "touch",
        "echo",
        "pwd",
        "head",
        "tail",
        "wc",
        "sort",
        "cut",
        "tr",
        "seq",
        "basename",
        "dirname",
        "stat",
        "du",
        "df",
        "date",
        "env",
        "printenv",
        "uname",
        "whoami",
        "yes",
        "tee",
        "nl",
        "tac",
        "fold",
        "expand",
        "unexpand",
        "truncate",
        "chmod",
    }
)

# Host / hash / ACL / docs crates never enabled for the in-process safe subset.
# Must stay out of Cargo.lock when coreutils is an optional path dep.
DROP_OPTIONAL_CRATES = frozenset(
    {
        "selinux",
        "selinux-sys",
        "zip",
        "coz",
        "blake3",
        "blake2b_simd",
        "md-5",
        "sha1",
        "sha2",
        "sha3",
        "sm3",
        "digest",
        "crc32fast",
        "hex",
        "data-encoding",
        "data-encoding-macro",
        "data-encoding-macro-internal",
        "z85",
        "exacl",
        "utmp-classic",
        "utmp-classic-raw",
        "dns-lookup",
        # Keep uuhelp_parser: uucore_procs links it for help macros.
    }
)

# Optional deps only safe to strip from uucore (utils use these as normal deps).
DROP_UUCORE_OPTIONAL_CRATES = frozenset(
    {
        "memchr",
        "regex",
        "thiserror",
        "time",
        "data-encoding",
        "data-encoding-macro",
        "z85",
        "blake3",
        "blake2b_simd",
        "md-5",
        "sha1",
        "sha2",
        "sha3",
        "sm3",
        "digest",
        "crc32fast",
        "hex",
        "utmp-classic",
        "utmp-classic-raw",
        "dns-lookup",
    }
)

# Feature keys to drop from uucore / umbrella when pruning.
_DROP_FEATURE_NAMES = frozenset(
    {
        "feat_selinux",
        "feat_require_selinux",
        "feat_hardware",
        "feat_hash",
        "selinux",
        "checksum",
        "encoding",
        "sum",
        "utmpx",
        "uptime",
        "proc-info",
        "uudoc",
    }
)


def _read_assignment(lines: list[str], start: int) -> tuple[list[str], int]:
    """Return (lines_of_assignment, index_after). Handles multi-line `{ … }` / `[ … ]`."""
    buf = [lines[start]]
    i = start
    # Brace/bracket depth for tables and arrays.
    depth = lines[start].count("{") - lines[start].count("}")
    depth += lines[start].count("[") - lines[start].count("]")
    # Feature arrays often start with `name = [` on one line.
    while depth > 0 and i + 1 < len(lines):
        i += 1
        buf.append(lines[i])
        depth += lines[i].count("{") - lines[i].count("}")
        depth += lines[i].count("[") - lines[i].count("]")
    return buf, i + 1


_KEEP_STRUCTURAL_FEATS = frozenset(
    {
        "default",
        "uudoc",
        "test_unimplemented",
        "nightly",
        "uucore",
        "macos",
        "unix",
        "windows",
        "expensive_tests",
        "test_risky_names",
        "feat_acl",
        "feat_common_core",
        "feat_os_unix",
        "feat_os_windows",
        "feat_os_macos",
        "feat_os_unix_android",
        "feat_require_unix",
        "feat_require_unix_utmpx",
        "feat_require_unix_hostid",
        "feat_require_unix_message",
    }
)

_DROP_FEAT_KEYS = _DROP_FEATURE_NAMES


def _filter_feature_array(buf: list[str]) -> list[str] | None:
    """Rewrite a feature assignment; return None to drop the whole feature."""
    text = "".join(buf)
    m = re.match(r"^(\s*)([A-Za-z0-9_-]+)\s*=\s*(.*)$", text, re.S)
    if not m:
        return buf
    indent, feat, rhs = m.group(1), m.group(2), m.group(3).strip()
    if feat in _DROP_FEAT_KEYS or "selinux" in feat:
        return None
    # Collect string items from an array RHS (single- or multi-line).
    if not rhs.startswith("["):
        return buf
    items = re.findall(r'"([^"]+)"', rhs)
    kept: list[str] = []
    for item in items:
        base = item.split("/", 1)[0]
        if base in DROP_OPTIONAL_CRATES or "selinux" in item:
            continue
        # Umbrella feat_* sets list util feature names; drop ones we pruned.
        if feat.startswith("feat_") or feat == "default":
            if (
                base not in WAWONA_COREUTILS_UTILS
                and base not in _KEEP_STRUCTURAL_FEATS
                and not base.startswith("feat_")
                and base not in {"dep:uuhelp_parser", "zip"}
            ):
                # Keep structural / dep: qualifiers; drop unknown util toggles.
                if base.startswith("dep:"):
                    dep = base[4:]
                    if dep in DROP_OPTIONAL_CRATES:
                        continue
                    kept.append(item)
                    continue
                continue
        kept.append(item)
    if feat == "uudoc":
        kept = [x for x in kept if x != "zip" and "zip" not in x]
    body = ",\n  ".join(f'"{x}"' for x in kept)
    if kept:
        return [f"{indent}{feat} = [\n  {body},\n]\n"]
    return [f"{indent}{feat} = []\n"]


def _is_dev_dependencies_section(header: str) -> bool:
    """True for [dev-dependencies] and target-specific dev-dependency tables."""
    h = header.strip()
    return h == "[dev-dependencies]" or (
        h.startswith("[target.") and h.endswith("]") and "dev-dependencies" in h
    )


def strip_dev_dependencies(text: str) -> str:
    """Drop [dev-dependencies] tables so path-dep resolve cannot churn Cargo.lock."""
    lines = text.splitlines(True)
    out: list[str] = []
    i = 0
    while i < len(lines):
        s = lines[i].strip()
        if s.startswith("[") and s.endswith("]") and not s.startswith("[["):
            if _is_dev_dependencies_section(s):
                i += 1
                while i < len(lines):
                    nxt = lines[i].strip()
                    if (
                        nxt.startswith("[")
                        and nxt.endswith("]")
                        and not nxt.startswith("[[")
                    ):
                        break
                    i += 1
                continue
        out.append(lines[i])
        i += 1
    return "".join(out)


def prune_dropped_optional_deps(text: str, *, package_name: str | None = None) -> str:
    """Remove dropped optional crates (and their feature keys) from any manifest."""
    drop_deps = set(DROP_OPTIONAL_CRATES)
    if package_name == "uucore":
        drop_deps |= DROP_UUCORE_OPTIONAL_CRATES
    lines = text.splitlines(True)
    out: list[str] = []
    section: str | None = None
    i = 0
    while i < len(lines):
        line = lines[i]
        s = line.strip()
        if s.startswith("[") and s.endswith("]") and not s.startswith("[["):
            section = s
            out.append(line)
            i += 1
            continue

        if section in {"[dependencies]", "[build-dependencies]"} or (
            section
            and section.startswith("[target.")
            and "dependencies" in section
            and "dev-dependencies" not in section
        ):
            m = re.match(r"^([A-Za-z0-9_-]+)\s*=", s)
            if m and m.group(1) in drop_deps:
                _, nxt = _read_assignment(lines, i)
                i = nxt
                continue

        if section == "[features]":
            m = re.match(r"^([A-Za-z0-9_-]+)\s*=", s)
            if m:
                buf, nxt = _read_assignment(lines, i)
                feat = m.group(1)
                if feat in _DROP_FEAT_KEYS or "selinux" in feat:
                    i = nxt
                    continue
                joined = "".join(buf)
                if package_name == "uucore" and feat in _DROP_FEAT_KEYS:
                    i = nxt
                    continue
                if any(
                    tok in joined
                    for tok in (
                        "selinux",
                        '"zip"',
                        "blake3",
                        "blake2b",
                        "md-5",
                        "sha1",
                        "sha2",
                        "sha3",
                        "sm3",
                        "digest",
                        "crc32fast",
                        "data-encoding",
                        "z85",
                        "exacl",
                        "utmp-classic",
                        "dns-lookup",
                    )
                ) or (package_name == "uucore" and any(
                    tok in joined for tok in ("memchr", "thiserror", '"time"', "regex")
                )):
                    filtered = _filter_feature_array(buf)
                    if filtered is None:
                        i = nxt
                        continue
                    out.extend(filtered)
                    i = nxt
                    continue
                out.extend(buf)
                i = nxt
                continue

        out.append(line)
        i += 1
    return "".join(out)


def _package_name(text: str) -> str | None:
    m = re.search(r'(?m)^name\s*=\s*"([^"]+)"', text)
    return m.group(1) if m else None


def prune_umbrella_for_wawona(text: str) -> str:
    """Keep only Wawona util path-deps on the umbrella; scrub feat sets."""
    lines = text.splitlines(True)
    out: list[str] = []
    section: str | None = None
    i = 0
    while i < len(lines):
        line = lines[i]
        s = line.strip()
        if s.startswith("[") and s.endswith("]") and not s.startswith("[["):
            section = s
            out.append(line)
            i += 1
            continue

        if section in {"[dependencies]", "[dev-dependencies]", "[build-dependencies]"}:
            m = re.match(r"^([A-Za-z0-9_-]+)\s*=", s)
            if m:
                name = m.group(1)
                buf, nxt = _read_assignment(lines, i)
                joined = "".join(buf)
                pkg_m = re.search(r'package\s*=\s*"uu_([A-Za-z0-9_]+)"', joined)
                util = pkg_m.group(1) if pkg_m else name
                is_path_util = "path =" in joined and (
                    "/uu/" in joined or 'package = "uu_' in joined
                )
                if name in DROP_OPTIONAL_CRATES or util in DROP_OPTIONAL_CRATES:
                    i = nxt
                    continue
                if is_path_util and util not in WAWONA_COREUTILS_UTILS:
                    i = nxt
                    continue
                out.extend(buf)
                i = nxt
                continue

        if section == "[features]":
            m = re.match(r"^([A-Za-z0-9_-]+)\s*=", s)
            if m:
                feat = m.group(1)
                buf, nxt = _read_assignment(lines, i)
                if feat in _DROP_FEAT_KEYS or "selinux" in feat:
                    i = nxt
                    continue
                if (
                    feat not in WAWONA_COREUTILS_UTILS
                    and feat not in _KEEP_STRUCTURAL_FEATS
                    and not feat.startswith("feat_")
                ):
                    i = nxt
                    continue
                filtered = _filter_feature_array(buf)
                if filtered is None:
                    i = nxt
                    continue
                out.extend(filtered)
                i = nxt
                continue

        out.append(line)
        i += 1
    return "".join(out)


def dependency_names_from_manifest(text: str) -> list[str]:
    """Cargo.lock package names for [dependencies] and [build-dependencies].

    Prefer `package = "..."` when present (uutils keys like `ls` map to
    `uu_ls` in the lockfile). Skip target-specific / dev dependency tables.
    Build-deps belong in the lock package's dependencies list too.
    """
    names: list[str] = []
    section: str | None = None
    keep = {"[dependencies]", "[build-dependencies]"}
    lines = text.splitlines(True)
    i = 0
    while i < len(lines):
        s = lines[i].strip()
        # Array tables ([[bin]], [[example]]) are not section headers for deps.
        # Clear the section so trailing name=/path= keys are not treated as crates.
        if s.startswith("[[") and s.endswith("]]"):
            section = None
            i += 1
            continue
        if s.startswith("[") and s.endswith("]") and not s.startswith("[["):
            section = s
            i += 1
            continue
        if section not in keep:
            i += 1
            continue
        m = re.match(r"^([A-Za-z0-9_-]+)\s*=", s)
        if not m:
            i += 1
            continue
        key = m.group(1)
        buf, nxt = _read_assignment(lines, i)
        joined = "".join(buf)
        pkg_m = re.search(r'package\s*=\s*"([^"]+)"', joined)
        names.append(pkg_m.group(1) if pkg_m else key)
        i = nxt
    return sorted(set(names))


def sync_lock_package_deps(lock_path: Path, package_name: str, dep_names: list[str]) -> bool:
    """Rewrite Cargo.lock [[package]] dependencies for a path crate after prune/expand.

    cargo metadata --locked fails when the lock's dependency list for coreutils /
    waypipe no longer matches the pruned manifests. Keep package rows; only sync
    the named package's dependencies array. Preserve existing version suffixes
    (`"phf 0.11.3"`) when the package name still applies.
    """
    if not lock_path.is_file():
        return False
    text = lock_path.read_text()
    pat = re.compile(
        rf'(name = "{re.escape(package_name)}"\n'
        rf'version = [^\n]+\n'
        rf'(?:source = [^\n]+\n)?'
        rf'(?:checksum = [^\n]+\n)?'
        rf')dependencies = \[([\s\S]*?)\]\n',
        re.M,
    )
    m = pat.search(text)
    if not m:
        pat = re.compile(
            rf'(name = "{re.escape(package_name)}"\nversion = [^\n]+\n)'
            rf'dependencies = \[([\s\S]*?)\]\n',
            re.M,
        )
        m = pat.search(text)
    if not m:
        print(f"note: no lock package {package_name} to sync in {lock_path}", file=sys.stderr)
        return False
    old_entries = re.findall(r'"([^"]+)"', m.group(2))
    # Map bare package name -> preferred lock entry (keep version suffix).
    by_name: dict[str, str] = {}
    for ent in old_entries:
        bare = ent.split()[0]
        by_name.setdefault(bare, ent)
    merged: list[str] = []
    for name in dep_names:
        merged.append(by_name.get(name, name))
    body = "".join(f' "{n}",\n' for n in merged)
    replacement = m.group(1) + "dependencies = [\n" + body + "]\n"
    new_text = text[: m.start()] + replacement + text[m.end() :]
    if new_text == text:
        return False
    lock_path.write_text(new_text)
    print(f"synced Cargo.lock deps for {package_name} ({len(merged)} entries)")
    return True


def process_coreutils_tree(coreutils_root: Path) -> None:
    root_toml = coreutils_root / "Cargo.toml"
    if not root_toml.is_file():
        print(f"note: missing {root_toml}", file=sys.stderr)
        return
    original = root_toml.read_text()
    deps = extract_workspace_deps(original)
    pkg = extract_workspace_package(original)
    if not deps and "[workspace.dependencies]" not in original:
        # Already expanded by a prior ensure/prepare pass. Still sync lock.
        lock = coreutils_root.parent / "Cargo.lock"
        sync_lock_package_deps(
            lock, "coreutils", dependency_names_from_manifest(root_toml.read_text())
        )
        print(f"note: coreutils already expanded under {coreutils_root}; skipping expand")
        return
    count = 0
    for toml in coreutils_tree_tomls(coreutils_root):
        text = toml.read_text()
        # Expand before strip so we still see [workspace.*] tables on the root.
        if deps:
            text = expand_workspace_true(
                text, deps, crate_toml=toml, coreutils_root=coreutils_root
            )
        if pkg:
            text = expand_package_workspace(text, pkg)
        text = strip_nested_workspace(text)
        text = strip_dev_dependencies(text)
        text = prune_dropped_optional_deps(text, package_name=_package_name(text))
        if toml.resolve() == root_toml.resolve():
            text = prune_umbrella_for_wawona(text)
        toml.write_text(text)
        count += 1
    lock = coreutils_root.parent / "Cargo.lock"
    sync_lock_package_deps(
        lock, "coreutils", dependency_names_from_manifest(root_toml.read_text())
    )
    print(
        f"Expanded uutils workspace pins under {coreutils_root} "
        f"({len(deps)} deps, {len(pkg)} package fields, {count} manifests; "
        f"umbrella pruned to {len(WAWONA_COREUTILS_UTILS)} utils)"
    )


def strip_file(path: Path) -> None:
    if not path.is_file():
        return
    path.write_text(strip_nested_workspace(path.read_text()))
    print(f"stripped nested workspace: {path}")


def prepare_waypipe_manifest(waypipe_root: Path) -> None:
    """Strip nested workspace and drop gbmfallback (not in Wawona's feature set)."""
    toml = waypipe_root / "Cargo.toml"
    if not toml.is_file():
        return
    text = strip_nested_workspace(toml.read_text())
    # Wawona enables lz4/zstd/video only. Unused optional path deps still force
    # Cargo.lock updates on modern cargo, so drop gbmfallback entirely.
    text = re.sub(r'^gbmfallback\s*=\s*.*\n', "", text, flags=re.M)
    text = re.sub(r",\s*\"gbmfallback\"", "", text)
    text = re.sub(r"\"gbmfallback\",\s*", "", text)
    text = re.sub(r'^waypipe-gbm-wrapper\s*=\s*.*\n', "", text, flags=re.M)
    toml.write_text(text)
    lock = waypipe_root.parent / "Cargo.lock"
    sync_lock_package_deps(lock, "waypipe", dependency_names_from_manifest(text))
    print(f"prepared waypipe manifest (no gbmfallback): {toml}")


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(
            "usage: expand_uutils_workspace_deps.py <coreutils-dir>\n"
            "       expand_uutils_workspace_deps.py --waypipe <waypipe-dir>",
            file=sys.stderr,
        )
        return 2
    if argv[1] == "--waypipe":
        if len(argv) < 3:
            print("usage: expand_uutils_workspace_deps.py --waypipe <dir>", file=sys.stderr)
            return 2
        prepare_waypipe_manifest(Path(argv[2]))
        return 0
    process_coreutils_tree(Path(argv[1]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
