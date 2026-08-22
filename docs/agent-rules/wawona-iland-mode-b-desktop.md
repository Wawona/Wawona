# wwn-iland Mode A / Mode B + Desktop / LockScreen Replacement

Authority for **when** Wawona uses App Store-safe in-window iland (Mode A)
versus the SIP-gated host Desktop/LockScreen `.dylib` (Mode B on macOS).

**Wawona Swinging Bridge is a different product** (host-app → Wayland bridge). Do not document
Wawona Swinging Bridge here. See `wawona-swinging-bridge`.

## WindowServer options (Classic / KEEP_WS / Path C)

Not IOWatchdog Path A/B. Full table:
`Wawona/docs/mode-b-windowserver-options.md`.

| Option | WindowServer | Status |
|---|---|---|
| Classic | Booted out; Mode B owns panel | Implemented (kmscube proof) |
| KEEP_WS | Left up; Aqua stays | Implemented (probe) |
| Path C | Parked/suspended; Cocoa still has WS for Swinging Bridge | **Planned** after multi-TTY |

Desktop / LockScreen status: **⏳ planned / coming soon** (in development on
macOS and Android; iOS path only via `repo.wawona.io`. Website docs only).

## Two iland modes (do not conflate with Wawona Swinging Bridge Mode A/B)

| | Mode A (default) | Mode B (desktop-host only) |
|---|---|---|
| Artifact | `libiland_userland.a` | `libwayland-mac.dylib` |
| Present | `iland_drm_set_present_callback` → `WWNIlandPresenter` / CAMetalLayer | Mach IPC → `framebufferd` (SkyLight path) |
| Load | Static link | `DYLD_INSERT_LIBRARIES` + Dobby (CoreBedtime model) |
| SIP / root | Not required | SIP **fully disabled** (`csrutil disable`) + root for constructor |
| App Store | Yes | **No** |
| Platforms | macOS, iOS/iPadOS/visionOS, Android; tvOS/watchOS stubs | **macOS only** (Desktop/LockScreen host tweak) |

**Hard:** macOS Mode A (SIP on, in-window present) must keep working. See
`wawona-macos-mode-a`. Mode B never becomes the only macOS path.

## What Desktop / LockScreen is

Replace the **host** desktop environment and lock screen with a Wawona machine
picker (nested compositor session). Machine profile type: **native ports
only**. Not Linux. Not App Store iOS family.

| Host | Mechanism | Root / SIP |
|---|---|---|
| **macOS** | SIP fully disabled (`csrutil disable`) + bundled `.dylib` in `wawona-macos-desktop-host` | Required for Mode B engage |
| **Android** | Default Home App + LockScreen APIs | **No root**; **no fallback tier** |
| iOS / iPadOS | Jailbreak tweak from **`repo.wawona.io`** (Sileo) | Outside App Store only |
| App Store iOS / iPadOS / tvOS / watchOS / visionOS | - | **❌ forbidden** in-app; **never mention jailbreak** in store binaries |

## Runtime decision (macOS)

1. Detect SIP via `WWNSipStatus` (`csrutil status` text parse. Same as
   playground `checkSipStatus`). Mode B requires the first line
   `System Integrity Protection status: disabled`. Settings shows that as
   **Fully Disabled**. Partial
   (`Debugging Restrictions: disabled` after `csrutil enable --without debug`)
   is refused.
2. If SIP is **not** fully disabled → Mode A only; ignore / clear
   `DesktopReplacementEnabled`.
3. If SIP allows **and** Settings → Desktop → Enable Desktop Replacement is on
   **and** the user chooses Take Over Screen Now → Mode B via
   `WWNDesktopReplacementController` (privileged insert of bundled dylib).
   First enable installs sudoers NOPASSWD for the root helper. It does not
   install a login LaunchAgent. Take Over is per session. Disable kernel
   IOWatchdog (`wwn-iowatchdog`) first, then unload watchdogd, then
   WindowServer. Abort if IOWatchdog disable fails. Never
   `launchctl kickstart -k` watchdogd. Probe may inject while Aqua stays
   up. Prefix `DYLD_INSERT_LIBRARIES` on the niri/weston exec only.
4. Otherwise → Mode A.

Never invent CSR_* syscalls; stay on `csrutil status` string matching.

## Shipping rules (hard)

- Ship `libwayland-mac.dylib` **only** in `.#wawona-macos-desktop-host`
  (`Contents/Library/Wawona/iland/`). Built from
  `wwn-iland` `registryFragment.iland-baremetal` /
  `dependencies/libs/iland/macos-baremetal.nix`.
- Default `.#wawona-macos` (store-safe / product-build / TestFlight-shaped) and
  **all** iOS/iPadOS/tvOS/watchOS/visionOS/Android artifacts: **dylib absent**.
- Assert with `Wawona/.github/scripts/verify-iland-mode-b-bundle.sh`.
- Cargo: `iland-baremetal` only with `profile-desktop-host` or
  `profile-full-dev` (see `Wawona/src/lib.rs` compile_errors). Never on mobile.
- Do **not** ship or describe Desktop/LockScreen as ready until the planned
  work lands; gates stay ⏳ / in-app Apple-mobile ❌.

## Where to edit

- Mode A recipes / shims: `wwn-iland` (`macos.nix`, `ios.nix`, `android.nix`,
  `upstream/shims/`).
- Mode B dylib build: `wwn-iland/.../macos-baremetal.nix`.
- Mode B Watchdog tools: `wwn-iowatchdog` (L3′ flake; not in-tree C).
- **macOS 26 watchdog safety:** `wawona-mode-b-watchdog-safety` (never Take
  Over / never LLDB MCP on `watchdogd`).
- SIP + prefs UI: `WWNSipStatus.*`, `WWNPreferences.m` Desktop section.
- Engage/disengage: `WWNDesktopReplacementController.*`,
  `WWNMachineSessionBridge.m`. Default `nix run .#install` skips Mode B
  restage. `WAWONA_MODEB_STAGE=1 nix run .#install` (or `Wawona --mode-b-stage`)
  copies helper + dylib for this store (no take-over; never `wwn-iowatchdog`
  disable/enable or lldb on `watchdogd` during stage).
  Site: https://wawona.io/docs/desktop/ (restage helper and dylib).
- Canonical prose: `Wawona/docs/iland-mode-a-b-desktop.md`.
- Wawona Swinging Bridge: `wawona-swinging-bridge`, `Wawona/docs/swinging-bridge.md`.
