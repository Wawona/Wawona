# WLCS (Wayland Conformance Test Suite) integration (ci-l2-wlcs).
#
# Builds the Wawona WLCS server-integration shared object from
# src/tests/wlcs/wlcs_server_integration.c and packages a runner that points
# WLCS at it. This is a SKELETON: the integration's client-socket + window
# hooks are stubbed (see the .c), so the runner currently reports WLCS failures
# rather than a green battery. Wiring the hooks + running the battery is the
# Linux CI lane (nightly full-matrix), hence the runtime is deferred here.
#
# Linux-only (WLCS + Wayland server backend). On non-Linux this evaluates but is
# not expected to be built.
{ lib
, stdenv
, wlcs
, gtest
, pkg-config
, wayland
, makeWrapper
, writeShellApplication
}:

let
  integration = stdenv.mkDerivation {
    pname = "wawona-wlcs-integration";
    version = "0.1.0";
    src = ../../src/tests/wlcs;

    nativeBuildInputs = [ pkg-config ];
    buildInputs = [ wayland ];

    buildPhase = ''
      runHook preBuild
      $CC -shared -fPIC -o libwawona_wlcs.so wlcs_server_integration.c
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib
      cp libwawona_wlcs.so $out/lib/
      runHook postInstall
    '';

    meta = {
      description = "Wawona WLCS server-integration shared object (skeleton)";
      platforms = lib.platforms.linux;
    };
  };
in
writeShellApplication {
  name = "wawona-wlcs-run";
  runtimeInputs = [ wlcs ];
  text = ''
    set -euo pipefail
    # WLCS loads the compositor integration .so and runs its test battery.
    # NOTE: the integration is a skeleton; expect failures until the
    # create_client_socket / window hooks are implemented.
    exec wlcs "${integration}/lib/libwawona_wlcs.so" "$@"
  '';
}
