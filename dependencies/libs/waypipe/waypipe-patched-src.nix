# Produces a pre-patched waypipe source tree for use as a Cargo path dependency.
#
# This is a PURE SOURCE derivation — no compilation. It takes the raw waypipe
# source and applies the iOS/Android/macOS compatibility patches, producing a
# ready-to-compile source tree. By making this a separate derivation, the Nix
# hash only changes when the patch script or raw waypipe source changes.
# Changing wawona source does NOT invalidate this derivation.
#
# Usage:
#   waypipePatchedSrc = pkgs.callPackage ./waypipe-patched-src.nix {
#     inherit waypipe-src;
#     patchScript = ./patch-waypipe-source.sh;
#     platform = "ios";  # or "macos" or "android"
#   };
#
{ pkgs, waypipe-src, patchScript, platform ? "ios", waypipePatchHelpers ? {} }:

pkgs.stdenvNoCC.mkDerivation {
  name = "waypipe-patched-src-${platform}";
  src = waypipe-src;

  nativeBuildInputs = [ pkgs.python3 ];

  # No compilation — just patching
  dontBuild = true;
  dontFixup = true;

  unpackPhase = ''
    # Copy source to a writable directory
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
    # Run the platform-specific patch script
    cp ${patchScript} ./patch.sh
    chmod +x ./patch.sh
    bash ./patch.sh

    # Verify libssh2 bridge was wired (iOS/macOS use patch-waypipe-source.sh)
    if [ "${platform}" = "ios" ] || [ "${platform}" = "macos" ]; then
      if ! grep -q "run_client_oneshot_libssh2" src/main.rs 2>/dev/null && \
         ! grep -q "run_client_oneshot_libssh2" src/lib.rs 2>/dev/null; then
        echo "ERROR: libssh2 bridge NOT wired - run_client_oneshot_libssh2 sentinel not found"
        echo "  Upstream waypipe source may have changed. Update old_block in patch-waypipe-source.sh"
        exit 1
      fi
      echo "✓ Verified libssh2 bridge wired (run_client_oneshot_libssh2 found)"
    fi

    # Copy the fully patched source tree to $out
    cd ..
    cp -r source $out
  '';
}
