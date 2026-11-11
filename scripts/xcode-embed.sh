#!/usr/bin/env bash
# Copy the slice's bundle tree (fonts, xkb, rootfs, catalog; on macOS the
# helper executables and graphics dylibs) into the built app, then make the
# app installable and self-contained.
set -euo pipefail

slice=$PLATFORM_NAME
if [ "$TARGET_NAME" = Wawona-iOS-ModeB ] && [ "$slice" = iphoneos ]; then
  slice=iphoneos-modeb
fi
src="$SRCROOT/.deps/$slice/bundle"
contents="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH"
app="$TARGET_BUILD_DIR/$WRAPPER_NAME"

# Store links become copies; relative links (macOS modeb-* aliases) stay links.
(cd "$src" && find . -type f -o -type l) | while IFS= read -r p; do
  rm -rf "${contents:?}/$p"
  mkdir -p "$(dirname "$contents/$p")"
  t=$(readlink "$src/$p" || true)
  case $t in
    '') cp "$src/$p" "$contents/$p" ;;
    /*) cp -RL "$t" "$contents/$p" ;;
    *) ln -s "$t" "$contents/$p" ;;
  esac
done
chmod -R u+w "$contents"

# App Store Connect treats an executable file as an unsigned code object.
if [ -d "$contents/wawona-rootfs" ]; then
  find "$contents/wawona-rootfs" -type f -exec chmod a-x {} +
fi

# Relay owns the CPU; no QEMU or UTM engine ships (docs/wwn-repo-dag.md).
hits=$(find "$app" \( -name wwn-qemu-run -o -iname 'qemu-system-*' -o -iname 'libqemu*' \
  -o -iname 'qemu-*.framework' -o -path '*/share/qemu/*' \))
if [ -n "$hits" ]; then
  printf 'QEMU/UTM artifacts are forbidden in Wawona bundles:\n%s\n' "$hits" >&2
  exit 1
fi

# The source Info.plist is shared. exportArchive and ASC reject iOS-only keys
# on the other platforms (wawona#138), and a watch build listing them is
# accepted and then silently discarded.
case $TARGET_NAME in
  Wawona-iOS | Wawona-iPadOS | Wawona-iOS-ModeB) ;;
  *)
    for key in LSRequiresIPhoneOS 'UISupportedInterfaceOrientations~ipad' 'MinimumOSVersion~ipad'; do
      /usr/libexec/PlistBuddy -c "Delete :$key" "$TARGET_BUILD_DIR/$INFOPLIST_PATH" 2>/dev/null || true
    done
    ;;
esac

case $PLATFORM_NAME in
  *simulator)
    # Store modes and com.apple.provenance make simctl install fail with EACCES.
    xattr -cr "$app"
    exit 0
    ;;
  macosx) ;;
  *) exit 0 ;;
esac

# macOS: the app and its helpers link Nix store dylibs by absolute path. Copy
# each into Frameworks, point the load commands at @rpath, and re-sign the
# helpers, since the app's CodeSign phase refuses an unsigned nested Mach-O.
# The app itself is signed by that phase, which runs after this one.
fw="$contents/Frameworks"
main="$contents/MacOS/$EXECUTABLE_NAME"
sign() {
  [ "${CODE_SIGNING_ALLOWED:-YES}" = YES ] && [ "$1" != "$main" ] || return 0
  codesign --force --timestamp=none --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$1"
}
machos() {
  find "$contents/MacOS" "$contents/Resources/bin" "$contents/Resources/lib"/* "$fw" -maxdepth 1 -type f |
    while IFS= read -r f; do
      file "$f" | grep -q Mach-O && echo "$f"
    done
}
store_deps() {
  otool -l "$1" | awk '/cmd LC_(LOAD|LOAD_WEAK|REEXPORT)_DYLIB$/ { getline; getline; if ($2 ~ /^\/nix\/store\//) print $2 }'
}

for d in $(machos); do
  case $(otool -D "$d" | sed -n 2p) in
    /nix/store/*) install_name_tool -id "@rpath/$(basename "$d")" "$d" ;;
  esac
done
added=1
while [ "$added" = 1 ]; do
  added=0
  for m in $(machos); do
    for d in $(store_deps "$m"); do
      b=$(basename "$d")
      [ -f "$fw/$b" ] && continue
      cp -L "$d" "$fw/$b"
      chmod 755 "$fw/$b"
      install_name_tool -id "@rpath/$b" "$fw/$b"
      added=1
    done
  done
done
for m in $(machos); do
  for d in $(store_deps "$m"); do
    install_name_tool -change "$d" "@rpath/$(basename "$d")" "$m"
  done
  for rp in $(otool -l "$m" | awk '/cmd LC_RPATH/ { getline; getline; print $2 }'); do
    case $rp in /nix/store/*) install_name_tool -delete_rpath "$rp" "$m" ;; esac
  done
  case $m in
    */Resources/*) rp=@executable_path/../../Frameworks ;;
    *) rp=@executable_path/../Frameworks ;;
  esac
  if otool -L "$m" | grep -q '@rpath/' && ! otool -l "$m" | grep -q "path $rp "; then
    install_name_tool -add_rpath "$rp" "$m"
  fi
  sign "$m"
done
