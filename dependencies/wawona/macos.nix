# The macOS app: the committed project's Wawona-macOS scheme over the macosx
# slice, the build Xcode runs. Signed ad hoc without entitlements; iCloud
# needs a team profile, which a Release build from Xcode uses.
{
  lib,
  pkgs,
  wawonaSrc,
  wawonaVersion ? null,
  xcodeProject,
  applePath,
}:
(pkgs.callPackage ./ios.nix {
  inherit wawonaSrc wawonaVersion xcodeProject applePath;
  simulator = false;
  adHoc = true;
  xcodeTarget = "Wawona-macOS";
  nativeSdk = "macosx";
  platformName = "macOS";
}).overrideAttrs (old: {
  name = "wawona-macos";
  # Fixup would rewrite files inside the sealed bundle.
  dontStrip = true;
  dontPatchShebangs = true;
  postFixup = (old.postFixup or "") + ''
    app=$out/Applications/Wawona.app
    mkdir -p $out/Applications $out/bin
    mv $out/Wawona.app $app
    ln -s $app/Contents/MacOS/Wawona $out/bin/Wawona
    ln -s $app/Contents/MacOS/Wawona $out/bin/wawona-macos
    ln -s $app/Contents/Resources/share $out/share
    ln -s $app/Contents/Resources/lib $out/lib
    for f in Resources/share/weston/background.png Resources/share/weston/pattern.png \
      Resources/share/fonts/truetype/DejaVuSans.ttf Resources/share/fonts/truetype/DejaVuSansMNerdFontMono-Regular.ttf \
      Resources/bin/weston Resources/bin/weston-terminal Resources/bin/weston-simple-shm Resources/bin/foot \
      Library/Wawona/iland/libwayland-mac.dylib Library/Wawona/wwn-iowatchdog Library/Wawona/wwn-iowatchdog-claim-install \
      Library/Wawona/lib/libwwn_watchdogd_hook.dylib \
      Resources/lib/libweston-13/drm-backend.so Resources/lib/libweston-13/gl-renderer.so; do
      [ -e "$app/Contents/$f" ] || { echo "Wawona.app is missing Contents/$f" >&2; exit 1; }
    done
    /usr/bin/codesign --verify --strict "$app"
  '';
})
