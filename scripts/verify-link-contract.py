#!/usr/bin/env python3
"""Fail an Apple app build before compile when the link cannot succeed.

Two drifts produced undefined symbols at Ld, after a long compile:

1. A source file xcodegen would compile was absent from the target's
   Sources phase (the ObjC class, or a Swift type, never made it into the
   binary).
2. A C function declared for that target was absent from every static
   archive the target actually links (a stale .nix-deps copy, or a Rust
   backend built from waypipe that does not export the entry).

This script is the contract. xcode-prebuild.sh runs `membership` before Nix
and `symbols` after libwawona.a is copied. Apple nm cannot read the Rust
nightly archive, so symbol presence is the exported name in the archive
bytes, which is what ld looks up.
"""

from __future__ import annotations

import argparse
import fnmatch
import os
import re
import sys

COMPILE_EXT = {".m", ".mm", ".c", ".swift", ".s", ".S"}
SKIP_NAMES = {
    "if",
    "for",
    "while",
    "switch",
    "return",
    "sizeof",
    "typeof",
}


def die(msg: str) -> None:
    print(f"link contract: {msg}", file=sys.stderr)
    raise SystemExit(1)


def read(path: str) -> str:
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def strings_in(expr: str) -> list[str]:
    return re.findall(r'"([^"]*)"', expr)


def assign_expr(text: str, name: str) -> str:
    m = re.search(rf"\b{re.escape(name)} = (.+?);", text, re.S)
    if not m:
        die(f"xcodegen.nix has no assignment {name}")
    return m.group(1)


def exclude_env(nix: str) -> dict[str, list[str]]:
    env: dict[str, list[str]] = {}
    for name in ("commonExcludes", "mobileMacPlatformExcludes"):
        expr = assign_expr(nix, name)
        parts: list[str] = []
        for token in re.findall(r"[A-Za-z_][\w]*|\[[^\]]*\]", expr):
            if token.startswith("["):
                parts.extend(strings_in(token))
            elif token in env:
                parts.extend(env[token])
        env[name] = parts
    return env


def resolve_excludes(expr: str, env: dict[str, list[str]]) -> list[str]:
    if not expr:
        return []
    parts: list[str] = []
    for token in re.findall(r"[A-Za-z_][\w]*|\[[^\]]*\]", expr):
        if token.startswith("["):
            parts.extend(strings_in(token))
        elif token in env:
            parts.extend(env[token])
    return parts


def excluded(rel: str, patterns: list[str]) -> bool:
    rel = rel.strip("/")
    base = rel.rsplit("/", 1)[-1]
    for pattern in patterns:
        if pattern.endswith("/**"):
            prefix = pattern[:-3].strip("/")
            if prefix.startswith("**/"):
                needle = prefix[3:]
                if rel == needle or rel.startswith(needle + "/") or f"/{needle}/" in f"/{rel}/":
                    return True
            elif rel == prefix or rel.startswith(prefix + "/"):
                return True
        if fnmatch.fnmatch(rel, pattern) or fnmatch.fnmatch(base, pattern):
            return True
        if pattern.startswith("**/"):
            rest = pattern[3:]
            if fnmatch.fnmatch(base, rest) or fnmatch.fnmatch(rel, rest):
                return True
    return False


