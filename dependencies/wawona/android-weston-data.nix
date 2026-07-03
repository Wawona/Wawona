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
    tar xf ${westonSrc} \
      --wildcards 'weston-13.0.0/data/*.png' \
      --strip-components=2 \
      -C app/src/main/assets/weston
    chmod -R u+w app/src/main/assets/weston
    if [ ! -f app/src/main/assets/weston/icon_window.png ]; then
      echo "ERROR: Weston frame assets missing from APK assets/weston"
      exit 1
    fi
    echo "Bundled $(ls app/src/main/assets/weston/*.png | wc -l) Weston PNG assets for toytoolkit CSD"
  '';
}
