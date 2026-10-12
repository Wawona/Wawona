{ lib, pkgs }:
{
  buildFn,
  toolchains,
  simulator ? false,
  # mobile: iOS/iPadOS. tv: tvOS. watch: watchOS. vision: visionOS.
  # All Apple mobile variants: libssh2 + waypipe remote (never OpenSSH).
  variant ? "mobile",
  extras ? {},
}:
let
  inherit simulator;
  # Product keep-set: shell CLIs + remote + Relay wasm. No weston/niri/foot/
  # cubes/phoon/fuzzel (optional-software → repo.wawona.io deb/wasm).
  networkStack =
    {
      zstd = buildFn "zstd" { inherit simulator; };
      lz4 = buildFn "lz4" { inherit simulator; };
      zlib = buildFn "zlib" { inherit simulator; };
      libssh2 = buildFn "libssh2" { inherit simulator; };
      "ssh-cli" = buildFn "ssh-cli" { inherit simulator; };
      mbedtls = buildFn "mbedtls" { inherit simulator; };
      openssl = buildFn "openssl" { inherit simulator; };
      sshpass = buildFn "sshpass" { inherit simulator; };
    }
    // lib.optionalAttrs (
      variant == "mobile" || variant == "tv" || variant == "watch" || variant == "vision"
    ) {
      waypipe = buildFn "waypipe" { inherit simulator; };
    };
  # Store Apple-mobile + tv/watch: no ANGLE/MoltenVK/cubes (no in-app GLES clients).
  # Host present uses Smithay + Metal/SpriteKit; iland userland only where needed.
  # visionOS keeps iland for multi-window present (no GL client archives).
  allowIlandPresent = variant == "mobile" || variant == "vision" || variant == "tv";
  base =
    {
      xkbcommon = buildFn "xkbcommon" { inherit simulator; };
      libffi = buildFn "libffi" { inherit simulator; };
      libwayland = buildFn "libwayland" { inherit simulator; };
      epoll-shim = buildFn "epoll-shim" { inherit simulator; };
      pixman = buildFn "pixman" { inherit simulator; };
    }
    // lib.optionalAttrs (
      variant == "mobile" || variant == "tv" || variant == "watch" || variant == "vision"
    ) networkStack
    // lib.optionalAttrs allowIlandPresent {
      # Mode A present path (IOSurface/Metal). No ANGLE, no cube clients.
      iland = buildFn "iland" { inherit simulator; };
    }
    // lib.optionalAttrs
      (variant == "mobile" || variant == "tv" || variant == "watch" || variant == "vision")
      {
        "wawona-pty" = buildFn "wawona-pty" { inherit simulator; };
        "wawona-rootfs" = buildFn "wawona-rootfs" { inherit simulator; };
        zsh = buildFn "zsh" { inherit simulator; };
      }
    // lib.optionalAttrs (variant == "mobile" || variant == "tv" || variant == "watch" || variant == "vision") {
        "wawona-wasm" = buildFn "wawona-wasm" { inherit simulator; };
        "wawona-relay" = buildFn "wawona-relay" { inherit simulator; };
      }
    // lib.optionalAttrs (
      variant == "mobile" || variant == "vision" || variant == "tv" || variant == "watch"
    ) {
        fastfetch = buildFn "fastfetch" { inherit simulator; };
      };
in
# No weston toytoolkit (cairo/pango) closure: optional-software unbundled.
base // extras
