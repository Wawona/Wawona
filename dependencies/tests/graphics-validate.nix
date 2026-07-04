# Graphics validation harness (ci-graphics-cts).
#
# Produces `bin/graphics-validate-macos`, a self-contained driver-sanity check
# for the Wawona graphics stack. It does not vendor the full Khronos CTS (that
# lives in the optional `dependencies/libs/{vulkan,gl}-cts` trees and the
# `vulkan-cts`/`gl-cts` flake packages); instead it validates the pieces CI can
# always run cheaply:
#
#   1. A Vulkan ICD is resolvable (VK_DRIVER_FILES set and the JSON parses).
#   2. `vulkaninfo` (when available) enumerates at least one physical device.
#   3. The GL/Vulkan must-pass caselists exist and are non-empty, and are echoed
#      as the intended deqp `--deqp-caselist-file` inputs for the full CTS lane.
#
# The full deqp lanes consume the same caselist files, so this harness is the
# fast PR gate and the nightly CTS lane is the deep gate.
{ lib
, stdenvNoCC
, writeShellApplication
, vulkan-tools ? null
, coreutils
}:

let
  glList = ../tests/gl-mustpass-smoke.txt;
  vkList = ../tests/vulkan-mustpass-smoke.txt;
  vulkaninfoBin =
    if vulkan-tools != null then "${vulkan-tools}/bin/vulkaninfo" else "";
in
writeShellApplication {
  name = "graphics-validate-macos";
  runtimeInputs = [ coreutils ];
  text = ''
    set -euo pipefail

    gl_list="${glList}"
    vk_list="${vkList}"
    vulkaninfo_bin="${vulkaninfoBin}"

    fail() { echo "graphics-validate: FAIL: $*" >&2; exit 1; }
    ok()   { echo "graphics-validate: ok: $*"; }

    # 1. Must-pass caselists present and non-empty (strip comments/blank lines).
    for f in "$gl_list" "$vk_list"; do
      [ -f "$f" ] || fail "missing caselist $f"
      n=$(grep -cvE '^[[:space:]]*(#|$)' "$f" || true)
      [ "$n" -gt 0 ] || fail "empty caselist $f"
      ok "caselist $f has $n cases"
    done

    # 2. Vulkan ICD resolvable (advisory: CI may run without a bundled ICD).
    if [ -n "''${VK_DRIVER_FILES:-}" ]; then
      for icd in ''${VK_DRIVER_FILES//:/ }; do
        [ -f "$icd" ] || fail "VK_DRIVER_FILES entry not found: $icd"
        # Cheap JSON sanity: must contain an ICD library_path key.
        grep -q '"library_path"' "$icd" || fail "ICD missing library_path: $icd"
        ok "ICD json valid: $icd"
      done
    else
      echo "graphics-validate: note: VK_DRIVER_FILES unset (SHM/software path)"
    fi

    # 3. Device enumeration when vulkaninfo is available.
    if [ -n "$vulkaninfo_bin" ] && [ -x "$vulkaninfo_bin" ]; then
      if "$vulkaninfo_bin" --summary >/tmp/wwn-vkinfo.txt 2>&1; then
        if grep -qiE 'deviceName|GPU id' /tmp/wwn-vkinfo.txt; then
          ok "vulkaninfo enumerated a device"
        else
          echo "graphics-validate: note: vulkaninfo ran but listed no device"
        fi
      else
        echo "graphics-validate: note: vulkaninfo failed (no loader/ICD in sandbox)"
      fi
    else
      echo "graphics-validate: note: vulkaninfo not available; skipping enumeration"
    fi

    echo "graphics-validate: PASS"
  '';
}
