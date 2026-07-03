#!/usr/bin/env bash
# Remove Wawona from a physical iOS device (clears stale delta-install manifests).
set -euo pipefail

bundle="${WAWONA_BUNDLE_ID:-com.aspauldingcode.Wawona}"
device="${1:-${IOS_DEVICE_UDID:-STARDUST}}"

echo "Uninstalling ${bundle} from device ${device}..."
xcrun devicectl device uninstall app --device "$device" "$bundle"
echo "Done. Rebuild and Run from Xcode for a clean full install."
