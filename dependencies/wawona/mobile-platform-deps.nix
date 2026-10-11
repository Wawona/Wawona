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
  # tv: GLES (ANGLE) + Vulkan (MoltenVK). watch: SHM/CPU only. iOS/vision: full GLES+VK.
  # SwiftShader stays iOS/vision simulator only (no tvOS recipe).
  allowGpu = variant == "mobile" || variant == "vision" || variant == "tv";
  allowVulkan = allowGpu;
  allowSwiftShaderSim = (variant == "mobile" || variant == "vision") && simulator;
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
      # runtime on GPU platforms only. iOS/iPadOS use compositor-ios-drm so
      # enableIlandDrm cannot be dropped by the unary-wrapper functionArgs hole.
      "weston-compositor" = buildFn (
        if variant == "mobile" then "weston-compositor-drm" else "weston-compositor"
      ) {
        inherit simulator;
        enableIlandDrm = allowGpu;
      };
    }
    # Full network stack (libssh2 + waypipe + compression) on all Apple mobile
    # variants that support Remote. visionOS shares the same libssh2 path.
    // lib.optionalAttrs (
      variant == "mobile" || variant == "tv" || variant == "watch" || variant == "vision"
    ) networkStack
    // lib.optionalAttrs allowVulkan {
      iland = buildFn "iland" { inherit simulator; };
      moltenvk = buildFn "moltenvk" { inherit simulator; };
    }
    // lib.optionalAttrs allowGpu {
      angle = buildFn "angle" { inherit simulator; };
    }
    # SwiftShader CPU Vulkan ICD. IOS *Simulator* / CI only. On-device store
    # builds stay MoltenVK-only (App Store posture; verify-iland-graphics-bundle
    # forbids it there). The Simulator's Metal cannot bring up MoltenVK's pipeline
    # on headless CI (the app is killed with Metal domain 102), so vkcube needs a
    # pure-CPU device to fall back to.
    // lib.optionalAttrs allowSwiftShaderSim {
      # wwn-iland merge historically concatenated .a members with duplicate
      # basenames; -force_load then fails (~900 duplicate Vulkan symbols).
      # Deduplicate by member basename (first wins) without rebuilding SS.
      swiftshader =
        let
          raw = buildFn "swiftshader" { inherit simulator; };
        in
        pkgs.runCommand "${raw.name or "swiftshader"}-deduped" {
          nativeBuildInputs = [
            pkgs.python3
            pkgs.llvmPackages.bintools
          ];
          meta = raw.meta or { };
        } ''
          mkdir -p "$out/lib"
          src="${raw}/lib/libvk_swiftshader.a"
          test -f "$src"
          python3 - "$src" "$out/lib/libvk_swiftshader.a" <<'PY'
          import os, subprocess, sys, tempfile
          from collections import Counter

          src, dst = sys.argv[1], sys.argv[2]
          ar = "llvm-ar"

          # Parse the archive ourselves so duplicate basenames are all visible.
          # First-wins dropped the larger LLVM/Reactor objects and left
          # undefined ConstantInt / Error / Timer / sw::CPUID symbols at Ld.
          def iter_members(path):
              with open(path, "rb") as f:
                  if f.read(8) != b"!<arch>\n":
                      raise SystemExit("not a System V / BSD ar archive")
                  while True:
                      header = f.read(60)
                      if len(header) < 60:
                          break
                      name = header[0:16].decode("ascii", "replace").strip()
                      size = int(header[48:58])
                      data = f.read(size)
                      if size % 2:
                          f.read(1)
                      if name.startswith("#1/"):
                          nlen = int(name[3:])
                          name = data[:nlen].split(b"\0", 1)[0].decode("ascii", "replace")
                          data = data[nlen:]
                      if name.endswith("/"):
                          name = name[:-1]
                      yield name, data

          best = {}
          for name, data in iter_members(src):
              if not name.endswith(".o"):
                  continue
              prev = best.get(name)
              if prev is None or len(data) > len(prev):
                  best[name] = data

          with tempfile.TemporaryDirectory() as td:
              objs = []
              # Darwin TMPDIR is case-insensitive. keep-N-Pass.cpp.o and
              # keep-M-pass.cpp.o collide on disk and drop LLVM RTTI (Pass
              # vtable). Use keep-%d.o only; never embed the original basename.
              for i, (name, data) in enumerate(sorted(best.items())):
                  path = os.path.join(td, "keep-%d.o" % i)
                  with open(path, "wb") as out:
                      out.write(data)
                  objs.append(path)
              if len(objs) < 2:
                  raise SystemExit("too few unique .o members: %d" % len(objs))
              subprocess.check_call([ar, "rcs", dst] + objs)
              # Fail closed if case-fold pairs were collapsed somehow.
              folded = {}
              for name in best:
                  key = name.lower()
                  folded.setdefault(key, []).append(name)
              lost = [v for v in folded.values() if len(v) > 1]
              # Both case variants must remain in `best` (different objects).
              # Count members written == len(best).
              if len(objs) != len(best):
                  raise SystemExit("dedupe write lost members: %d vs %d" % (len(objs), len(best)))
              print(
                  "swiftshader-dedupe: %d case-variant basename groups kept as separate members"
                  % len(lost)
              )

          dups = subprocess.check_output([ar, "t", dst], text=True).splitlines()
          repeated = [n for n, c in Counter(dups).items() if c > 1]
          if repeated:
              raise SystemExit("dedupe left duplicate members:\n" + "\n".join(repeated[:20]))
          print(
              "swiftshader-dedupe: %d unique .o members (keep-largest)"
              % len(best)
          )
          PY
          if [ -d "${raw}/lib/vulkan" ]; then
            cp -a "${raw}/lib/vulkan" "$out/lib/"
          fi
        '';
    }
    // lib.optionalAttrs allowGpu {
      kmscube = buildFn "kmscube" { inherit simulator; };
      "iland-gl-clients" = buildFn "kmscube" { inherit simulator; };
      "gbm-es2-demo" = buildFn "gbm-es2-demo" { inherit simulator; };
      # GLES cube over Wayland-EGL (iland + ANGLE). tvOS uses the same recipe.
      "opengl-cube" = buildFn "opengl-cube" { inherit simulator; };
    }
    // lib.optionalAttrs allowVulkan {
      # Vulkan cube over Wayland IOSurface dmabuf + MoltenVK.
      vkcube = buildFn "vkcube" { inherit simulator; };
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
        # triples), so it is bundled everywhere like niri. No GPU/framework deps.
        phoon = buildFn "phoon" { inherit simulator; };
      }
    # wwn-relay: WASI P1/P2 interpreter + Linux VM/OCI policy. Pulley on Apple
    # mobile. Mandatory on every Apple variant including watchOS.
    // lib.optionalAttrs (variant == "mobile" || variant == "tv" || variant == "watch" || variant == "vision") {
        "wawona-wasm" = buildFn "wawona-wasm" { inherit simulator; };
        "wawona-relay" = buildFn "wawona-relay" { inherit simulator; };
      }
    // lib.optionalAttrs (variant == "mobile" || variant == "vision") {
        # wwn-niri fuzzel stack (Mod+D launcher spawned in-process).
        # fuzzel uses fork/exec. Not available on tvOS; keep off tv/watch.
        fuzzel = buildFn "fuzzel" { inherit simulator; };
      }
    # fastfetch is an in-process (`fastfetch_main`) system-info tool with no
    # fork/exec and no GPU dependency, so it ships on the WHOLE Apple family.
    # wwn-fastfetch drops Metal/VideoToolbox on watchOS (CPU-only, no-Metal wall)
    # via its per-platform framework list. Wawona stays framework-agnostic. #139
    // lib.optionalAttrs (
      variant == "mobile" || variant == "vision" || variant == "tv" || variant == "watch"
    ) {
        fastfetch = buildFn "fastfetch" { inherit simulator; };
      };
in
base
// (mobileToytoolkitDeps { inherit buildFn simulator; })
// extras
