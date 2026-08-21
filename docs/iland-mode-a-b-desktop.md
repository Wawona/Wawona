# iland Mode A / Mode B and Desktop / LockScreen Replacement

> **Public subset** for wawona.io. Desktop / LockScreen are **macOS + Android**
> (planned), plus **iOS / iPadOS jailbreak tweaks** documented only on the website /
> `repo.wawona.io`. **Not** Linux. **Not** App Store Apple-mobile builds.
>
> **Wawona Swinging Bridge is separate**. See [`swinging-bridge.md`](swinging-bridge.md). Do not document
> Swinging Bridge as Desktop or LockScreen. **VMs/containers** are separate. See
> [`vms-containers.md`](vms-containers.md).

Live grades: [`iland-graphics-progress.md`](iland-graphics-progress.md).
CI bundle matrix: [`testing/graphics-ci-matrix.md`](testing/graphics-ci-matrix.md).

Canonical description of how Wawona uses **wwn-iland** for graphics present and
macOS Desktop/LockScreen host replacement. When this conflicts with older docs
or comments, **this file wins** (also mirrored in
`.cursor/rules/wawona-iland-mode-b-desktop.mdc` and `AGENTS.md`).

Upstream inspiration: [CoreBedtime/iland](https://github.com/CoreBedtime/iland).
Wawona packaging: [wwn-iland](https://github.com/Wawona/wwn-iland).
Stack architecture and toolkit contracts:
[`iland-graphics-stack.md`](iland-graphics-stack.md). Repository ownership:
[`wwn-repo-dag.md`](wwn-repo-dag.md).

## Status

**Coming soon / in development.** Desktop and LockScreen replacement are not
ready to treat as shipping. Product gates stay **planned** on macOS and Android;
App Store Apple-mobile builds keep Desktop/LockScreen **forbidden** and must
**never mention jailbreak** in UI or strings.

## What Desktop / LockScreen is

Make Wawona the **host desktop environment** and **lock-screen / greeter** with
a Wawona **machine picker**. Machine profile type for these roles: **native
ports only**.

| Host | Mechanism | Privilege |
|---|---|---|
| **macOS** | SIP fully disabled (`csrutil disable`) + `.dylib` tweak in `wawona-macos-desktop-host` | Required for Mode B |
| **Android** | Default Home App + LockScreen APIs | **No root**; **no fallback tier** |
| **iOS / iPadOS** | Jailbreak tweak from **`repo.wawona.io`** (Sileo source) | Outside App Store only; website docs only |
| Linux / App Store Apple-mobile / tvOS / watchOS / visionOS | - | **Forbidden** in store binaries (never mention jailbreak there) |

## Summary (iland present modes)

- **Mode A** is the default, App Store-safe path: static `libiland_userland.a`,
  in-window DRM/KMS/EGL/GBM over IOSurface + ANGLE, present via
  `iland_drm_set_present_callback` into Wawona’s Metal layer.
- **Mode B** is optional, **macOS-only** for **Desktop/LockScreen host
  replacement**, **not** App Store safe: ship `libwayland-mac.dylib`, load with
  `DYLD_INSERT_LIBRARIES` + Dobby (same model as CoreBedtime), replace
  SkyLight/WindowServer / lock path via `framebufferd`. Requires SIP fully
  disabled (`csrutil disable` in Recovery) and root. `csrutil enable --without
  debug` is not enough.
- **Android Desktop/LockScreen** uses platform Home + LockScreen APIs. Not the
  macOS dylib, and not Wawona Swinging Bridge.
- **Wawona Swinging Bridge** (app bridge) has its own Mode A/B. See [`swinging-bridge.md`](swinging-bridge.md).

## Decision tree

```text
feature?
  Wawona Swinging Bridge                      → see swinging-bridge.md (not this file)
  Desktop / LockScreen
    Linux                     → forbidden
    App Store iOS family      → forbidden in-app (no jailbreak mentions)
    iOS / iPadOS (website / repo only) → repo.wawona.io jailbreak tweak (planned)
    Android                   → Default Home + LockScreen (planned; no root)
    macOS
      SIP fully disabled?     (`csrutil status`: disabled)
        no  → Mode A (ignore Desktop toggle; clear if stale)
        yes → DesktopReplacementEnabled?
              no  → Mode A
              yes → Mode B: disable kernel IOWatchdog, unload watchdogd,
                    unload WindowServer, DYLD_INSERT bundled dylib into
                    niri/weston (framebufferd). Abort if IOWatchdog
                    disable fails. Compositor argv comes from
                    WWNWaypipeRunner (weston --backend=drm, niri
                    NIRI_BACKEND=tty, custom command as written).
```

SIP detection: `WWNSipStatus` → `csrutil status` text parse (playground
`checkSipStatus` port). Mode B is allowed only when the **first line** is
`System Integrity Protection status: disabled` (optional period). Settings
shows that state as **Fully Disabled**. Custom Configuration /
`Debugging Restrictions: disabled` after `csrutil enable --without debug`
is classified as partial and **refused**. Do not use CSR_* APIs.

## Artifacts and packages

| Package / recipe | Mode | Notes |
|------------------|------|--------|
| `wwn-iland` `iland` (`macos.nix`, `ios.nix`, …) | A | `libiland_userland.a` |
| `wwn-iland` `iland-baremetal` (`macos-baremetal.nix`) | B | `libwayland-mac.dylib` + embedded daemons |
| `wwn-iowatchdog` (L3′, flake input) | B | macOS Watchdog CLIs; bundled as `Contents/Library/Wawona/wwn-iowatchdog` |
| `.#wawona-macos` | A only | Product / store-safe shaped; **must not** contain Mode B dylib |
| `.#wawona-macos-desktop-host` | A + B dylib | Developer ID / desktop-host; dylib at `Contents/Library/Wawona/iland/libwayland-mac.dylib` |
| iOS / Android apps | A only | Never ship Mode B dylib |

Cargo features for desktop-host Rust backend: `profile-desktop-host` +
`iland-baremetal` (gated in `src/lib.rs`). Mobile and store-safe builds must
not enable `iland-baremetal`.

## Runtime code anchors (macOS)

| Concern | Location |
|---------|----------|
| SIP classify | `src/platform/macos/ui/Settings/WWNSipStatus.{h,m}` |
| Desktop prefs UI + hard enforce | `WWNPreferences.m` (Desktop section), keys in `WWNPreferencesManager` |
| Mode B engage / disengage | `WWNDesktopReplacementController.{h,m}` |
| Mode B compositor argv/env | `WWNWaypipeRunner` `baremetalCompositorLaunchSpecForProfile:` |
| Connect / lockscreen handoff | `WWNMachineSessionBridge.m` |
| Mode A present | `WWNIlandPresenter.m` + `iland_present.h` |
| Bundle verify | `.github/scripts/verify-iland-mode-b-bundle.sh` |

Prefs (macOS `NSUserDefaults`):

- `DesktopReplacementEnabled`
- `DesktopReplacementMachineId` (nested compositor native profile only)
- `LockscreenReplacementEnabled` / `LockscreenReplacementMachineId`
- `SwingingBridgeEnabled` (Wawona Swinging Bridge. Separate feature; see [`swinging-bridge.md`](swinging-bridge.md))

## Mode B launch (macOS)

CoreBedtime's host takeover is the model: unload Apple's WindowServer, inject
`libwayland-mac.dylib` into a **root** compositor process, let the dylib start
`framebufferd` / `inputd` / `amfiexceptiond`. Wawona does not copy
`run-weston.sh` or `WESTON_MODULE_MAP`. The display server is whichever nested
compositor the Desktop Machine names.

1. Settings stores `DesktopReplacementMachineId` (weston, niri, or custom
   compositor). Demo clients (`kmscube`, `weston-terminal`, `foot`) are not
   eligible.
2. `nix run .#install` (and `Wawona --mode-b-stage`) restages
   `libwayland-mac.dylib`, `wwn-iowatchdog`, and a root-owned helper
   (`/Library/Application Support/Wawona/run-modeb.sh`) and installs
   `/etc/sudoers.d/wawona-modeb` (`NOPASSWD` for that helper and
   `wwn-iowatchdog` only). One admin authorization. If a prior Take Over
   left `com.apple.watchdogd` disabled, stage only `launchctl enable` +
   `bootstrap`s it (never `kickstart -k`). Stage must **never** run
   `wwn-iowatchdog disable` / `enable` or attach `lldb` to `watchdogd`:
   that probe paniced on 2026-08-20 (`watchdogd` exited SIGTRAP /
   namespace 2 subcode 0x5 while kernel IOWatchdog was still armed).
   IOWatchdog disable belongs only on Take Over. Stage does **not** take
   over the screen and does **not** install a login LaunchAgent. Take
   Over Screen Now is the only activate step. Logout and the next Aqua
   login return normal macOS.
3. Take Over consumes sticky Path B (preferred) or Path A
   `/var/db/wwn-iowatchdog/claim-ok` before unloading watchdogd /
   WindowServer (`WWN_MODEB_WD=iowatchdog-then-unload`). Soft-inject /
   `lldb` stay forbidden. Without `claim-ok`, Settings refuses Classic
   Take Over and points at `claim-install --path-b` + reboot. KEEP_WS
   `--mode-b-probe` may still inject while WindowServer and watchdogd
   stay up. `nix run .#install` skips Mode B restage by default
   (`WAWONA_MODEB_STAGE=1` to force). Never `export
   DYLD_INSERT_LIBRARIES`. Insert on the niri/weston exec only.
   `ws-guard` may restore WindowServer only.
4. After logout, Aqua's login screen starts WindowServer. The next login
   does not re-run Mode B. Use Settings → Desktop → Take Over Screen Now
   again. Older builds that wrote
   `com.aspauldingcode.wawona.modeb-login` caused a login WindowServer
   crash loop (helper kills WS, Aqua dies, launchd sends TERM,
   restore_aqua, agent fires again). The menubar boots that agent out if
   a leftover plist is present. A leftover KeepAlive system daemon can
   keep niri running in the background without owning the screen.
5. `WWNWaypipeRunner` `baremetalCompositorLaunchSpecForProfile:` supplies argv
   and env: no `WAYLAND_DISPLAY` (this process *is* the display server),
   `XDG_RUNTIME_DIR=/tmp/wawona-$uid`, weston `--backend=drm
   --continue-without-input` plus the bundled `weston.ini`, niri
   `NIRI_BACKEND=tty`, custom commands tokenized and exec'd as written.
6. Disable is a full teardown: restore Apple's WindowServer (enable +
   load; `kickstart -k` only if WindowServer is not already running), kill
   root niri/weston and framebufferd/inputd, and remove the login
   LaunchAgent, sudoers drop-in, helper, installed `libwayland-mac.dylib`,
   and `ws-guard` LaunchDaemon. Settings keeps the switch on if the
   privileged uninstall is cancelled.
7. If the nested compositor exits unexpectedly, or framebufferd never
   starts, the helper leaves or restores Apple's WindowServer, writes
   `/tmp/wawona-modeb-failed.reason`, and exits 0. Aqua stays usable.
   The Enable switch is turned off. Take Over Screen Now retries. Log:
   `/tmp/wawona-modeb.log`. See
   [`incident-reports/2026-08-19-windowserver-login.md`](incident-reports/2026-08-19-windowserver-login.md).

## Android Desktop / LockScreen (no SIP, no root)

| Surface | Behavior |
|---------|----------|
| Desktop | Default Home App role |
| LockScreen | Platform LockScreen replacement APIs |
| Privilege | No root required; no MediaProjection “fallback tier” as the Desktop story |

Wawona Swinging Bridge settings (`wawona.swingingBridge.*`) are **not** Desktop/LockScreen. See
[`swinging-bridge.md`](swinging-bridge.md) and Settings Desktop / App Bridge copy when those ship.

## Store / distribution compliance (per target)

macOS is **third-party distribution** (Developer ID / notarized), **not** Mac
App Store. Never gated on Mac App Store review rules (see
`wawona-macos-no-appstore.mdc`). Everything that ships to a store must be
**Mode A-shaped end-to-end** for graphics, and must not ship Desktop Mode B or
Wawona Swinging Bridge Mode B.

| Target | Distribution | Compliance bar for graphics / Desktop |
|--------|--------------|----------------------------------------|
| **iOS** | App Store | Mode A only; no Desktop/LockScreen UI; **no jailbreak mentions**; no Mode B dylib; SSH = libssh2 only |
| **iPadOS** | App Store | Same as iOS for Desktop/Wawona Swinging Bridge store policy + multi-window required |
| **visionOS** | App Store | Same Mode A / macOS-product GLES+Vulkan parity; no Mode B; multi-window required |
| **tvOS** | App Store | Mode A **software only**. No ANGLE/MVK/KK/Vulkan ICD, no IOKit, no GPU DRM clients |
| **watchOS** | App Store | Same software policy as tvOS |
| **Android** | Google Play | Mode A graphics; Home Desktop **without root** when it ships; Wawona Swinging Bridge Mode B never Play-required |
| **macOS** | **3rd-party** (not MAS) | Mode A default (SIP OK). Mode B desktop-host OK under SIP partial\|off; never contaminate iOS/Android store artifacts |

### Store-compliance checklist (assert per store build)

1. **No Mode B artifacts** in App Store IPA / Play AAB/APK (no
   `libwayland-mac.dylib`, no inject, no `framebufferd`).
2. **No SIP disablement / root** required for any store-listed feature
   (including kmscube, waypipe, Android Home Desktop when shipped).
3. **Private API / entitlement firewall:** Mode A present = public
   Metal/UIKit/AppKit/Surface + userland DRM shims only.
4. **tvOS/watchOS:** software Mode A only. Never "fix" compliance by shipping
   GPU stacks.
5. **visionOS/iPadOS:** store Mode A meets multi-window + product GLES/Vulkan
   expectations without Mode B.
6. **Shared Nix/xcodegen:** gate Mode B + desktop-host dylibs so store schemes
   cannot link them; `verify-iland-mode-b-bundle.sh` is the evidence.
7. **macOS 3rd-party:** may ship desktop-host flavor separately; never reuse
   its packaging for iOS/Android store builds.
8. **No jailbreak language** in App Store iOS binaries or metadata.

Leak vectors to watch (from graphics-stack epic R7): manual packaging copying
the dylib; sharing iOS GPU post-build phases onto tv/watch; adding IOKit
ldflags to tv/watch; linking OpenSSH into mobile `OTHER_LDFLAGS`; shared
Settings sections without `#if` platform guards; enabling `desktopHost` on the
wrong flake attr.

## Portable KMS abstraction + IOSurface (Mode A)

`wwn-iland` is a **portable KMS-like display stack**, not "IOSurface replaces
GBM." On Apple, a backend **emulates the KMS object model** (connector, encoder,
CRTC, plane, framebuffer); **GBM and libdrm stay the client-facing ABI** and map
into that allocator/present path. IOSurface is the shared **FB / BO backing**;
page-flip triggers the present callback into the Metal layer.