def brace_block(text: str, open_at: int) -> str:
    depth = 0
    for i in range(open_at, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[open_at : i + 1]
    die("unclosed brace in xcodegen.nix")
    return ""


def list_body(text: str, name: str) -> str:
    m = re.search(rf"\b{re.escape(name)} = \[", text)
    if not m:
        die(f"xcodegen.nix has no list {name}")
    start = m.end()
    depth = 1
    i = start
    while i < len(text) and depth:
        if text[i] == "[":
            depth += 1
        elif text[i] == "]":
            depth -= 1
        i += 1
    return text[start : i - 1]


def path_blocks(body: str) -> list[str]:
    blocks: list[str] = []
    i = 0
    while True:
        j = body.find("{", i)
        if j < 0:
            break
        block = brace_block(body, j)
        if re.search(r"\bpath\s*=", block):
            blocks.append(block)
        i = j + len(block)
    return blocks


def entry_path(block: str) -> str | None:
    m = re.search(r'\bpath\s*=\s*"([^"]+)"', block)
    if not m:
        return None
    if re.search(r"\bbuildPhase\s*=", block) and "sources" not in block:
        # Resources and folders are not compiled into the link.
        phase = re.search(r'\bbuildPhase\s*=\s*"([^"]+)"', block)
        if phase and phase.group(1) != "sources":
            return None
    if re.search(r'\btype\s*=\s*"folder"', block):
        return None
    return m.group(1)


def entry_excludes(block: str, env: dict[str, list[str]]) -> list[str]:
    m = re.search(r"\bexcludes\s*=\s*([^;]+);", block, re.S)
    if not m:
        return []
    return resolve_excludes(m.group(1), env)


def target_sources_body(nix: str, target: str) -> str:
    m = re.search(rf"(?m)^[ \t]*{re.escape(target)} = (\w[\w-]*) // \{{", nix)
    if m and "sources =" not in nix[m.end() : m.end() + 400]:
        return target_sources_body(nix, m.group(1))
    m = re.search(rf"(?m)^[ \t]*{re.escape(target)} = \{{", nix)
    if not m:
        die(f"xcodegen.nix has no target {target}")
    # sources = [ ... ] ++ helpers
    sm = re.search(r"\bsources\s*=\s*\[", nix[m.end() :])
    if not sm:
        die(f"target {target} has no sources list")
    start = m.end() + sm.end()
    depth = 1
    i = start
    text = nix
    while i < len(text) and depth:
        if text[i] == "[":
            depth += 1
        elif text[i] == "]":
            depth -= 1
        i += 1
    body = text[start : i - 1]
    tail = text[i : i + 180]
    extra = []
    if "iosUtilSources" in tail:
        extra.append(list_body(nix, "iosUtilSources"))
    if "appleMobileEnvUISources" in tail:
        extra.append(list_body(nix, "appleMobileEnvUISources"))
    return body + "\n" + "\n".join(extra)


def nix_subs(srcroot: str) -> dict[str, str]:
    # Workspace checkouts sit beside Wawona. The Nix Xcode project copies
    # those trees into the generated source root, because the build sandbox
    # has no sibling repos.
    srcroot = os.path.abspath(srcroot)
    parent = os.path.dirname(srcroot)

    def pick(name: str) -> str:
        sibling = os.path.join(parent, name)
        inside = os.path.join(srcroot, name)
        if os.path.isdir(sibling):
            return sibling
        return inside

    return {
        "toolbarKeysSrc": pick("ToolbarKeys"),
        "terminalSrc": pick("Terminal"),
    }


def resolve_root(spec: str, srcroot: str) -> str | None:
    m = re.match(r"\$\{(\w+)\}(.*)$", spec)
    if m:
        base = nix_subs(srcroot).get(m.group(1))
        if not base:
            return None
        return os.path.normpath(base + m.group(2))
    return os.path.normpath(os.path.join(srcroot, spec))


def required_files(nix: str, target: str, srcroot: str) -> list[tuple[str, str]]:
    env = exclude_env(nix)
    body = target_sources_body(nix, target)
    found: list[tuple[str, str]] = []
    seen: set[str] = set()
    for block in path_blocks(body):
        spec = entry_path(block)
        if not spec:
            continue
        root = resolve_root(spec, srcroot)
        if not root or not os.path.exists(root):
            die(f"source path missing on disk: {spec} -> {root}")
        patterns = entry_excludes(block, env)
        if os.path.isfile(root):
            rel = os.path.basename(root)
            if os.path.splitext(rel)[1] in COMPILE_EXT and not excluded(rel, patterns):
                if root not in seen:
                    seen.add(root)
                    found.append((root, rel))
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            rel_dir = os.path.relpath(dirpath, root)
            if rel_dir == ".":
                rel_dir = ""
            kept = []
            for name in dirnames:
                rel = f"{rel_dir}/{name}" if rel_dir else name
                if excluded(rel, patterns) or excluded(rel + "/x", patterns):
                    continue
                kept.append(name)
            dirnames[:] = kept
            for name in filenames:
                rel = f"{rel_dir}/{name}" if rel_dir else name
                if os.path.splitext(name)[1] not in COMPILE_EXT:
                    continue
                if excluded(rel, patterns):
                    continue
                full = os.path.join(dirpath, name)
                if full in seen:
                    continue
                seen.add(full)
                found.append((full, name))
    return found


def target_window(pbx: str, target: str) -> str:
    needle = f'name = "{target}";'
    start = 0
    while True:
        i = pbx.find(needle, start)
        if i < 0:
            die(f"project has no native target {target}")
        pre = pbx[max(0, i - 40) : i]
        if "productName" in pre:
            start = i + len(needle)
            continue
        window = pbx[max(0, i - 4000) : i + 200]
        if "isa = PBXNativeTarget" not in window:
            start = i + len(needle)
            continue
        return window


def sources_in_target(pbx: str, target: str) -> set[str]:
    window = target_window(pbx, target)
    isa = window.rfind("isa = PBXNativeTarget")
    if isa < 0:
        die(f"target {target} window has no PBXNativeTarget")
    # Only this target's buildPhases. An earlier target in the window has
    # its own Sources phase and must not be counted.
    m = re.search(r"([A-Fa-f0-9]{24}) /\* Sources \*/", window[isa:])
    if not m:
        die(f"target {target} has no Sources phase")
    phase = re.search(
        rf"{m.group(1)} /\* Sources \*/ = \{{(.*?)\n\t\t\}};",
        pbx,
        re.S,
    )
    if not phase:
        die(f"Sources phase {m.group(1)} missing")
    names = re.findall(r"/\* (.+?) in Sources \*/", phase.group(1))
    return set(names)


def cmd_membership(args: argparse.Namespace) -> None:
    nix = read(os.path.join(args.srcroot, "dependencies/generators/xcodegen.nix"))
    pbx = read(args.project)
    compiled = sources_in_target(pbx, args.target)
    missing = []
    for full, name in required_files(nix, args.target, args.srcroot):
        if name not in compiled:
            missing.append(os.path.relpath(full, args.srcroot))
    if missing:
        shown = "\n".join(f"  {p}" for p in sorted(missing))
        die(
            f"{args.target} would compile {len(missing)} file(s) that are not in "
            f"the Sources phase. Ld then reports an undefined class or Swift type.\n"
            f"{shown}"
        )
    print(f"link contract: {args.target} membership ok ({len(compiled)} compiled inputs)")


def header_functions(text: str) -> list[str]:
    names = []
    for line in text.splitlines():
        s = line.strip()
        if (
            not s
            or s.startswith("#")
            or s.startswith("//")
            or s.startswith("/*")
            or s.startswith("*")
            or s.startswith("typedef")
        ):
            continue
        m = re.match(
            r"(?:extern\s+)?[A-Za-z_][\w\s\*]*\s+([A-Za-z_]\w*)\s*\(",
            s,
        )
        if m and m.group(1) not in SKIP_NAMES:
            names.append(m.group(1))
    return names


def decl_line(line: str) -> bool:
    s = line.strip()
    if "extern " not in s:
        return False
    if s.endswith(";") or "__attribute__" in s:
        return True
    return False


def extern_names(text: str) -> list[str]:
    names = []
    for line in text.splitlines():
        if "extern " not in line or "(" not in line:
            continue
        m = re.search(r"extern\s+[A-Za-z_][\w\s\*]*\s+([A-Za-z_]\w*)\s*\(", line)
        if m:
            names.append(m.group(1))
    return names


def mentioned(text: str, name: str) -> bool:
    token = re.compile(rf"\b{re.escape(name)}\b")
    for line in text.splitlines():
        if not token.search(line) or decl_line(line):
            continue
        return True
    return False


def weak_externs(text: str) -> set[str]:
    names: set[str] = set()
    for line in text.splitlines():
        if "extern " not in line or "weak" not in line:
            continue
        m = re.search(r"extern\s+[A-Za-z_][\w\s\*]*\s+([A-Za-z_]\w*)\s*\(", line)
        if m:
            names.add(m.group(1))
    return names


def object_body(pbx: str, header: str) -> str:
    i = pbx.find(header)
    if i < 0:
        return ""
    brace = pbx.find("{", i)
    if brace < 0:
        return ""
    return brace_block(pbx, brace)


def config_text(pbx: str, target: str) -> str:
    window = target_window(pbx, target)
    isa = window.rfind("isa = PBXNativeTarget")
    ids = re.findall(
        r"buildConfigurationList = ([A-Fa-f0-9]{24})",
        window[isa:],
    )
    if not ids:
        return ""
    # The id also appears as `buildConfigurationList = ID /* ... */;` inside
    # the target. The object itself is a line that starts with the id.
    listing = object_body(
        pbx,
        f"\n\t\t{ids[-1]} /* Build configuration list",
    )
    if not listing:
        return ""
    chunks = []
    for cid, name in re.findall(
        r"([A-Fa-f0-9]{24}) /\* (Debug|Release) \*/",
        listing,
    ):
        block = object_body(pbx, f"\n\t\t{cid} /* {name} */ = ")
        if block:
            chunks.append(block)
    return "\n".join(chunks)


# libSystem and other SDK dylibs satisfy these. They are not in our static
# archives, and a miss here is not a Wawona link-contract failure.
SYSTEM_SYMBOL = re.compile(
    r"^(proc_|objc_|dispatch_|CF|NS|UI|MTL|CG|CA|VT|AU|SC|os_|mach_|pthread_|sandbox_|sysctl)"
)


def expand_build_path(path: str, srcroot: str, derived: str) -> str:
    return (
        path.replace("$(SRCROOT)", srcroot)
        .replace("$(DERIVED_FILE_DIR)", derived)
        .replace("$(inherited)", "")
    )


def ldflags_text(settings: str, sdk: str) -> str:
    keys = []
    if sdk:
        keys.append(f'"OTHER_LDFLAGS[sdk={sdk}*]"')
        if sdk.endswith("simulator"):
            family = sdk[: -len("simulator")]
            keys.append(f'"OTHER_LDFLAGS[sdk={family}simulator*]"')
    keys.append('"OTHER_LDFLAGS"')
    for key in keys:
        i = settings.find(key)
        if i < 0:
            continue
        j = settings.find(");", i)
        if j > i:
            return settings[i:j]
    return settings


def link_archives(settings: str, extra: list[str], srcroot: str, derived: str) -> list[str]:
    found: list[str] = []
    seen: set[str] = set()

    def add(path: str) -> None:
        if not path or path.startswith("-"):
            return
        path = os.path.normpath(expand_build_path(path, srcroot, derived))
        if path in seen or not os.path.isfile(path):
            return
        seen.add(path)
        found.append(path)

    for path in extra:
        add(path)
    if derived and os.path.isdir(derived):
        for name in os.listdir(derived):
            if name.endswith(".a"):
                add(os.path.join(derived, name))
    for path in re.findall(r'"(\$\((?:SRCROOT|DERIVED_FILE_DIR)\)/[^"]+\.a)"', settings):
        add(path)
    for path in re.findall(r'"(/[^"]+\.a)"', settings):
        add(path)
    # -L$(SRCROOT)/.nix-deps/lib/hash is one quoted token.
    lib_dirs = re.findall(r'"-L(\$\((?:SRCROOT|DERIVED_FILE_DIR)\)/[^"]+)"', settings)
    lib_names = re.findall(r'"-l([A-Za-z0-9_+\-.]+)"', settings)
    for directory in lib_dirs:
        for name in lib_names:
            add(os.path.join(expand_build_path(directory, srcroot, derived), f"lib{name}.a"))
    return found


def archive_exports(path: str, cache: dict[str, bytes]) -> bytes:
    if path not in cache:
        with open(path, "rb") as fh:
            cache[path] = fh.read()
    return cache[path]


def exported(blob: bytes, symbol: str) -> bool:
    return symbol.encode("ascii") in blob or f"_{symbol}".encode("ascii") in blob


def cmd_symbols(args: argparse.Namespace) -> None:
    nix = read(os.path.join(args.srcroot, "dependencies/generators/xcodegen.nix"))
    pbx = read(args.project)
    compiled = sources_in_target(pbx, args.target)
    files = [
        full
        for full, name in required_files(nix, args.target, args.srcroot)
        if name in compiled
    ]
    header = os.path.join(
        args.srcroot, "src/platform/macos/ui/Machines/wawona_relay.h"
    )
    blobs = []
    for path in files:
        try:
            blobs.append(read(path))
        except OSError as exc:
            die(f"cannot read {path}: {exc}")
    source = "\n".join(blobs)
    weak = weak_externs(source)
    needed: list[str] = []
    for name in header_functions(read(header)):
        if name not in weak and mentioned(source, name):
            needed.append(name)
    for name in extern_names(source):
        if name not in weak and name not in SKIP_NAMES and mentioned(source, name):
            needed.append(name)
    # Stable, unique.
    ordered: list[str] = []
    seen: set[str] = set()
    for name in needed:
        if name in seen or SYSTEM_SYMBOL.match(name):
            continue
        seen.add(name)
        ordered.append(name)
    if not ordered:
        print(f"link contract: {args.target} references no Relay/extern C symbols")
        return
    settings = ldflags_text(config_text(pbx, args.target), args.sdk or "")
    archives = link_archives(
        settings,
        args.wawona_archive or [],
        args.srcroot,
        args.derived or "",
    )
    if not archives:
        die(f"{args.target} link line has no static archives to search")
    cache: dict[str, bytes] = {}
    missing = []
    for name in ordered:
        if not any(exported(archive_exports(path, cache), name) for path in archives):
            missing.append(name)
    if missing:
        shown = "\n".join(f"  {name}" for name in missing)
        die(
            f"{args.target} calls {len(missing)} C symbol(s) that no linked archive exports "
            f"({len(archives)} archives on the {args.sdk or 'default'} link line).\n"
            f"{shown}"
        )
    print(
        f"link contract: {args.target} exports ok "
        f"({len(ordered)} symbols, {len(archives)} archives)"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)
    for name in ("membership", "symbols"):
        cmd = sub.add_parser(name)
        cmd.add_argument("--project", required=True)
        cmd.add_argument("--target", required=True)
        cmd.add_argument("--srcroot", required=True)
        cmd.add_argument("--wawona-archive", action="append", default=[])
        cmd.add_argument("--derived", default="")
        cmd.add_argument("--sdk", default="")
    args = parser.parse_args()
    if args.cmd == "membership":
        cmd_membership(args)
    else:
        cmd_symbols(args)


if __name__ == "__main__":
    main()
