# Weston toytoolkit PNG assets for Android (window frame decorations, panel icons).
#
# Without WESTON_DATA_DIR + these files, in-process CSD clients (weston-terminal,
# cliptest, flower, …) SIGSEGV in window_frame_create when frame_create cannot
# load sign_close.png / icon_window.png (iOS bundles the same tree under share/weston).
{
  lib,
  pkgs,
}:
let
  westonSrc = pkgs.fetchurl {
    url = "https://gitlab.freedesktop.org/wayland/weston/-/releases/13.0.0/downloads/weston-13.0.0.tar.xz";
    sha256 = "sha256-Uv8dSqI5Si5BbIWjOLYnzpf6cdQ+t2L9Sq8UXTb8eVo=";
  };
in
{
  preBuildFragment = ''
    mkdir -p app/src/main/assets/weston
    # Extract the whole weston data/ directory rather than a *.png glob: macOS
    # ships bsdtar (libarchive), which does not support GNU tar's --wildcards
    # flag, so a glob-in-extract silently matches nothing and the APK ends up
    # without the CSD frame assets. Extracting the directory member is portable
    # across both GNU tar and bsdtar; we then drop the few non-PNG data files.
    tar xf ${westonSrc} \
      --strip-components=2 \
      -C app/src/main/assets/weston \
      weston-13.0.0/data
    find app/src/main/assets/weston -type f ! -name '*.png' -delete 2>/dev/null || true
    chmod -R u+w app/src/main/assets/weston
    if [ ! -f app/src/main/assets/weston/icon_window.png ]; then
      echo "ERROR: Weston frame assets missing from APK assets/weston"
      exit 1
    fi
    echo "Bundled $(ls app/src/main/assets/weston/*.png | wc -l) Weston PNG assets for toytoolkit CSD"
  '';
}
