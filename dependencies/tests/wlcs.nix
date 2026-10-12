# WLCS (Wayland Conformance Test Suite) integration and grading runner.
{ lib
, stdenv
, wlcs
, pkg-config
, wayland
, python3
, wawonaBackend
, writeShellApplication
}:

let
  integration = stdenv.mkDerivation {
    pname = "wawona-wlcs-integration";
    version = "0.1.0";
    src = ../../src/tests/wlcs;

    nativeBuildInputs = [ pkg-config ];
    buildInputs = [ wlcs wayland wawonaBackend ];

    buildPhase = ''
      runHook preBuild
      $CC -std=gnu11 -shared -fPIC \
        $(pkg-config --cflags wlcs wayland-client) \
        -o libwawona_wlcs.so wlcs_server_integration.c \
        -L${wawonaBackend}/lib -lwawona_core \
        $(pkg-config --libs wayland-client) -lpthread \
        -Wl,-rpath,${wawonaBackend}/lib
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib
      cp libwawona_wlcs.so $out/lib/
      runHook postInstall
    '';

    meta = {
      description = "Wawona WLCS server-integration shared object";
      platforms = lib.platforms.linux;
    };
  };
in
writeShellApplication {
  name = "wawona-wlcs-run";
  runtimeInputs = [ wlcs python3 ];
  text = ''
    set -euo pipefail

    output_dir="''${WAWONA_WLCS_OUTPUT_DIR:-wlcs-results}"
    minimum_pass_rate="''${WAWONA_WLCS_MINIMUM_PASS_RATE:-100}"
    maximum_failures="''${WAWONA_WLCS_MAXIMUM_FAILURES:-0}"
    declare -a wlcs_args=()
    while (($#)); do
      case "$1" in
        --output-dir)
          output_dir="$2"; shift 2 ;;
        --minimum-pass-rate)
          minimum_pass_rate="$2"; shift 2 ;;
        --maximum-failures)
          maximum_failures="$2"; shift 2 ;;
        --help)
          cat <<'HELP'
Usage: wawona-wlcs-run [runner options] [GoogleTest options]
  --output-dir DIR          Report directory (default: wlcs-results)
  --minimum-pass-rate N     Required percentage (default: 100)
  --maximum-failures N      Required failure ceiling (default: 0)

Examples:
  wawona-wlcs-run
  wawona-wlcs-run --gtest_filter='*Xdg*'
HELP
          exit 0 ;;
        *)
          wlcs_args+=("$1"); shift ;;
      esac
    done

    mkdir -p "$output_dir"
    output_dir="$(realpath "$output_dir")"
    xml="$output_dir/wlcs.xml"
    set +e
    wlcs "${integration}/lib/libwawona_wlcs.so" \
      "--gtest_output=xml:$xml" "''${wlcs_args[@]}" \
      2>&1 | tee "$output_dir/wlcs.log"
    wlcs_status="''${PIPESTATUS[0]}"
    set -e

    python3 ${../../scripts/wlcs-grade.py} \
      --xml "$xml" \
      --json "$output_dir/summary.json" \
      --markdown "$output_dir/summary.md" \
      --wlcs-exit-code "$wlcs_status" \
      --minimum-pass-rate "$minimum_pass_rate" \
      --maximum-failures "$maximum_failures"
  '';
  derivationArgs = {
    passthru = { inherit integration; };
    meta = {
      description = "Run and grade Wawona against nixpkgs WLCS";
      platforms = lib.platforms.linux;
      mainProgram = "wawona-wlcs-run";
    };
  };
}
