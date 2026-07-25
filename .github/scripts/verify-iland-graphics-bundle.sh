#!/usr/bin/env bash
# Enforce the shipped graphics capability matrix on an unpacked app/artifact.
set -euo pipefail

platform=""
root=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform) platform="${2:-}"; shift 2 ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) root="$1"; shift ;;
  esac
done

case "$platform" in
  macos|macos-desktop|ios|ipados|visionos|tvos|watchos|android) ;;
  *) echo "usage: $0 --platform <target> <app-or-unpacked-root>" >&2; exit 2 ;;
esac
if [[ -z "$root" || ! -e "$root" ]]; then
  echo "missing or invalid root: ${root:-"(empty)"}" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
if [[ "$platform" == "macos-desktop" ]]; then
  "$script_dir/verify-iland-mode-b-bundle.sh" --mode present "$root"
else
  "$script_dir/verify-iland-mode-b-bundle.sh" --mode absent "$root"
fi

# Apple mobile links ANGLE and MoltenVK statically, so there is no driver file
# to look for. Release binaries are stripped, but both drivers keep identifying
# strings in __TEXT, which survive stripping.
mach_o_files() {
  while IFS= read -r candidate; do
    if file "$candidate" 2>/dev/null | grep -q 'Mach-O'; then
      echo "$candidate"
    fi
  done < <(find "$root" -type f -print)
}

# grep -c rather than -q: -q exits on the first hit, and the resulting SIGPIPE
# on strings would be turned into a pipeline failure by `set -o pipefail`.
bundle_has_marker() {
  local marker="$1" binary hits
  while IFS= read -r binary; do
    hits="$(strings -a "$binary" 2>/dev/null | grep -cF -- "$marker" || true)"
    if [[ "$hits" -gt 0 ]]; then
      echo "$binary"
      return 0
    fi
  done < <(mach_o_files)
  return 1
}

# Whole-string form, for markers that are also substrings of prose. ANGLE's
# renderer string is the standalone literal "ANGLE (", but kmscube's own UI
# copy reads "Spinning GL cube via iland + ANGLE (userland KMS)" on every
# target, driver or not.
bundle_has_exact_marker() {
  local marker="$1" binary hits
  while IFS= read -r binary; do
    hits="$(strings -a "$binary" 2>/dev/null | grep -cxF -- "$marker" || true)"
    if [[ "$hits" -gt 0 ]]; then
      echo "$binary"
      return 0
    fi
  done < <(mach_o_files)
  return 1
}

# Count defined Vulkan/EGL entry points. Strings alone are ambiguous: shared
# driver-selection code embeds literals like "vulkan/icd.d/MoltenVK_icd.json",
# and Rust's ash crate embeds enum names such as IOSSurfaceCreateFlagsMVK, on
# targets that link no driver at all.
bundle_driver_symbols() {
  local binary total=0 count
  while IFS= read -r binary; do
    count="$(nm "$binary" 2>/dev/null | grep -cE ' [TtSs] _(vk[A-Z]|egl[A-Z]|angle_egl)' || true)"
    total=$(( total + count ))
  done < <(mach_o_files)
  echo "$total"
}

