# Produces a pre-patched uutils "coreutils" source tree for use as a Cargo path
# dependency. Mirrors dependencies/libs/waypipe/waypipe-patched-src.nix.
#
# This is a PURE SOURCE derivation — no compilation. It takes the raw uutils
# source and turns the umbrella multicall binary into a static library exposing
# wawona_coreutils_main(). Because it is a separate derivation, the Nix hash
# only changes when the patch script or the pinned coreutils source changes;
# editing wawona source does NOT invalidate it.
#
# Usage:
#   coreutilsPatchedSrc = pkgs.callPackage ./coreutils-patched-src.nix {
#     inherit coreutils-src;
#     patchScript = ./patch-coreutils-source.sh;
#     platform = "ios";  # or "macos" / "android"
#   };
{ pkgs, coreutils-src, patchScript, platform ? "ios" }:

pkgs.stdenvNoCC.mkDerivation {
  name = "coreutils-patched-src-${platform}";
  src = coreutils-src;

  nativeBuildInputs = [ pkgs.python3 ];

  dontBuild = true;
  dontFixup = true;

  unpackPhase = ''
    if [ -d "$src" ]; then
      cp -r "$src" source
    else
      mkdir source
      tar -xf "$src" -C source --strip-components=1
    fi
    chmod -R u+w source
    cd source
  '';

  installPhase = ''
    cp ${patchScript} ./patch.sh
    chmod +x ./patch.sh
    bash ./patch.sh

    # Verify the C entry point landed; fail loudly if upstream layout drifted.
    if ! grep -q "wawona_coreutils_main" src/bin/coreutils.rs 2>/dev/null; then
      echo "ERROR: wawona_coreutils_main not wired — uutils layout may have changed." >&2
      echo "  Update dependencies/libs/coreutils/patch-coreutils-source.sh anchors." >&2
      exit 1
    fi
    echo "✓ Verified wawona_coreutils_main present in src/bin/coreutils.rs"

    cd ..
    cp -r source $out
  '';
}
