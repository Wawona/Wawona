---
description: macOS Mode A is mandatory. SIP on, iland DRM/KMS in a Cocoa window, never require Mode B dylib
alwaysApply: true
---

# macOS Mode A is always required

Wawona on macOS must keep working as **Mode A** with **SIP enabled**. Userspace
DRM/KMS/GBM (`iLand` `libiland_userland.a`) presents **inside a normal
macOS window** (AppKit + `WWNIlandPresenter` / CAMetalLayer). That is the
default product. It is not optional, not a fallback, and not replaced by
Desktop Replacement.

Mode B (`libwayland-mac.dylib`, WindowServer replacement, igetty, Path B) is
an **additional** SIP-off path on `.#wawona-macos-desktop-host` only. Building
or testing Mode B must never break Mode A.

## Required (Mode A)

- SIP on or off: `.#wawona-macos` (and store-shaped macOS) still launches,
  shows Machines, and runs nested compositors / clients **in-window**.
- Present path: `iland_drm_set_present_callback` → host surface. WindowServer
  stays up. No `DYLD_INSERT_LIBRARIES`, no Classic Take Over.
- Default when SIP is not fully disabled: ignore / clear
  `DesktopReplacementEnabled`. Never force Mode B.

## Hard rejects

- Requiring `csrutil disable` to use Wawona on macOS.
- Shipping or linking the Mode B dylib in `.#wawona-macos` / mobile.
- Making in-window DRM present depend on helper, sudoers, claim-ok, or igetty.
- Treating "macOS Wawona" as Desktop Replacement only.
- Breaking CAMetalLayer / Mode A present to finish Classic Take Over.

Canonical: `wawona-iland-mode-b-desktop`, `docs/iland-mode-a-b-desktop.md`,
`docs/agent-rules/wawona-macos-mode-a.md`. See also
`wawona-compositor-backend`.
