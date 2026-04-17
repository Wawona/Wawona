{
  lib,
  pkgs,
  common,
  buildModule,
  ...
}:

{
  # Linux-native dependency resolver scaffold.
  # Most linux builds should resolve directly from nixpkgs or dedicated
  # dependency recipes as they are introduced.
  buildForLinux =
    name: entry:
    if name == "waypipe" then pkgs.waypipe
    else if name == "libwayland" then pkgs.wayland
    else if name == "zstd" then pkgs.zstd
    else if name == "lz4" then pkgs.lz4
    else if name == "xkbcommon" then pkgs.libxkbcommon
    else if name == "openssl" then pkgs.openssl
    else if name == "libssh2" then pkgs.libssh2
    else if name == "mbedtls" then pkgs.mbedtls
    else if name == "openssh" then pkgs.openssh
    else if name == "sshpass" then pkgs.sshpass
    else if name == "libffi" then pkgs.libffi
    else if name == "libxml2" then pkgs.libxml2
    else if name == "expat" then pkgs.expat
    else if name == "pixman" then pkgs.pixman
    else if name == "ffmpeg" then pkgs.ffmpeg
    else if name == "spirv-tools" then pkgs.spirv-tools
    else if name == "epoll-shim" then pkgs.emptyDirectory
    else if name == "weston-simple-shm" then pkgs.callPackage ../libs/weston-simple-shm/linux.nix {}
    else if name == "freetype" then pkgs.freetype
    else if name == "fontconfig" then pkgs.fontconfig
    else if name == "fcft" then (if pkgs ? fcft then pkgs.fcft else pkgs.emptyDirectory)
    else if name == "tllist" then (if pkgs ? tllist then pkgs.tllist else pkgs.emptyDirectory)
    else if name == "utf8proc" then pkgs.utf8proc
    else if name == "weston" then pkgs.weston
    else if name == "foot" then pkgs.foot
    else
      throw "Unknown linux dependency '${name}'. Add it to dependencies/platforms/linux.nix.";
}
