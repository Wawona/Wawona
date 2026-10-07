#!/usr/bin/env bash
# After ensure-waypipe / ensure-coreutils: strip nested [workspace*] tables so
# `cargo test` / `cargo metadata` see a single workspace root, and merge
# uutils [workspace.dependencies] into the root Cargo.toml (with paths
# rewritten under coreutils/). Same logic as dependencies/wawona/workspace-src.nix.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

strip_nested_workspace() {
  python3 - "$1" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
if not p.is_file():
    raise SystemExit(0)
lines = p.read_text().splitlines(True)
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
p.write_text("".join(out))
print(f"stripped nested workspace: {p}")
PY
}

merge_coreutils_workspace_deps() {
  python3 - "$ROOT/Cargo.toml" "$ROOT/coreutils/Cargo.toml" <<'PY'
from pathlib import Path
import re
import sys

root_path = Path(sys.argv[1])
nested_path = Path(sys.argv[2])
if not nested_path.is_file():
    print("note: no coreutils/Cargo.toml; skip workspace.deps merge")
    raise SystemExit(0)

def extract_workspace_deps(text: str) -> str:
    lines = text.splitlines(True)
    out, grab = [], False
    for line in lines:
        s = line.strip()
        if s == "[workspace.dependencies]":
            grab = True
            continue
        if grab:
            if s.startswith("[") and not s.startswith("[workspace.dependencies]"):
                break
            if s and not s.startswith("#"):
                out.append(line if line.endswith("\n") else line + "\n")
    return "".join(out)

def rewrite_coreutils_paths(deps_body: str) -> str:
    def repl(m: re.Match) -> str:
        p = m.group(1)
        if p.startswith("coreutils/"):
            return m.group(0)
        return f'path = "coreutils/{p}"'
    return re.sub(r'path\s*=\s*"([^"]+)"', repl, deps_body)

def ensure_workspace_deps_table(text: str, deps_body: str) -> str:
    if not deps_body.strip():
        return text
    marker = "[workspace.dependencies]"
    if marker in text:
        existing = set()
        grab = False
        for line in text.splitlines():
            s = line.strip()
            if s == marker:
                grab = True
                continue
            if grab:
                if s.startswith("["):
                    break
                if "=" in s:
                    existing.add(s.split("=", 1)[0].strip())
        extra = []
        for line in deps_body.splitlines(True):
            s = line.strip()
            if not s or s.startswith("#") or "=" not in s:
                continue
            key = s.split("=", 1)[0].strip()
            if key not in existing:
                extra.append(line if line.endswith("\n") else line + "\n")
        if not extra:
            return text
        lines = text.splitlines(True)
        out = []
        for line in lines:
            out.append(line)
            if line.strip() == marker:
                out.extend(extra)
        return "".join(out)
    if "[workspace]" in text:
        lines = text.splitlines(True)
        out, i = [], 0
        while i < len(lines):
            out.append(lines[i])
            if lines[i].strip() == "[workspace]":
                i += 1
                while i < len(lines) and not lines[i].strip().startswith("["):
                    out.append(lines[i])
                    i += 1
                out.append("\n[workspace.dependencies]\n")
                out.append(deps_body if deps_body.endswith("\n") else deps_body + "\n")
                out.append("\n")
                out.extend(lines[i:])
                return "".join(out)
            i += 1
    return text + "\n[workspace.dependencies]\n" + deps_body + "\n"

# Merge from the *unstripped* nested file when possible. Callers strip after.
deps = rewrite_coreutils_paths(extract_workspace_deps(nested_path.read_text()))
if deps.strip():
    root_path.write_text(ensure_workspace_deps_table(root_path.read_text(), deps))
    print(f"Merged coreutils workspace.dependencies into root ({len(deps.splitlines())} lines)")
else:
    print("note: coreutils had no [workspace.dependencies] to merge")
PY
}

# Merge before strip so we still see [workspace.dependencies] on coreutils.
if [[ -f "$ROOT/coreutils/Cargo.toml" ]]; then
  merge_coreutils_workspace_deps
  strip_nested_workspace "$ROOT/coreutils/Cargo.toml"
fi
if [[ -f "$ROOT/waypipe/Cargo.toml" ]]; then
  strip_nested_workspace "$ROOT/waypipe/Cargo.toml"
fi