if [[ "$platform" == "ios" || "$platform" == "ipados" || "$platform" == "visionos" ]]; then
  # "MoltenVK version" is the driver's own banner, unlike the bare name which
  # also shows up in ICD path literals.
  if ! carrier="$(bundle_has_marker 'MoltenVK version')"; then
    echo "FAIL: $platform bundle has no statically linked MoltenVK" >&2
    exit 1
  fi
  echo "OK: $platform MoltenVK found in $carrier"

  if ! carrier="$(bundle_has_exact_marker 'ANGLE (')"; then
    echo "FAIL: $platform bundle has no statically linked ANGLE" >&2
    exit 1
  fi
  echo "OK: $platform ANGLE found in $carrier"

  # Drivers may be static or embedded frameworks, but they must resolve inside
  # the app bundle. An absolute path outside the bundle would mean loading a
  # driver the store never reviewed.
  while IFS= read -r binary; do
    while IFS= read -r dep; do
      case "$dep" in
        @*) ;;
        /System/*|/usr/lib/*) ;;
        *)
          echo "FAIL: $platform loads a driver from outside the bundle: $binary" >&2
          echo "       -> $dep" >&2
          exit 1
          ;;
      esac
    done < <(otool -L "$binary" 2>/dev/null \
               | grep $'^\t' \
               | awk '{print $1}' \
               | grep -E 'libvulkan|libEGL|libGLESv2|MoltenVK' || true)
  done < <(mach_o_files)
fi

if [[ "$platform" == "tvos" || "$platform" == "watchos" ]]; then
  for marker in 'MoltenVK version' 'SwiftShader'; do
    if carrier="$(bundle_has_marker "$marker")"; then
      echo "FAIL: $platform bundle statically embeds forbidden driver '$marker': $carrier" >&2
      exit 1
    fi
  done

  if carrier="$(bundle_has_exact_marker 'ANGLE (')"; then
    echo "FAIL: $platform bundle statically embeds forbidden driver 'ANGLE': $carrier" >&2
    exit 1
  fi

  driver_symbols="$(bundle_driver_symbols)"
  if [[ "$driver_symbols" -gt 0 ]]; then
    echo "FAIL: $platform bundle defines $driver_symbols Vulkan/EGL entry points; these targets are software-only" >&2
    exit 1
  fi
  echo "OK: $platform defines no Vulkan/EGL entry points"

  forbidden_files="$(
    find "$root" -type f \
      \( -iname '*angle*' -o -iname '*moltenvk*' -o -iname '*vulkan*icd*' \
         -o -iname '*swiftshader*' -o -name 'libvulkan*' \
         -o -name 'libEGL*' -o -name 'libGLES*' \) -print 2>/dev/null || true
  )"
  if [[ -n "$forbidden_files" ]]; then
    echo "FAIL: $platform bundle contains forbidden GPU driver artifacts:" >&2
    echo "$forbidden_files" >&2
    exit 1
  fi

  if command -v otool >/dev/null 2>&1; then
    while IFS= read -r binary; do
      if file "$binary" 2>/dev/null | grep -q 'Mach-O'; then
        linked="$(otool -L "$binary" 2>/dev/null || true)"
        if grep -Eq 'IOKit|MoltenVK|libEGL|libGLES|Vulkan' <<<"$linked"; then
          echo "FAIL: $platform Mach-O links a forbidden graphics dependency: $binary" >&2
          echo "$linked" >&2
          exit 1
        fi
      fi
    done < <(find "$root" -type f -print)
  fi
fi

if [[ "$platform" == "android" ]]; then
  apple_artifacts="$(
    find "$root" -type f \
      \( -name '*.dylib' -o -iname '*MoltenVK*' -o -iname '*IOSurface*' \) \
      -print 2>/dev/null || true
  )"
  if [[ -n "$apple_artifacts" ]]; then
    echo "FAIL: Android bundle contains Apple-only graphics artifacts:" >&2
    echo "$apple_artifacts" >&2
    exit 1
  fi

  direct_kernel_drivers="$(
    find "$root" -type f \
      \( -iname '*turnip*' -o -iname '*freedreno*' \) \
      -print 2>/dev/null || true
  )"
  if [[ -n "$direct_kernel_drivers" ]]; then
    echo "FAIL: Android runtime-only bundle contains direct KGSL driver artifacts:" >&2
    echo "$direct_kernel_drivers" >&2
    exit 1
  fi

  for required in libEGL_angle.so libGLESv2_angle.so libvk_swiftshader.so; do
    if ! find "$root" -type f -name "$required" -print -quit | grep -q .; then
      echo "FAIL: Android graphics bundle missing $required" >&2
      exit 1
    fi
  done
fi

if [[ "$platform" == "macos" ]]; then
  for required in libMoltenVK.dylib libvulkan_kosmickrisp.dylib; do
    if ! find "$root" -type f -name "$required" -print -quit | grep -q .; then
      echo "FAIL: macOS graphics bundle missing $required" >&2
      exit 1
    fi
  done
fi

echo "OK: $platform graphics bundle policy passed under $root"
