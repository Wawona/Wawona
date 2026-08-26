# Mode B scanout coordination (iland + igetty + weston + niri)

Classic Desktop Replacement has **one panel**. These components must never
pageflip or present over each other.

## Single lease

Canonical implementation: `wwn-iland/.../shims/modeb-coord.{h,c}`.

| Path | Role |
|------|------|
| `/tmp/libwayland-support/modeb-drm-client.pid` | Scanout holder pid (flock-backed) |
| `/tmp/libwayland-support/modeb-vt` | Active VT (inputd → igetty) |

### Writers

- **iland** (`libwayland-mac.dylib`): `wwn_modeb_scanout_claim()` on first
  `open("/dev/dri/card*")`; `wwn_modeb_scanout_release()` on dylib unload.
  weston, niri, kmscube, and overlay clients all claim through this path.

### Readers / enforcers

- **igettyd**: never `drmModePageFlip` dumb text buffers while
  `wwn_modeb_scanout_is_held()` or `wwn_modeb_session_runs_compositor(shell)`.
  The session walk covers typed `weston`/`niri` (shell script children of zsh).
- **inputd**: Ctrl+Alt+Backspace calls `wwn_modeb_scanout_stop_holder()` (not
  `modeb-compositor.pid`).

## Hard rejects

- igetty text VT pageflips while a DRM client holds the lease
- Feeding compositor stderr into vterm while that VT session runs a compositor
- Separate pid files for "compositor" vs "DRM client" (one lease only)
- `DrmNode::from_path` / rustix `stat` on macOS Mode B (use open + from_file;
  see `wawona-macos-drm-open.patch`)
- Global `DYLD_INSERT_LIBRARIES` in the login shell (compositor exec only)

## Verify after restage

```bash
# Typed weston on text VT: holder should be weston pid, igetty must not pageflip
cat /tmp/libwayland-support/modeb-drm-client.pid
pgrep -lf weston

# Restore chord stops holder, not only igettyd
# Ctrl+Alt+Backspace → holder pid receives SIGTERM
```

See `wawona-iland-mode-b-desktop`, `wawona-compositor-backend`,
`docs/incident-reports/2026-08-25-classic-armed-epoch-timeout/`.
