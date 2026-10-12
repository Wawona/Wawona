---
description: iland Mode A vs Mode B for Desktop/LockScreen. Not Wawona Swinging Bridge
alwaysApply: true
---

# iLand Mode A / Mode B + Desktop / LockScreen Replacement

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
`wawona-macos-mode-a`. Mode B never becomes the only macOS path. Aqua vs
Classic weston/niri backends: `wawona-compositor-backend`.

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
 **Fully Disabled**. Partial (`Debugging Restrictions: disabled` after
 `csrutil enable --without debug`) is refused.
2. If SIP is **not** fully disabled → Mode A only; ignore / clear
 `DesktopReplacementEnabled`.
3. If SIP allows **and** Settings → Desktop → Enable Desktop Replacement is on
 **and** the user chooses Replace now → Mode B via
 `WWNDesktopReplacementController` (privileged insert of bundled dylib).
 First enable installs `/etc/sudoers.d/wawona-modeb`.
 `nix run .#install` always syncs helper + dylib + `wwn-iowatchdog` +
 sudoers for this store (administrator once) and
 fails if the helper still points at a previous nix store. It does **not**
 take over the screen. It does **not** install
 `com.aspauldingcode.wawona.modeb-login`. It must **never** run
 `wwn-iowatchdog disable`/`enable` or attach `lldb` to `watchdogd`
 (2026-08-20 install panic: daemon exited SIGTRAP while kernel IOWatchdog
 was still armed). Stage may only `launchctl enable`+`bootstrap` a
 disabled watchdogd job. That Aqua LaunchAgent killed WindowServer on
 login, Aqua died, and the helper restored then re-fired (2026-08-18 and
 2026-08-19). Take Over is per session. Logout returns normal macOS. Take
 Over disables kernel IOWatchdog (`wwn-iowatchdog`, IOKit type 1 / method
 3) first, then unloads `com.apple.watchdogd`, then WindowServer. Abort if
 IOWatchdog disable fails. Unloading `watchdogd` without that panics
 immediately (`watchdogd[pid] exited`, 2026-08-19). `launchctl kickstart
 -k` on watchdogd is the same panic (ws-guard every 10s, 2026-08-19
 23:12). Probe (`--mode-b-probe`) may inject while both stay up.
 `ws-guard` may restore WindowServer only. It must never
 enable/load/bootstrap/kickstart/bootout watchdogd. Never `export
 DYLD_INSERT_LIBRARIES` in `run-modeb.sh`. Prefix it on the niri/weston
 command only. Apple `/bin/*` is `arm64e`; the dylib is `arm64`. A global
 export kills `date`/`mkdir`/`launchctl` and leaves no compositor PID.
 Partial SIP is refused. WindowServer restore uses `enable` + `load -w` +
 `kickstart -k` when launchd has no pid. Never do that to watchdogd.
 Restore after Classic with Path B sticky must **not** bootstrap or
 kickstart Path B and must **not** Apple-enable `watchdogd` (2026-08-23:
 Path B kickstart re-armed kernel monitoring, 8 checkins, 92s timeout).
 Kernel Disable stays sticky. Apple enable is only when Path B is absent.
4. Otherwise → Mode A.

Never invent CSR_* syscalls; stay on `csrutil status` string matching.

## Shipping rules (hard)

- Ship `libwayland-mac.dylib` **only** in `.#wawona-macos-desktop-host`
 (`Contents/Library/Wawona/iland/`). Built from
 `iLand` `registryFragment.iland-baremetal` /
 `dependencies/libs/iland/macos-baremetal.nix`.
- Ship `wwn-iowatchdog` from flake input `wwn-iowatchdog` (L3′). Do not
 re-vendor Watchdog C sources under `Wawona/src/platform/macos/modeb/`.
- Default `.#wawona-macos` (store-safe / product-build / TestFlight-shaped) and
 **all** iOS/iPadOS/tvOS/watchOS/visionOS/Android artifacts: **dylib absent**.
- Assert with `Wawona/.github/scripts/verify-iland-mode-b-bundle.sh`.
- Cargo: `iland-baremetal` only with `profile-desktop-host` or
 `profile-full-dev` (see `Wawona/src/lib.rs` compile_errors). Never on mobile.
- Do **not** ship or describe Desktop/LockScreen as ready until the planned
 work lands; gates stay ⏳ / in-app Apple-mobile ❌.

## Where to edit

- Mode A recipes / shims: `iLand` (`macos.nix`, `ios.nix`, `android.nix`,
 `upstream/shims/`).
- Mode B dylib build: `iLand/.../macos-baremetal.nix`.
- Mode B Watchdog tools: `github.com/Wawona/wwn-iowatchdog`.
- **macOS 26:** `wawona-mode-b-watchdog-safety` (never Take Over / LLDB on
 `watchdogd`).
- SIP + prefs UI: `Sources/WawonaApple/ModeB/SipStatus.swift`,
  `Sources/WawonaApple/Settings/WWNPreferences.swift` Desktop section.
- Engage/disengage: `WWNDesktopReplacementController` (Swift),
  `Sources/WawonaApple/Runners/WWNMachineSessionBridge.swift`. Compositor argv/env:
  `WaypipeRunner` `baremetalCompositorLaunchSpecForProfile:`.
- Canonical prose: `Wawona/docs/iland-mode-a-b-desktop.md`.
- Wawona Swinging Bridge: `wawona-swinging-bridge`, `Wawona/docs/swinging-bridge.md`.
