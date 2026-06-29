{ lib, pkgs }:
{
  buildFn,
  toolchains,
  simulator ? false,
  # mobile: iOS/iPadOS (full stack). tv: tvOS. watch: watchOS (no waypipe). vision: visionOS.
  variant ? "mobile",
  extras ? {},
}:
let
  inherit simulator;
  mobileToytoolkitDeps = import ./mobile-toytoolkit-deps.nix;
  networkStack =
    {
      zstd = buildFn "zstd" { inherit simulator; };
      lz4 = buildFn "lz4" { inherit simulator; };
      zlib = buildFn "zlib" { inherit simulator; };
      libssh2 = buildFn "libssh2" { inherit simulator; };
      mbedtls = buildFn "mbedtls" { inherit simulator; };
      openssl = buildFn "openssl" { inherit simulator; };
      ffmpeg = buildFn "ffmpeg" { inherit simulator; };
      foot = buildFn "foot" { inherit simulator; };
      sshpass = buildFn "sshpass" { inherit simulator; };
    }
    // lib.optionalAttrs (variant == "mobile" || variant == "tv") {
      waypipe = buildFn "waypipe" { inherit simulator; };
    };
  base =
    {
      xkbcommon = buildFn "xkbcommon" { inherit simulator; };
      libffi = buildFn "libffi" { inherit simulator; };
      libwayland = buildFn "libwayland" { inherit simulator; };
      epoll-shim = buildFn "epoll-shim" { inherit simulator; };
      pixman = buildFn "pixman" { inherit simulator; };
      weston = buildFn "weston" { inherit simulator; };
      weston-simple-shm = buildFn "weston-simple-shm" { inherit simulator; };
  # Unified archive: Settings can switch Wayland/Pixman vs iland DRM/GL at runtime.
      "weston-compositor" = buildFn "weston-compositor" { inherit simulator; enableIlandDrm = true; };
    }
    // lib.optionalAttrs (variant == "mobile" || variant == "tv" || variant == "watch") networkStack
    // lib.optionalAttrs (variant == "mobile" || variant == "vision") {
      iland = buildFn "iland" { inherit simulator; };
      angle = buildFn "angle" { inherit simulator; };
      kmscube = buildFn "kmscube" { inherit simulator; };
      "iland-gl-clients" = buildFn "kmscube" { inherit simulator; };
    }
    // lib.optionalAttrs
      (variant == "mobile" || variant == "tv" || variant == "watch" || variant == "vision")
      {
        # In-process zsh stack across the Apple family. coreutils is size-gated
        # off watchOS in rust-backend-c2n.nix, but the shell itself ships
        # everywhere (constrained UX on watch/tv is applied at the view layer).
        "wawona-pty" = buildFn "wawona-pty" { inherit simulator; };
        "wawona-rootfs" = buildFn "wawona-rootfs" { inherit simulator; };
        zsh = buildFn "zsh" { inherit simulator; };
      }
    // lib.optionalAttrs (variant == "mobile") {
        fastfetch = buildFn "fastfetch" { inherit simulator; };
        neovim = buildFn "neovim" { inherit simulator; };
        "neovim-rootfs" = buildFn "neovim-rootfs" { inherit simulator; };
      }
    // lib.optionalAttrs (variant == "vision") {
      libssh2 = buildFn "libssh2" { inherit simulator; };
      openssl = buildFn "openssl" { inherit simulator; };
    };
in
base
// (mobileToytoolkitDeps { inherit buildFn simulator; })
// extras
