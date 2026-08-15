{ lib, pkgs }:
{
  buildFn,
  toolchains,
  simulator ? false,
  # mobile: iOS/iPadOS (full stack). tv: tvOS. watch: watchOS. vision: visionOS.
  # All Apple mobile variants: libssh2 + waypipe remote (never OpenSSH).
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
      # In-process OpenSSH-shaped CLI (ssh_main / ssh_keygen_main / scp_main).
      # Never OpenSSH / libssh-inprocess.a on Apple mobile.
      "ssh-cli" = buildFn "ssh-cli" { inherit simulator; };
      mbedtls = buildFn "mbedtls" { inherit simulator; };
      openssl = buildFn "openssl" { inherit simulator; };
      ffmpeg = buildFn "ffmpeg" { inherit simulator; };
      foot = buildFn "foot" { inherit simulator; };
      sshpass = buildFn "sshpass" { inherit simulator; };
    }
    # Apple mobile family: libssh2 + ssh-cli only (never OpenSSH).
    # OpenSSH ships on macOS via macos.nix; Android uses OpenSSH portable.
    # waypipe on every Apple mobile variant that advertises Remote in the
    # platform-targets matrix (phone/tv/watch/vision).
    // lib.optionalAttrs (
      variant == "mobile" || variant == "tv" || variant == "watch" || variant == "vision"
    ) {
      waypipe = buildFn "waypipe" { inherit simulator; };
    };
  # tv/watch: shm/pixman only — no ANGLE/Vulkan (platform-targets matrix).
  allowGpu = variant == "mobile" || variant == "vision";
  base =
    {
      xkbcommon = buildFn "xkbcommon" { inherit simulator; };
      libffi = buildFn "libffi" { inherit simulator; };
      libwayland = buildFn "libwayland" { inherit simulator; };
      epoll-shim = buildFn "epoll-shim" { inherit simulator; };
      pixman = buildFn "pixman" { inherit simulator; };
      weston = buildFn "weston" {
        inherit simulator;
        enableGlClients = allowGpu;
      };
      weston-simple-shm = buildFn "weston-simple-shm" { inherit simulator; };
      # Unified archive: Settings can switch Wayland/Pixman vs iland DRM/GL at
      # runtime on GPU platforms only.
      "weston-compositor" = buildFn "weston-compositor" {
        inherit simulator;
        enableIlandDrm = allowGpu;
      };
    }
    # Full network stack (libssh2 + waypipe + compression) on all Apple mobile
    # variants that support Remote. visionOS shares the same libssh2 path.
    // lib.optionalAttrs (
      variant == "mobile" || variant == "tv" || variant == "watch" || variant == "vision"
    ) networkStack
    // lib.optionalAttrs allowGpu {
      iland = buildFn "iland" { inherit simulator; };
      angle = buildFn "angle" { inherit simulator; };
      moltenvk = buildFn "moltenvk" { inherit simulator; };
    }
    # SwiftShader CPU Vulkan ICD — iOS *Simulator* / CI only. On-device store
    # builds stay MoltenVK-only (App Store posture; verify-iland-graphics-bundle
    # forbids it there). The Simulator's Metal cannot bring up MoltenVK's pipeline
    # on headless CI (the app is killed with Metal domain 102), so vkcube needs a
    # pure-CPU device to fall back to.
    // lib.optionalAttrs (allowGpu && simulator) {
      swiftshader = buildFn "swiftshader" { inherit simulator; };
    }
    // lib.optionalAttrs allowGpu {
      kmscube = buildFn "kmscube" { inherit simulator; };
      "iland-gl-clients" = buildFn "kmscube" { inherit simulator; };
      "gbm-es2-demo" = buildFn "gbm-es2-demo" { inherit simulator; };
      # Vulkan acceptance client (krh/vkcube) over the same iland virtual DRM,
      # presenting through MoltenVK. GPU variants only; wwn-kmscube has no
      # tv/watch recipe for it by design.
      vkcube = buildFn "vkcube" { inherit simulator; };
      # Same mesa/kmscube sources as `kmscube` under opengl_cube_main, so Machines
      # can present the GLES cube as its own id. No tv/watch recipe by design.
      "opengl-cube" = buildFn "opengl-cube" { inherit simulator; };
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
    // lib.optionalAttrs (
      variant == "mobile" || variant == "tv" || variant == "watch" || variant == "vision"
    ) {
        # fcft required by real foot (all Apple mobile variants).
        fcft = buildFn "fcft" { inherit simulator; };
      }
    // lib.optionalAttrs (
      variant == "mobile" || variant == "tv" || variant == "watch" || variant == "vision"
    ) {
        # Weston and Niri are native in-process clients across the Apple
        # family. tvOS/watchOS use the constrained non-VM product surface.
        "cairo-gobject" = buildFn "cairo-gobject" { inherit simulator; };
        niri = buildFn "niri" { inherit simulator; };
        # phoon: pure-Rust in-process shell tool. Runs on the WHOLE Apple family
        # (rust-overlay stable ships std for the tier-3 tvOS/watchOS/visionOS
        # triples), so it is bundled everywhere like niri — no GPU/framework deps.
        phoon = buildFn "phoon" { inherit simulator; };
      }
    # wwn-wasm: WASI P1/P2 interpreter. Pulley on Apple mobile. Off on watchOS
    # (size), same as coreutils. See docs/wasm-wasi.md and milestone #2.
    // lib.optionalAttrs (variant == "mobile" || variant == "tv" || variant == "vision") {
        "wawona-wasm" = buildFn "wawona-wasm" { inherit simulator; };
      }
    // lib.optionalAttrs (variant == "mobile" || variant == "vision") {
        neovim = buildFn "neovim" { inherit simulator; };
        "neovim-rootfs" = buildFn "neovim-rootfs" { inherit simulator; };
        # wwn-niri fuzzel stack (Mod+D launcher spawned in-process).
        # fuzzel uses fork/exec — not available on tvOS; keep off tv/watch.
        fuzzel = buildFn "fuzzel" { inherit simulator; };
      }
    # fastfetch is an in-process (`fastfetch_main`) system-info tool with no
    # fork/exec and no GPU dependency, so it ships on the WHOLE Apple family.
    # wwn-fastfetch drops Metal/VideoToolbox on watchOS (CPU-only, no-Metal wall)
    # via its per-platform framework list — Wawona stays framework-agnostic. #139
    // lib.optionalAttrs (
      variant == "mobile" || variant == "vision" || variant == "tv" || variant == "watch"
    ) {
        fastfetch = buildFn "fastfetch" { inherit simulator; };
      };
in
base
// (mobileToytoolkitDeps { inherit buildFn simulator; })
// extras
