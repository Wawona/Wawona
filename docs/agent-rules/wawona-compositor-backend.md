# macOS weston/niri: nested Wayland and iland DRM

Weston and niri are dual-backend. They must launch from Machines Start in
**Aqua** and after **Classic Desktop Replacement**. The session chooses the
backend. Do not pin nested-only. Do not force DRM while WindowServer is up.

This is **not** Wawona Swinging Bridge. Not Desktop Replacement itself. The
clients are bundled compositors.

## Detection

Classic / own-display (no host compositor): **Apple WindowServer is not
running**. `WWNHostSessionUsesOwnDisplayDRM()`: NSScreen first (Machines
Start is AppKit), then a positive `proc_name` match for `WindowServer`.
A censored process list (hardened runtime often cannot name WindowServer)
is Aqua, not Classic. CLI wrappers: `pgrep -x WindowServer`.

Never treat these as Classic while Aqua is up:

- leaked `WWN_MODEB_TTY` / `NIRI_BACKEND=tty` / `WWN_MODEB_INSERT`
- `DesktopReplacementEnabled=1` without Take Over
- Settings Enable Desktop Replacement (Path B armed, WindowServer still up)

## Aqua (WindowServer up)

Honour Display Backend (`CompositorBackend` via `WWNResolveCompositorBackend`).
`auto` is nested `wayland`.

| Backend | weston | niri |
|---|---|---|
| `auto` / `wayland` | `--backend=wayland` on the Wawona socket | `NIRI_BACKEND=nested` |
| `drm` | in-process `--backend=drm` + iland Metal present (`WWNIlandPresenter`) | nested on Wawona (macOS has no in-process `niri_main`). niri DRM is Classic insert |

Strip Mode B leftovers from the Wawona process and from nested `NSTask` env:
`WWN_MODEB_TTY`, `WWN_MODEB_INSERT`, `NIRI_BACKEND=tty`,
`libwayland-mac.dylib` in `DYLD_INSERT_LIBRARIES`.

macOS weston **rewrites** `--backend=wayland` to drm when `WWN_MODEB_TTY` is
set. macOS niri **force-selects** the TTY backend when that var is set. Both
then fail in Aqua (no insert, no real `/dev/dri`).

## Classic (WindowServer down)

No host Wayland. Always wwn-iland userspace DRM/KMS/GBM:

- weston `--backend=drm`
- niri `NIRI_BACKEND=tty` and `WWN_MODEB_TTY=1`
- Prefix `DYLD_INSERT_LIBRARIES` from `WWN_MODEB_INSERT` on the compositor
  exec only, as the **login user**
- Do not nest. Do not kickstart compositor-host. Do not export insert in the
  login shell (Apple `/bin/*` is arm64e)

## Hard rejects

- Nesting weston/niri after Classic Take Over
- Forcing DRM/tty on Aqua Machines Start because Desktop Replacement is
  enabled or `WWN_MODEB_TTY` leaked
- `sudo niri` / `sudo weston` (sudo strips insert; libc `open("/dev/dri")`
  hits a missing real node)
- Opening a real DRM/KMS node. iland userspace only
- Pinning nested-only and discarding the iland DRM path
- Equating this with Swinging Bridge or with Mode B dylib present

## Code

- Resolver: `WWNResolveCompositorBackend`, `WWNHostSessionUsesOwnDisplayDRM`
  in `src/platform/macos/ui/Settings/WWNWaypipeRunner.m`
- CLI wrappers: `scripts/macos-register-cli-bins.sh`
- Doorman session: `wwn-igetty` `libexec/wwn-modeb-session/`

Cursor rule: `wawona-compositor-backend`. Canonical prose:
[`../iland-mode-a-b-desktop.md`](../iland-mode-a-b-desktop.md). See also
`wawona-macos-mode-a`, `wawona-iland-mode-b-desktop`,
`wawona-native-compositors`.
