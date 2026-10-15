# Prepend WAWONA_BACKEND_OUT* so xcode-prebuild.sh copies already-built
# libwawona.a instead of nested `nix build --impure` (the inner compile that
# dominated product-build wall time). Also inject zsh/fastfetch archives so
# the same script never talks to nix-daemon inside a sandboxed product build
# (NIX_BUILD_TOP + allowed-users deny).
{
  lib,
  rustBackend ? null,
  xcodeTarget,
  companionBackends ? { },
  # Store path to libwawona-zsh.a for the primary target.
  zshLib ? null,
  # Store path to libfastfetch.a for the primary target.
  fastfetchLib ? null,
  # Optional per-target shell archives for companions (e.g. watchOS inside iOS).
  # Attrset of target name -> { zshLib = ...; fastfetchLib = ...; }
  companionShellLibs ? { },
  mobileGuestArtifacts ? null,
  mobileGuestArtifacts16k ? null,
  mobileContainerGuestArtifacts ? null,
}:
old:
let
  envName = t: "WAWONA_BACKEND_OUT_" + builtins.replaceStrings [ "-" ] [ "_" ] t;
  shellEnv = prefix: t: "${prefix}_" + builtins.replaceStrings [ "-" ] [ "_" ] t;
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
    + lib.optionalString (zshLib != null) ''
      export WAWONA_ZSH_LIB="${zshLib}"
      export ${shellEnv "WAWONA_ZSH_LIB" xcodeTarget}="${zshLib}"
    ''
    + lib.optionalString (fastfetchLib != null) ''
      export WAWONA_FF_LIB="${fastfetchLib}"
      export ${shellEnv "WAWONA_FF_LIB" xcodeTarget}="${fastfetchLib}"
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (
        t: shells:
        lib.optionalString (shells.zshLib or null != null) ''
          export ${shellEnv "WAWONA_ZSH_LIB" t}="${shells.zshLib}"
        ''
        + lib.optionalString (shells.fastfetchLib or null != null) ''
          export ${shellEnv "WAWONA_FF_LIB" t}="${shells.fastfetchLib}"
        ''
      ) companionShellLibs
    )
    + lib.optionalString (mobileGuestArtifacts != null) ''
      export WAWONA_MOBILE_GUEST_DIR="${mobileGuestArtifacts}"
    ''
    + lib.optionalString (mobileGuestArtifacts16k != null) ''
      export WAWONA_MOBILE_GUEST_16K_DIR="${mobileGuestArtifacts16k}"
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
