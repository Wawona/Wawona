# iland (vendored)

`iland` is a Wayland platform-compat layer for Apple platforms. Wawona consumes a
fork of it to provide a **userland, in-window** Linux-graphics API surface
(EGL/GLES via ANGLE, GBM via IOSurface, DRM/KMS, udev, libinput) so that Linux
Wayland clients and Weston tools (e.g. `weston-simple-egl`, `kmscube`,
`es2gears`) can build and run inside the Wawona compositor.

## Provenance

- Upstream fork: `https://github.com/wawona/iland` (branch `real`)
- Seeded from: `https://github.com/corebedtime/iland`
- Vendored commit: `3519656b9f36251d324889be681449169f627d6d`
- Vendored tree: `upstream/` (excludes `.git`, `build/`, `build-weston/`, `.resources/`)
- License: MIT (see `upstream/`)

## Two build modes (see docs plan Phase 3)

- **Mode A — userland in-window (default; ALL Apple platforms; App-Store-safe).**
  Static, signed compat libraries (`gbm`/`egl`/`drm`/`udev`/`libinput`/`glibc`),
  no code injection, no daemons, no private SPI, no SIP/root. Buffers are
  IOSurfaces composited by Wawona's in-window CAMetalLayer renderer; GL is ANGLE.
- **Mode B — bare-metal WindowServer replacement (macOS ONLY; opt-in; NOT
  App-Store-safe).** Re-enables upstream's Dobby code injection, AMFI bypass,
  `framebufferd`/SkyLight, and `inputd` (requires SIP disabled + root). Gated
  behind `iland-baremetal` (default off) and Wawona's `profile-desktop-host` /
  `profile-full-dev`. Never compiled for iOS/iPadOS/tvOS/visionOS/watchOS or
  App Store / `store-safe` builds.

## Patches applied for Wawona

- Replace the MacPorts build (`port install ...`, `/opt/local`) with a Nix flake
  that reuses Wawona's existing macOS deps (`libwayland`, `xkbcommon`, `pixman`,
  `epoll-shim`, fonts) — only ANGLE (`nixpkgs#angle`) is new.
- `shims/egl/src/egl.c`: replace hardcoded `dlopen("/opt/local/lib/libEGL.dylib")`
  with the Nix ANGLE path / static link.
- Mode A: the DRM page-flip present path (`shims/drm/.../drm.c` Mach IPC to
  `framebufferd`) is redirected to a Wawona in-window present callback instead of
  a privileged daemon.

## Sync workflow

Patches are made in the `wawona/iland` fork, pushed to `origin` (`real`), and
this vendored copy is re-synced to the new commit (update `Vendored commit`
above).
