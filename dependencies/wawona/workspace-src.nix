# Assembles a complete Cargo workspace source tree for crate2nix.
#
# Combines:
# 1. Filtered wawona source (no .git, target/, Inspiration/, etc.)
# 2. Pre-patched waypipe source injected at ./waypipe/
# 3. Regenerated Cargo.lock that includes waypipe's sub-crates
#
# The Cargo.lock regeneration is critical: the original lockfile doesn't
# include waypipe's internal path dependencies (wrap-ffmpeg, wrap-lz4, etc.)
# Since those paths only appear after injecting waypipe, we must regenerate
# the lock file to satisfy `cargo metadata --locked` in crate2nix.
#
{ pkgs, wawonaSrc, waypipeSrc, wawonaVersion, platform ? "ios", coreutilsSrc ? null, terminalSrc ? null }:

pkgs.stdenvNoCC.mkDerivation {
  name = "wawona-workspace-src";
  
  src = wawonaSrc;

  nativeBuildInputs = [ pkgs.python3 ];

  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    # Copy the wawona source as the base
    cp -r . $out
    chmod -R u+w $out
    
    # Mobile platforms do not ship the standalone root binary entrypoint.
    if [ "${platform}" != "macos" ]; then
      echo "⚠️  Removing root binary entrypoint for mobile platform: ${platform}"
      rm -f $out/src/main.rs
      rm -rf $out/src/bin
    fi


    # Nested path crates must not define a Cargo workspace. crate2nix /
    # `cargo metadata` fails with "multiple workspace roots" if they do.
    # Strip bare `[workspace]` and every `[workspace.*]` table (uutils uses
    # `[workspace.package]` / `[workspace.dependencies]` without a bare
    # `[workspace]` header). Path deps and member manifests still resolve.
    strip_nested_workspace() {
      ${pkgs.python3}/bin/python3 - "$1" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
if not p.exists():
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
PY
    }

    # Drop any local / leftover trees before inject (gitignored checkouts).
    rm -rf $out/waypipe $out/coreutils

    # Inject pre-patched waypipe source
    if [ -n "${toString waypipeSrc}" ]; then
      mkdir -p $out/waypipe
      cp -r ${waypipeSrc}/* $out/waypipe/
      chmod -R u+w $out/waypipe

      rm -f $out/waypipe/Cargo.lock
      rm -rf $out/waypipe/.git
      strip_nested_workspace "$out/waypipe/Cargo.toml"

      echo "✓ Waypipe source injected (nested lockfile + [workspace*] removed)"
    fi

    # Inject pre-patched uutils coreutils source (in-process ls/cat/cp/...).
    # Subcrates keep their own manifests for uu_* field inheritance.
    if [ -n "${toString coreutilsSrc}" ]; then
      mkdir -p $out/coreutils
      cp -r ${coreutilsSrc}/* $out/coreutils/
      chmod -R u+w $out/coreutils

      rm -f $out/coreutils/Cargo.lock
      rm -rf $out/coreutils/.git

      # uutils members use `clap.workspace = true`. After we strip nested
      # `[workspace.*]`, those keys must live on the *root* workspace or
      # `cargo build` fails with "`workspace.dependencies` was not defined"
      # (AppImage / wawona-linux-ui on aarch64-linux). Merge first, then strip.
      ${pkgs.python3}/bin/python3 - "$out/Cargo.toml" "$out/coreutils/Cargo.toml" <<'PY'
from pathlib import Path
import sys

root_path = Path(sys.argv[1])
nested_path = Path(sys.argv[2])

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

def ensure_workspace_deps_table(text: str, deps_body: str) -> str:
    if not deps_body.strip():
        return text
    marker = "[workspace.dependencies]"
    if marker in text:
        # Append missing keys only (keep existing root pins).
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
        # Insert after the marker line.
        lines = text.splitlines(True)
        out = []
        for i, line in enumerate(lines):
            out.append(line)
            if line.strip() == marker:
                out.extend(extra)
        return "".join(out)
    # Prefer after [workspace] block.
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

nested = nested_path.read_text()
deps = extract_workspace_deps(nested)
if deps.strip():
    root = root_path.read_text()
    root_path.write_text(ensure_workspace_deps_table(root, deps))
    print(f"Merged coreutils workspace.dependencies into root ({len(deps.splitlines())} lines)")
else:
    print("note: coreutils had no [workspace.dependencies] to merge")
PY

      strip_nested_workspace "$out/coreutils/Cargo.toml"

      echo "✓ coreutils source injected (workspace.deps merged; nested [workspace*] removed)"
    fi

    # Terminal screen. The committed path is a symlink to the sibling repo.
    # Replace it with the flake input so the sandbox does not follow the link.
    # installPhase is a Nix string: a null terminalSrc must not appear in path
    # interpolation (cannot coerce null to a string).
    ${if terminalSrc != null then ''
    mkdir -p $out/src/term
    rm -f $out/src/term/screen.rs
    cp ${terminalSrc}/src/screen.rs $out/src/term/screen.rs
    chmod u+w $out/src/term/screen.rs
    echo "✓ Terminal screen injected"
    '' else ''
    echo "note: terminalSrc unset; keeping workspace term screen as packaged"
    ''}

    # Patch root Cargo.toml version and Cargo.lock consistency
    cd $out
    ${pkgs.python3}/bin/python3 <<'EOF'
from pathlib import Path
import re

platform = "${platform}"

p = Path("Cargo.toml")
if p.exists():
    s = p.read_text()
    
    # Only restrict root binary auto-discovery for mobile platforms
    if platform != "macos":
        print(f"⚠️  Disabling root binaries/autobins for mobile platform: {platform}")
        # Mobile backends link static libraries only.
        s = re.sub(r'^crate-type = .*$', 'crate-type = ["rlib", "staticlib"]', s, flags=re.MULTILINE)
        # Inject autobins = false to prevent binary auto-discovery
        s = re.sub(r'(\[package\]\n)', r'\1autobins = false\n', s)
        
        # Strip all [[bin]] sections to prevent cross-compilation linking errors for unused binaries
        lines = s.split('\n')
        out_lines = []
        in_bin = False
        for line in lines:
            stripped = line.strip()
            if stripped.startswith('[[bin]]'):
                in_bin = True
                continue
            if in_bin and stripped.startswith('[') and not stripped.startswith('[[bin]]'):
                in_bin = False
            if not in_bin:
                out_lines.append(line)
        s = '\n'.join(out_lines)
    
    s = re.sub(r'^version = .*', 'version = "${wawonaVersion}"', s, flags=re.MULTILINE)
    
    p.write_text(s)
    print(f"Patched Cargo.toml version to ${wawonaVersion}")

# Patch wawona version in Cargo.lock to match the patched Cargo.toml.
# cargo metadata --locked fails when Cargo.toml version != Cargo.lock version.
wawona_version = "${wawonaVersion}"
lock = Path("Cargo.lock")
if lock.exists():
    content = lock.read_text()
    in_wawona = False
    lines = content.splitlines(True)
    out = []
    for line in lines:
        if line.strip() == 'name = "wawona"':
            in_wawona = True
        elif in_wawona and line.strip().startswith("version = "):
            out.append(f'version = "{wawona_version}"\n')
            in_wawona = False
            continue
        elif in_wawona and line.strip().startswith("["):
            in_wawona = False
        out.append(line)
    lock.write_text("".join(out))
    print(f"Patched wawona version to {wawona_version} in Cargo.lock")

EOF
  '';
}
