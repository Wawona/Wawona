# Per-product Settings → Dependencies inventory (Okular-style components).
#
# Each package has: name, version, role (description), url, license (SPDX).
# Settings lists packages actually linked into THAT product. Never paste
# another platform's list. Canonical:
# docs/agent-rules/wawona-settings-dependencies.md
#
# Regenerate JSON snapshots (do not hand-edit):
#   ./scripts/regen-settings-deps.sh
#
# ANGLE / MoltenVK / iland versions must match the linked wwn-iland recipes.
# iland CalVer comes from sibling wwn-iland/VERSION (or versions.iland fallback).

let
  lib = builtins;

  # Prefer live sibling VERSION when regenerating from the org workspace.
  ilandVersionFromSibling =
    let
      path = ../../../wwn-iland/VERSION;
    in
    if builtins.pathExists path then
      builtins.replaceStrings [ "\n" "\r" " " ] [ "" "" "" ] (builtins.readFile path)
    else
      null;

  versions = {
    wayland = "1.23.0";
    xkbcommon = "1.7.0";
    lz4 = "1.10.0";
    zstd = "1.5.7";
    libffi = "3.5.2";
    sshpass = "1.10";
    waypipe = "0.11.0";
    libssh2 = "1.11.1";
    openssl = "3.4.1";
    pixman = "0.44.2";
    # Per-target ANGLE pins (wwn-iland angle recipes). Not a single "chromium".
    angleIos = "3100009"; # prebuilt iosUniversal (device + sim dylibs)
    angleMacos = "7258"; # nixpkgs.angle / GN source builds (tvOS/visionOS)
    angleAndroid = "chromium-7151";
    moltenvk = "1.4.1";
    swiftshader = "436722b";
    kosmickrisp = "26.1.3"; # Mesa driver tree used for KK
    weston = "14";
    niri = "25";
    zsh = "5.9";
    foot = "1.21";
    fuzzel = "1.11";
    openssh = "9.9p2";
    epollShim = "0.0.20240608";
    iland = if ilandVersionFromSibling != null then ilandVersionFromSibling else "26.9.9";
    neovim = "0.11";
    fastfetch = "2";
    kmscube = "mesa";
  };

  # Shared Okular-style metadata (url = source repo or project site).
  catalog = {
    libwayland = {
      url = "https://gitlab.freedesktop.org/wayland/wayland";
      license = "MIT";
      role = "Wayland protocol library";
    };
    xkbcommon = {
      url = "https://github.com/xkbcommon/libxkbcommon";
      license = "MIT";
      role = "Keyboard handling library";
    };
    LZ4 = {
      url = "https://github.com/lz4/lz4";
      license = "BSD-2-Clause";
      role = "Fast compression";
    };
    Zstd = {
      url = "https://github.com/facebook/zstd";
      license = "BSD-3-Clause OR GPL-2.0-only";
      role = "Zstandard compression";
    };
    libffi = {
      url = "https://github.com/libffi/libffi";
      license = "MIT";
      role = "Foreign function interface";
    };
    pixman = {
      url = "https://gitlab.freedesktop.org/pixman/pixman";
      license = "MIT";
      role = "Software 2D compositor";
    };
    Waypipe = {
      url = "https://gitlab.freedesktop.org/mstoeckl/waypipe";
      license = "MIT";
      role = "Remote Wayland display proxy";
    };
    libssh2 = {
      url = "https://github.com/libssh2/libssh2";
      license = "BSD-3-Clause";
      role = "In-process SSH (Apple mobile)";
    };
    OpenSSH = {
      url = "https://www.openssh.com";
      license = "SSH-OpenSSH";
      role = "Secure shell client";
    };
    sshpass = {
      url = "https://sourceforge.net/projects/sshpass";
      license = "GPL-2.0-or-later";
      role = "Non-interactive SSH password auth";
    };
    OpenSSL = {
      url = "https://www.openssl.org";
      license = "Apache-2.0";
      role = "Cryptography library";
    };
    "epoll-shim" = {
      url = "https://github.com/jiixyj/epoll-shim";
      license = "MIT";
      role = "epoll compatibility layer";
    };
    ANGLE = {
      url = "https://angleproject.org";
      license = "BSD-3-Clause";
      role = "OpenGL ES on Metal";
    };
    MoltenVK = {
      url = "https://github.com/KhronosGroup/MoltenVK";
      license = "Apache-2.0";
      role = "Vulkan on Metal";
    };
    KosmicKrisp = {
      url = "https://gitlab.freedesktop.org/mesa/mesa";
      license = "MIT";
      role = "Vulkan on Metal (Apple Silicon)";
    };
    SwiftShader = {
      url = "https://github.com/google/swiftshader";
      license = "Apache-2.0";
      role = "CPU Vulkan ICD";
    };
    iland = {
      url = "https://github.com/Wawona/wwn-iland";
      license = "MIT";
      role = "Userspace DRM/KMS/GBM (Mode A)";
    };
    Weston = {
      url = "https://gitlab.freedesktop.org/wayland/weston";
      license = "MIT";
      role = "Bundled nested compositor";
    };
    Niri = {
      url = "https://github.com/YaLTeR/niri";
      license = "GPL-3.0-or-later";
      role = "Bundled nested compositor";
    };
    zsh = {
      url = "https://www.zsh.org";
      license = "Zsh";
      role = "Local shell";
    };
    Foot = {
      url = "https://codeberg.org/dnkl/foot";
      license = "MIT";
      role = "Wayland terminal";
    };
    Fuzzel = {
      url = "https://codeberg.org/dnkl/fuzzel";
      license = "MIT";
      role = "Wayland launcher";
    };
    kmscube = {
      url = "https://gitlab.freedesktop.org/mesa/kmscube";
      license = "MIT";
      role = "GLES/Vulkan KMS demo";
    };
    neovim = {
      url = "https://neovim.io";
      license = "Apache-2.0";
      role = "Bundled editor";
    };
    fastfetch = {
      url = "https://github.com/fastfetch-cli/fastfetch";
      license = "MIT";
      role = "System info client";
    };
  };

  pkg =
    name: version: roleOverride:
    let
      c = catalog.${name};
    in
    {
      inherit name version;
      role = if roleOverride == null then c.role else roleOverride;
      url = c.url;
      license = c.license;
    };

  pkgDef = name: version: pkg name version null;

  substrate = v: [
    (pkgDef "libwayland" v.wayland)
    (pkgDef "xkbcommon" v.xkbcommon)
    (pkgDef "LZ4" v.lz4)
    (pkgDef "Zstd" v.zstd)
    (pkgDef "libffi" v.libffi)
    (pkgDef "pixman" v.pixman)
  ];

  inventories = rec {
    ios = v: (substrate v) ++ [
      (pkgDef "Waypipe" v.waypipe)
      (pkg "libssh2" v.libssh2 "In-process SSH (Apple mobile)")
      (pkgDef "epoll-shim" v.epollShim)
      (pkg "ANGLE" v.angleIos "OpenGL ES on Metal")
      (pkgDef "MoltenVK" v.moltenvk)
      (pkg "iland" v.iland "Userspace DRM/KMS/GBM (Mode A)")
      (pkgDef "Weston" v.weston)
      (pkgDef "Niri" v.niri)
      (pkg "zsh" v.zsh "In-process local shell")
      (pkgDef "Foot" v.foot)
      (pkgDef "Fuzzel" v.fuzzel)
    ];
    ipados = ios;
    macos = v: (substrate v) ++ [
      (pkgDef "Waypipe" v.waypipe)
      (pkg "OpenSSH" v.openssh "Secure shell client")
      (pkgDef "sshpass" v.sshpass)
      (pkg "ANGLE" v.angleMacos "OpenGL ES on Metal")
      (pkgDef "MoltenVK" v.moltenvk)
      (pkgDef "KosmicKrisp" v.kosmickrisp)
      (pkgDef "SwiftShader" v.swiftshader)
      (pkg "iland" v.iland "Userspace DRM/KMS/GBM (Mode A)")
      (pkgDef "Weston" v.weston)
      (pkgDef "Niri" v.niri)
      (pkg "zsh" v.zsh "Bundled local shell")
      (pkgDef "Foot" v.foot)
      (pkgDef "Fuzzel" v.fuzzel)
    ];
    tvos = v: (substrate v) ++ [
      (pkgDef "Waypipe" v.waypipe)
      (pkg "libssh2" v.libssh2 "In-process SSH (Apple mobile)")
      (pkgDef "epoll-shim" v.epollShim)
      (pkg "ANGLE" v.angleMacos "OpenGL ES on Metal")
      (pkgDef "MoltenVK" v.moltenvk)
      (pkg "iland" v.iland "Userspace DRM/KMS/GBM (Mode A)")
      (pkgDef "Weston" v.weston)
      (pkgDef "Niri" v.niri)
      (pkg "zsh" v.zsh "In-process local shell")
      (pkgDef "Foot" v.foot)
    ];
    watchos = v: (substrate v) ++ [
      (pkgDef "Waypipe" v.waypipe)
      (pkg "libssh2" v.libssh2 "In-process SSH (Apple mobile)")
      (pkgDef "epoll-shim" v.epollShim)
      (pkg "iland" v.iland "SHM clients; SpriteKit present (GL/VK blocked)")
      (pkgDef "Weston" v.weston)
      (pkgDef "Niri" v.niri)
      (pkg "zsh" v.zsh "In-process local shell")
      (pkgDef "Foot" v.foot)
    ];
    visionos = ios;
    android = v: (substrate v) ++ [
      (pkgDef "Waypipe" v.waypipe)
      (pkg "OpenSSH" v.openssh "SSH client (portable jniLibs)")
      (pkgDef "OpenSSL" v.openssl)
      (pkg "ANGLE" v.angleAndroid "OpenGL ES on Vulkan/EGL")
      (pkgDef "SwiftShader" v.swiftshader)
      (pkg "iland" v.iland "Userspace DRM/KMS/GBM over AHardwareBuffer")
      (pkgDef "Weston" v.weston)
      (pkgDef "Niri" v.niri)
      (pkg "zsh" v.zsh "In-process local shell")
    ];
    linux = v: (substrate v) ++ [
      (pkgDef "Waypipe" v.waypipe)
      (pkg "OpenSSH" v.openssh "Host SSH client")
      (pkgDef "Weston" v.weston)
      (pkgDef "Niri" v.niri)
      (pkgDef "Foot" v.foot)
      (pkg "zsh" v.zsh "Bundled local shell")
      (pkgDef "kmscube" v.kmscube)
      (pkgDef "neovim" v.neovim)
      (pkgDef "fastfetch" v.fastfetch)
    ];
  };

  toJSON = packages: builtins.toJSON { packages = packages; };

  inventoryJSON = target: toJSON (inventories.${target} versions);

in
{
  inherit versions catalog inventories toJSON inventoryJSON pkg;
  # Convenience for regen: all targets → JSON strings.
  allJSON = builtins.mapAttrs (name: _: inventoryJSON name) inventories;
}
