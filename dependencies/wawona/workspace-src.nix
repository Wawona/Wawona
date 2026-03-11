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
{ pkgs, wawonaSrc, waypipeSrc, wawonaVersion, platform ? "ios" }:

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
    
    # Only remove binaries from the source tree for mobile platforms to prevent cross-compilation errors.
    # macOS needs these for utility tools like keyboard-test-client.
    if [ "${platform}" != "macos" ]; then
      echo "⚠️  Removing binaries for mobile platform: ${platform}"
      rm -rf $out/src/bin
      rm -f $out/src/main.rs
    fi


    # Inject pre-patched waypipe source
    if [ -n "${toString waypipeSrc}" ]; then
      mkdir -p $out/waypipe
      cp -r ${waypipeSrc}/* $out/waypipe/
      chmod -R u+w $out/waypipe

      echo "✓ Waypipe source injected"
    fi

    # Patch root Cargo.toml version and Cargo.lock consistency
    cd $out
    ${pkgs.python3}/bin/python3 <<'EOF'
from pathlib import Path
import re

platform = "${platform}"

p = Path("Cargo.toml")
if p.exists():
    s = p.read_text()
    
    # Only restrict binaries for mobile platforms
    if platform != "macos":
        print(f"⚠️  Disabling binaries/autobins for mobile platform: {platform}")
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

# Android uses OpenSSH (fork/exec), not libssh2. Strip ssh2 from root Cargo.toml,
# waypipe/Cargo.toml, and Cargo.lock so `cargo metadata --locked` passes.
if platform == "android":
    # 1. Root Cargo.toml
    p = Path("Cargo.toml")
    if p.exists():
        s = p.read_text()
        s = re.sub(r'^ssh2\s*=.*$\n?', "", s, flags=re.MULTILINE)
        s = re.sub(r'"ssh2",?\n?', "", s)
        s = re.sub(r'"dep:ssh2",?\n?', "", s)
        p.write_text(s)
        print("✓ Stripped ssh2 from root Cargo.toml")

    # 2. waypipe/Cargo.toml
    wp_toml = Path("waypipe/Cargo.toml")
    if wp_toml.exists():
        s = wp_toml.read_text()
        s = re.sub(r'^ssh2\s*=.*$\n?', "", s, flags=re.MULTILINE)
        s = re.sub(r'"ssh2",?\n?', "", s)
        s = re.sub(r'"dep:ssh2",?\n?', "", s)
        wp_toml.write_text(s)
        print("✓ Stripped ssh2 from waypipe/Cargo.toml")

    # 3. Cargo.lock: Remove ssh2, libssh2-sys, and ssh2-sys blocks entirely
    lock = Path("Cargo.lock")
    if lock.exists():
        content = lock.read_text()
        blocks = content.split('\n\n')
        new_blocks = []
        
        # Names to strip entirely
        strip_names = {'"ssh2"', '"libssh2-sys"', '"ssh2-sys"'}
        
        for block in blocks:
            lines = block.splitlines()
            if not lines: continue
            
            is_package = lines[0].strip() == "[[package]]"
            name = None
            if is_package:
                for line in lines:
                    if line.strip().startswith("name = "):
                        name = line.strip().split("name = ")[1]
                        break
            
            if is_package and name in strip_names:
                print(f"✓ Stripped package block: {name}")
                continue
            
            # Also strip from dependencies arrays in other blocks
            new_lines = []
            in_deps = False
            for line in lines:
                s = line.strip()
                if s == "dependencies = [":
                    in_deps = True
                elif s == "]":
                    in_deps = False
                
                if in_deps and any(n in s for n in strip_names):
                    continue
                new_lines.append(line)
            
            new_blocks.append('\n'.join(new_lines))
        
        lock.write_text('\n\n'.join(new_blocks) + '\n')
        print("✓ Refined ssh2 stripping in Cargo.lock (blocks and references removed)")
EOF
  '';
}
