# Assembles a complete Cargo workspace source tree for the cargo backend:
# the filtered wawona source with the patched waypipe and coreutils path
# crates injected, prepared by `cargo xtask workspace prepare` so the
# committed Cargo.lock still holds under `--locked`.
{ pkgs, wawonaSrc, waypipeSrc, wawonaVersion, platform ? "ios", coreutilsSrc ? null, terminalSrc ? null
  # Full uzaaft/libghostty-rs checkout (same rev as Cargo.toml). When set,
  # stage expanded path crates under vendor/ so cargo does not hit
  # `edition.workspace` after git cargo-vendor of a workspace member.
, libghosttyRsSrc ? null
, xtask ? pkgs.buildPackages.callPackage ./xtask.nix { }
}:

pkgs.stdenvNoCC.mkDerivation {
  name = "wawona-workspace-src";

  src = wawonaSrc;

  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    cp -r . $out
    chmod -R u+w $out

    # Mobile platforms do not ship the standalone root binary entrypoint.
    if [ "${platform}" != "macos" ] && [ "${platform}" != "linux" ]; then
      rm -f $out/src/main.rs
      rm -rf $out/src/bin
    fi

    # Drop any local / leftover trees before inject (gitignored checkouts).
    rm -rf $out/waypipe $out/coreutils

    if [ -n "${toString waypipeSrc}" ]; then
      mkdir -p $out/waypipe
      cp -r ${waypipeSrc}/* $out/waypipe/
      chmod -R u+w $out/waypipe
      rm -rf $out/waypipe/Cargo.lock $out/waypipe/.git
    fi

    # uutils coreutils (in-process ls/cat/cp/...). Subcrates keep their own
    # manifests for uu_* field inheritance.
    if [ -n "${toString coreutilsSrc}" ]; then
      mkdir -p $out/coreutils
      cp -r ${coreutilsSrc}/* $out/coreutils/
      chmod -R u+w $out/coreutils
      rm -rf $out/coreutils/Cargo.lock $out/coreutils/.git
    fi

    # Terminal VT (libghostty-vt). Committed paths are sibling symlinks;
    # replace with flake input so the sandbox does not follow the link.
    # A null terminalSrc must not appear in path interpolation.
    ${if terminalSrc != null then ''
    mkdir -p $out/src/term
    rm -f $out/src/term/screen.rs $out/src/term/kitty.rs
    for f in cell engine ffi_surface key_input; do
      rm -f $out/src/term/$f.rs
      cp ${terminalSrc}/src/$f.rs $out/src/term/$f.rs
      chmod u+w $out/src/term/$f.rs
    done
    '' else ""}

    ${xtask}/bin/xtask workspace prepare $out \
      ${if libghosttyRsSrc != null then "--libghostty ${libghosttyRsSrc}" else ""} \
      --platform ${platform} --version ${wawonaVersion}
  '';
}