| Concept | Linux-shaped ABI (clients keep) | Apple backend meaning |
|---------|----------------------------------|------------------------|
| Device | `drmOpen` / card fd | iland device → window/display session |
| Connector + mode | `drmModeGetConnector` / modes | Display or window size + Hz (must reflect real scene size) |
| CRTC | `drmModeGetCrtc` / page-flip | Metal present cadence |
| Framebuffer | `drmModeAddFB*` | IOSurface-backed FB id (must honor fourcc) |
| GBM BO | `gbm_bo_*` | Same IOSurface (unified allocator, not a second buffer world) |
| Page-flip | `drmModePageFlip` | present callback → CAMetalLayer drawable / host import |

All of these objects are runtime-only userland emulation. Even the historical
Mode B `baremetal` package name does not authorize kernel DRM/KMS: virtual
`/dev/dri` opens and ioctls terminate inside iland, while framebufferd returns
a Mach present ACK from its host-vsync path. No Wawona kernel module, kernel
patch, real DRM node, or direct KGSL path is permitted.

Minimal layers: GLES → **ANGLE → Metal**; Vulkan → **MoltenVK or KosmicKrisp →
Metal**. IOSurface is the shared backing for FB/dmabuf zero-copy (#86), not a
third GL stack. Per-target IOSurface reality + current gaps (#58 card-open, #94
format/size) are tracked in [`iland-graphics-progress.md`](iland-graphics-progress.md).

## Agent / Cursor rules

- Workspace: `.cursor/rules/wawona-iland-mode-b-desktop.mdc` (alwaysApply)
- Wawona Swinging Bridge: `.cursor/rules/wawona-swinging-bridge.mdc`
- Wawona repo: `Wawona/.cursor/rules/wawona-iland-mode-b-desktop.mdc`
- Repo DAG: `.cursor/rules/wawona-repo-dag.mdc` (+ Wawona repo mirror);
  canonical `docs/wwn-repo-dag.md`
- Platform matrix: `.cursor/rules/wawona-platform-targets.mdc`
- tvOS/watchOS GL stubs: `.cursor/rules/wwn-iland-apple-fallback.mdc`
- Agent entry: `Wawona/AGENTS.md`, `wwn-iland/AGENTS.md`
- Graphics-stack progress + capability matrix:
  [`iland-graphics-progress.md`](iland-graphics-progress.md); epic #122
