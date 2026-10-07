#!/usr/bin/env bash
# Build placeholder Mode B metadata debs. Real Mach-O payloads come from the
# recorded Procursus upstreams when the iOS cross toolchain is present.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/out"
rm -rf "$OUT"
mkdir -p "$OUT"
for pkg in wawona-uikit-tools wawona-launch-tools wawona-defaults wawona-security-tools; do
  stage="$OUT/stage-$pkg"
  mkdir -p "$stage/DEBIAN" "$stage/usr/share/doc/$pkg"
  cp "$ROOT/debian/$pkg/control" "$stage/DEBIAN/control"
  cp "$ROOT/UPSTREAMS.txt" "$stage/usr/share/doc/$pkg/"
  if [[ "$pkg" == "wawona-security-tools" ]]; then
    printf '%s\n' "ldid is AGPL-3.0. Source: https://github.com/ProcursusTeam/ldid" \
      > "$stage/usr/share/doc/$pkg/copyright"
  fi
  (cd "$OUT" && dpkg-deb --build "stage-$pkg" "${pkg}_26.10.6_iphoneos-arm64.deb")
done
echo "wrote $OUT"
ls -l "$OUT"/*.deb
