# wwn-iland Mode A / Mode B + Desktop Replacement

Tracked mirror of Cursor rule `wawona-iland-mode-b-desktop` (alwaysApply).
Prefer [`../iland-mode-a-b-desktop.md`](../iland-mode-a-b-desktop.md) for full
anchors; this file is the short agent checklist.

## Two modes (do not conflate)

| | Mode A (default) | Mode B (desktop-host only) |
|---|---|---|
| Artifact | `libiland_userland.a` | `libwayland-mac.dylib` |
| Present | `iland_drm_set_present_callback` → Metal | Mach IPC → `framebufferd` |
| Load | Static link | `DYLD_INSERT_LIBRARIES` + Dobby |
| SIP / root | Not required | SIP Disabled or PartiallyDisabled + root |
| App Store | Yes | **No** |
| Platforms | macOS, iOS/iPadOS/visionOS, Android; tvOS/watchOS stubs | **macOS only** |

## Runtime (macOS)

1. `WWNSipStatus` via `csrutil status` (playground partial = Debugging Restrictions disabled).
2. SIP blocked → Mode A; clear `DesktopReplacementEnabled`.
3. SIP allows + Desktop on + Desktop machine connect → `WWNDesktopReplacementController` Mode B.
4. Else Mode A.

## Shipping

- Dylib **only** in `.#wawona-macos-desktop-host` → `Contents/Library/Wawona/iland/`.
- `.#wawona-macos` + all non-macOS → dylib **absent**.
- Verify: `.github/scripts/verify-iland-mode-b-bundle.sh`.
- Cargo `iland-baremetal` only with `profile-desktop-host` / `profile-full-dev`.

## Desktop surface

macOS + Android only. Android: no SIP; anowaW rootless vs Shizuku/root power.
Never Mode B dylib on Android or iOS family.
