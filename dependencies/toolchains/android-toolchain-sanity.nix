{
  pkgs,
  androidToolchain,
}:

pkgs.runCommand "android-toolchain-sanity" { } ''
  set -euo pipefail

  cc="${androidToolchain.androidCC}"
  cxx="${androidToolchain.androidCXX}"
  resource_dir="$("$cc" -print-resource-dir)"
  fallback="${if androidToolchain.androidNdkIsFallback then "true" else "false"}"
  ndk_prebuilt_prefix="${androidToolchain.androidndkRoot}/toolchains/llvm/prebuilt"

  "$cc" --version >/dev/null
  "$cxx" --version >/dev/null

  # Canary: fallback hosts must not resolve clang resource headers from the
  # NDK prebuilt toolchain; that regresses into NEON builtin mismatches.
  if [ "$fallback" = "true" ]; then
    case "$resource_dir" in
      "$ndk_prebuilt_prefix"/*)
        echo "android toolchain sanity failed: fallback compiler resolved NDK resource-dir: $resource_dir" >&2
        exit 1
        ;;
    esac
  fi

  cat > neon-canary.c <<'EOF'
  #include <arm_neon.h>
  int main(void) {
    int8x8_t x = vdup_n_s8(1);
    return vget_lane_s8(x, 0);
  }
EOF
  "$cc" -c neon-canary.c -o neon-canary.o

  mkdir -p "$out"
  {
    echo "fallback=$fallback"
    echo "resource_dir=$resource_dir"
    echo "host_tag=${androidToolchain.androidNdkHostTag}"
    echo "compat_host_tag=${androidToolchain.androidNdkCompatHostTag}"
  } > "$out/report.txt"
''
