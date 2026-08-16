# Freedesktop applications catalog for nested-niri fuzzel (Mod+D).
# Produces share/applications/*.desktop + share/icons/hicolor/{48x48,64x64}/apps
# so fuzzel's XDG scan finds launchable bundled clients with icons.
#
# Wire into macos.nix / xcodegen.nix (install under both App/share and
# Contents/Resources/share), then set XDG_DATA_DIRS=<bundle>/share at
# niri/fuzzel launch (WWNEnsureFuzzelXdgEnv). Prefer the share root that
# contains applications/. See WWNWawonaShareRoot.
# See https://github.com/Wawona/Wawona/issues/78

{
  pkgs,
  lib,
  wawonaSrc ? null,
}:

let
  westonFetch =
    name: sha256:
    pkgs.fetchurl {
      url = "https://gitlab.freedesktop.org/wayland/weston/-/raw/13.0.0/data/${name}";
      inherit sha256;
    };

  terminalPng = westonFetch "terminal.png" "sha256-ZxUcCQYM4kTNof+V5q2VAgKkR51S+YFiAOjrzUGqU7o=";
  iconWindowPng = westonFetch "icon_window.png" "sha256-RrzYR/znpkBhJPDCkinwI5or9NiIgR3FMMF66f+QZ8I=";
  iconFlowerPng = westonFetch "icon_flower.png" "sha256-tK80FRME3we1jXSRqJ3JOWdLQFlEH90w/SA9EdLaa/0=";
  iconEditorPng = westonFetch "icon_editor.png" "sha256-mKbxqBjd6gqIrA96mPPCbaLUDUAEvOFAC2QLMADTB7I=";
  iconTerminalPng = westonFetch "icon_terminal.png" "sha256-ry8nAsc20wwYxD3lUVMkqUQMGndXnvp04MBht3IQ1W4=";
  iconSmokePng = westonFetch "icon_ivi_smoke.png" "sha256-j+Kz9RKyAytOHp4KgRva1kF3HL3f+Iqp5ASuLDvwNI4=";
  iconClickdotPng = westonFetch "icon_ivi_clickdot.png" "sha256-EPUNRmoTN60UqyBWQDD2b52vYSucSoJ5MipQQIpiOBk=";

  waylandPng =
    if wawonaSrc != null then
      wawonaSrc + "/src/resources/Wawona.icon/Assets/wayland.png"
    else
      iconWindowPng;

  # id == Exec basename == Icon name. Keep Exec in sync with
  # wawona_dispatch_can_handle() / bundled PATH binaries.
  apps = [
    {
      id = "weston-terminal";
      name = "Weston Terminal";
      comment = "In-process Wayland terminal (zsh)";
      categories = "System;TerminalEmulator;";
      icon = "weston-terminal";
    }
    {
      id = "foot";
      name = "Foot Terminal";
      comment = "Fast Wayland terminal emulator";
      categories = "System;TerminalEmulator;";
      icon = "foot";
    }
    {
      id = "nvim";
      name = "Neovim";
      comment = "Hyperextensible Vim-based text editor";
      categories = "Utility;TextEditor;";
      icon = "nvim";
    }
    {
      id = "fastfetch";
      name = "Fastfetch";
      comment = "System information tool";
      categories = "System;Utility;";
      icon = "fastfetch";
    }
    {
      id = "phoon";
      name = "Phoon";
      comment = "ASCII moon-phase display";
      categories = "Utility;";
      icon = "phoon";
    }
    {
      id = "weston-simple-shm";
      name = "Weston Simple SHM";
      comment = "Wawona in-process Wayland client";
      categories = "Utility;";
      icon = "weston-simple-shm";
    }
    {
      id = "weston-flower";
      name = "Weston Flower";
      comment = "Wawona in-process Wayland client";
      categories = "Utility;";
      icon = "weston-flower";
    }
    {
      id = "weston-smoke";
      name = "Weston Smoke";
      comment = "Wawona in-process Wayland client";
      categories = "Utility;";
      icon = "weston-smoke";
    }
    {
      id = "weston-clickdot";
      name = "Weston Clickdot";
      comment = "Wawona in-process Wayland client";
      categories = "Utility;";
      icon = "weston-clickdot";
    }
    {
      id = "weston-eventdemo";
      name = "Weston Event Demo";
      comment = "Wawona in-process Wayland client";
      categories = "Utility;";
      icon = "weston-eventdemo";
    }
    {
      id = "weston-resizor";
      name = "Weston Resizor";
      comment = "Wawona in-process Wayland client";
      categories = "Utility;";
      icon = "weston-resizor";
    }
    {
      id = "weston-cliptest";
      name = "Weston Clip Test";
      comment = "Wawona in-process Wayland client";
      categories = "Utility;";
      icon = "weston-cliptest";
    }
    {
      id = "weston-transformed";
      name = "Weston Transformed";
      comment = "Wawona in-process Wayland client";
      categories = "Utility;";
      icon = "weston-transformed";
    }
    {
      id = "weston-stacking";
      name = "Weston Stacking";
      comment = "Wawona in-process Wayland client";
      categories = "Utility;";
      icon = "weston-stacking";
    }
    {
      id = "weston-dnd";
      name = "Weston Drag & Drop";
      comment = "Wawona in-process Wayland client";
      categories = "Utility;";
      icon = "weston-dnd";
    }
    {
      id = "weston-image";
      name = "Weston Image";
      comment = "Wawona in-process Wayland client";
      categories = "Utility;";
      icon = "weston-image";
    }
    {
      id = "weston-scaler";
      name = "Weston Scaler";
      comment = "Wawona in-process Wayland client";
      categories = "Utility;";
      icon = "weston-scaler";
    }
    {
      id = "weston-editor";
      name = "Weston Editor";
      comment = "Wawona in-process Wayland client";
      categories = "Utility;";
      icon = "weston-editor";
    }
    {
      id = "weston-constraints";
      name = "Weston Constraints";
      comment = "Wawona in-process Wayland client";
      categories = "Utility;";
      icon = "weston-constraints";
    }
  ];

  # Map icon id -> source PNG path for install phase.
  iconSources = {
    weston-terminal = iconTerminalPng;
    foot = terminalPng;
    nvim = iconEditorPng;
    fastfetch = waylandPng;
    phoon = iconWindowPng;
    weston-simple-shm = iconWindowPng;
    weston-flower = iconFlowerPng;
    weston-smoke = iconSmokePng;
    weston-clickdot = iconClickdotPng;
    weston-eventdemo = iconWindowPng;
    weston-resizor = iconWindowPng;
    weston-cliptest = iconWindowPng;
    weston-transformed = iconWindowPng;
    weston-stacking = iconWindowPng;
    weston-dnd = iconWindowPng;
    weston-image = iconWindowPng;
    weston-scaler = iconWindowPng;
    weston-editor = iconEditorPng;
    weston-constraints = iconWindowPng;
  };

  writeDesktop =
    app:
    pkgs.writeTextDir "share/applications/${app.id}.desktop" ''
      [Desktop Entry]
      Type=Application
      Name=${app.name}
      Comment=${app.comment}
      Exec=${app.id}
      Icon=${app.icon}
      Terminal=false
      Categories=${app.categories}
      X-Wawona-InProcess=true
    '';

  desktopEntries = pkgs.symlinkJoin {
    name = "wawona-desktop-entries";
    paths = map writeDesktop apps;
  };
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "wawona-applications-catalog";
  version = "1.0";

  dontUnpack = true;
  nativeBuildInputs = [ pkgs.imagemagick ];

  buildPhase = ''
    set -euo pipefail
    mkdir -p share/applications
    mkdir -p share/icons/hicolor/48x48/apps
    mkdir -p share/icons/hicolor/64x64/apps
    cp -L "${pkgs.hicolor-icon-theme}/share/icons/hicolor/index.theme" \
      share/icons/hicolor/index.theme
    cp -L ${desktopEntries}/share/applications/*.desktop share/applications/

    install_icon() {
      local id="$1"
      local src="$2"
      if [ ! -f "$src" ]; then
        echo "warning: missing icon source for $id at $src" >&2
        src="${iconWindowPng}"
      fi
      ${pkgs.imagemagick}/bin/convert "$src" -resize 48x48 \
        "share/icons/hicolor/48x48/apps/$id.png"
      ${pkgs.imagemagick}/bin/convert "$src" -resize 64x64 \
        "share/icons/hicolor/64x64/apps/$id.png"
    }

    ${lib.concatMapStrings (app: ''
      install_icon "${app.id}" "${iconSources.${app.id}}"
    '') apps}
  '';

  installPhase = ''
    mkdir -p $out
    cp -R share $out/
  '';

  meta = with lib; {
    description = "Freedesktop .desktop + hicolor icons for nested-niri fuzzel";
    platforms = platforms.all;
  };
}
