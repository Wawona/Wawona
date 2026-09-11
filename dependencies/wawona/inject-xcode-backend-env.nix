# Prepend WAWONA_BACKEND_OUT* so xcode-prebuild.sh copies already-built
# libwawona.a instead of nested `nix build --impure` (the inner compile that
# dominated product-build wall time).
{
  lib,
  rustBackend ? null,
  xcodeTarget,
  companionBackends ? { },
  mobileGuestArtifacts ? null,
  mobileContainerGuestArtifacts ? null,
}:
old:
let
  envName = t: "WAWONA_BACKEND_OUT_" + builtins.replaceStrings [ "-" ] [ "_" ] t;
  exports =
    lib.optionalString (rustBackend != null) ''
      export WAWONA_BACKEND_OUT="${rustBackend}"
      export ${envName xcodeTarget}="${rustBackend}"
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (t: drv: ''
        export ${envName t}="${drv}"
      '') companionBackends
    )
    + lib.optionalString (mobileGuestArtifacts != null) ''
      export WAWONA_MOBILE_GUEST_DIR="${mobileGuestArtifacts}"
    ''
    + lib.optionalString (mobileContainerGuestArtifacts != null) ''
      export WAWONA_MOBILE_CONTAINER_GUEST_DIR="${mobileContainerGuestArtifacts}"
    '';
  signed = (import ./match-host-signing-attrs.nix { inherit lib; }) old;
in
signed
// {
  buildPhase = exports + (signed.buildPhase or "");
}
