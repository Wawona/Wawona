{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  simulator ? false,
  iosToolchain,
}:

{
  buildForWatchOS =
    name: entry:
    if name == "libwayland" then
      pkgs.callPackage ../libs/libwayland/watchos.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else if name == "expat" then
      pkgs.callPackage ../libs/expat/watchos.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else if name == "libffi" then
      pkgs.callPackage ../libs/libffi/watchos.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else if name == "libxml2" then
      pkgs.callPackage ../libs/libxml2/watchos.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else if name == "waypipe" then
      pkgs.callPackage ../libs/waypipe/watchos.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else if name == "zlib" then
      pkgs.callPackage ../libs/zlib/watchos.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else if name == "zstd" then
      pkgs.callPackage ../libs/zstd/watchos.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else if name == "lz4" then
      pkgs.callPackage ../libs/lz4/watchos.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else if name == "ffmpeg" then
      pkgs.callPackage ../libs/ffmpeg/watchos.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else if name == "spirv-tools" then
      pkgs.callPackage ../libs/spirv-tools/watchos.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else if name == "xkbcommon" then
      pkgs.callPackage ../libs/xkbcommon/watchos.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else if name == "libssh2" then
      pkgs.callPackage ../libs/libssh2/watchos.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else if name == "mbedtls" then
      pkgs.callPackage ../libs/mbedtls/watchos.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else if name == "openssl" then
      pkgs.callPackage ../libs/openssl/watchos.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else if name == "openssh" then
      pkgs.callPackage ../libs/openssh/watchos.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else if name == "sshpass" then
      pkgs.callPackage ../libs/sshpass/watchos.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else if name == "epoll-shim" then
      pkgs.callPackage ../libs/epoll-shim/watchos.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else if name == "pixman" then
      pkgs.callPackage ../libs/pixman/watchos.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else if name == "weston" then
      pkgs.callPackage ../clients/weston/watchos.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else if name == "weston-simple-shm" then
      pkgs.callPackage ../libs/weston-simple-shm/watchos.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else if name == "foot" then
      pkgs.callPackage ../clients/foot/watchos.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else
      # Explicitly retained watchOS policy: when a watch module is absent,
      # use the iOS recipe as a compatibility fallback.
      buildModule.buildForIOS name entry;
}
