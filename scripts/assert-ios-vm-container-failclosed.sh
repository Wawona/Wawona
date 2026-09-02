#!/usr/bin/env bash
# Source-level fail-closed proof for iOS VM/container Start without embeds.
# Runtime e2e needs WAWONA_MOBILE_GUEST_DIR + WAWONA_MOBILE_VM_ENGINE_DIR.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VM="$ROOT/src/platform/macos/ui/Machines/WWNVirtualMachineRunner.m"
ENG="$ROOT/src/platform/macos/ui/Machines/WWNMobileVmEngine.m"
CAPS="$ROOT/Sources/WawonaModel/PlatformCapabilities.swift"

rg -q 'wawona-mobile-guest.*not embedded' "$VM"
rg -q 'QEMU-TCTI engine frameworks are not embedded' "$ENG"
rg -q 'oci-bundle' "$ENG"
rg -q 'WWN_CONTAINERS' "$CAPS"
rg -q 'isFlagEnabled\(flag\)' "$CAPS"

echo "OK: iOS VM/container fail-closed strings + WWN_CONTAINERS gate present"
echo "Runtime: rebuild sim with embeds, then WWN_VMS=1 WWN_CONTAINERS=1 agent-device open"
