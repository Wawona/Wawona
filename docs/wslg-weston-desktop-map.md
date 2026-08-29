# WSLg / Weston → Wawona host integration map

Reference-only research from `vendor-research/{wslg,weston-mirror,weston-upstream}`.
**There is no Microsoft Windows / RDP / Win32 ship target.** Map RAIL/DWM semantics
onto Apple, Android, and Linux host bridges.

Authority for verification: [`.cursor/rules/wawona-host-wm-verification.mdc`](../.cursor/rules/wawona-host-wm-verification.mdc).

## Research trees (local)

| Tree | Source | Role |
|------|--------|------|
| `vendor-research/wslg` | github.com/microsoft/wslg | Host orchestration; RAIL-shell selection |
| `vendor-research/weston-mirror` | github.com/microsoft/weston-mirror | RDP/RAIL backend + `rdprail-shell` |
| `vendor-research/weston-upstream` | gitlab.freedesktop.org/wayland/weston | Upstream Weston baseline |

Cloned shallow for themed diffs; not committed (`vendor-research/` in `.gitignore`).

## Semantic map (never port RDP)

| WSLg / RAIL concept | Wawona equivalent | Where |
|---------------------|-------------------|-------|
| Host DWM chrome + shadow strip when server-owned | `Mode::ServerSide` → titled host + `hasShadow` / opaque plate | `WWNWindow applyPresentationPolicyForServerSideDecorations:YES` |
| Client paints chrome + shadow in buffer | `Mode::ClientSide` → borderless, transparent host, `content_rect` crop | same API `…:NO`; `scene.rs` content_rect |
| `should_strip_window_shadow` / geometry offset | Crop buffer to xdg `set_window_geometry` | `resolve_window_content_geometry` → `node.content_rect` |
| `RAIL_SYSCOMMAND` min/max/close/restore | Host WM ↔ xdg toplevel | `handleWindowMaximize/Fullscreen/Close…` bridges |
| `RAIL_WINDOW_MOVE` continuous geometry | Live host resize + configure every drag tick | SSD: `windowWillResize` + `injectWindowResize`; CSD: `handleWindowResizeRequested` track loop |
| `rdprail-shell` app list / activate | Machines + foreign-toplevel / activation (desktop hosts) | P3; macOS+Android Desktop only |
| VAIL shared pixels | IOSurface / dmabuf zero-copy | ISSUE #86 (P3) |
| RDP transport / FreeRDP / mstsc | **Forbidden** | - |

## Decoration policy (Smithay)

Keep three-way policy in [`decoration.rs`](../src/core/wayland/xdg/decoration.rs) /
[`extension_handlers.rs`](../src/core/wayland/xdg/extension_handlers.rs):

| Policy | Behavior |
|--------|----------|
| **Force SSD** (`ForceServer`) | Always configure `ServerSide`; host chrome required |
| **PreferServer / PreferClient** | Honour client `zxdg_toplevel_decoration_v1.set_mode` |
| Weston-family special cases | CSD when not Force (existing rules) |

WSLg “host chrome feel” applies whenever mode is **ServerSide** (Force **or**
client-requested), not “always Force SSD.”

## Platform matrix

| Platform | SSD host chrome | CSD transparent | Live resize | Multi-window | Desktop/anowaW |
|----------|-----------------|-----------------|-------------|--------------|----------------|
| macOS | titled + shadow | borderless + clear Metal/AppKit | SSD+CSD mid-drag | native | allowed |
| iOS phone | fill-primary chrome/policy | clear UIKit/Metal | required | tabs/focus | **forbidden** |
| iPadOS | required | required | required | multi-scene **required** | **forbidden** |
| visionOS | macOS parity clients | required | required | multi-scene **required** | **forbidden** |
| tvOS | constrained | limited OK | required | N/A | **forbidden** |
| watchOS | constrained | limited OK | required | N/A | **forbidden** |
| Android | required | clear Vulkan/GL | required | freeform as OS allows | allowed |
| Linux | host WM | host WM | required | as DE allows | N/A |

## Maximize / fullscreen / minimize / Focus (host WM policy)

UIKit and Android own the host surface; Wawona cannot offer macOS-style floating
zoom frames. `PlatformCapabilities.hostWindowManagerPolicy` is authoritative.

| Platform | Maximize | Fullscreen | Minimize | Focus (Machines) |
|----------|----------|------------|----------|------------------|
| **macOS** | AppKit `zoom:` + xdg maximized | `toggleFullScreen:` + xdg fullscreen | AppKit miniaturize (Dock) | `orderFront` / deminiaturize |
| **iOS phone / tvOS** | **Fill-primary**: configure to compositor bounds + xdg maximized | Same fill + xdg fullscreen (status bar already deferred in-session) | Hide compositor → Machines; **session stays alive** | Reveal compositor; do not relaunch |
| **iPadOS / visionOS** | Fill active host `UIWindow`/scene + xdg maximized | Same | Hide primary + per-client host windows → Machines | Unhide host windows + reveal |
| **Android** | Fill logical output + xdg maximized | Same | `showMachinesHome=true`; session stays | `focusMachine` → hide Machines home |
| **watchOS** | No-op stub | No-op stub | No-op stub | N/A |
| **Linux** | GTK maximize | GTK fullscreen | GTK iconify | DE focus |

**iOS decision (cannot resize host windows):** treat maximize and fullscreen as
the same host geometry (fill-primary). Advertise distinct xdg states so clients
that branch on `maximized` vs `fullscreen` still see the bit they requested.
Unmaximize/unfullscreen clear those bits but keep fill-primary size. There is
no pre-max floating geometry to restore. Minimize must never terminate the
client; Focus is the restore path.

## Issue map

| Issue | Theme | Phase |
|------:|-------|-------|
| [#53](https://github.com/Wawona/Wawona/issues/53) | styleMask thrash / CSD↔SSD | P1 |
| [#94](https://github.com/Wawona/Wawona/issues/94) | iOS edge-to-edge | P2 |
| [#52](https://github.com/Wawona/Wawona/issues/52) | close/teardown | P2 |
| [#88](https://github.com/Wawona/Wawona/issues/88) [#63](https://github.com/Wawona/Wawona/issues/63) [#80](https://github.com/Wawona/Wawona/issues/80) | waypipe remote resize | P2 |
| [#86](https://github.com/Wawona/Wawona/issues/86) | IOSurface dmabuf | P3 |
| [#84](https://github.com/Wawona/Wawona/issues/84) [#65](https://github.com/Wawona/Wawona/issues/65) | multi-window / tabs | P2 |
| [#83](https://github.com/Wawona/Wawona/issues/83) [#59](https://github.com/Wawona/Wawona/issues/59) | WM / resize polish | P1-P2 |
| [#32](https://github.com/Wawona/Wawona/issues/32) [#103](https://github.com/Wawona/Wawona/issues/103) | Desktop/launcher | P3 macOS+Android only |

## Host ↔ client size sync (state machine)

**Authority:** [`.cursor/rules/wawona-host-client-size-sync.mdc`](../.cursor/rules/wawona-host-client-size-sync.mdc).

**Implementation:** `src/core/window/size_authority.rs`. Permanent SM.
States: `AwaitingFirstCommit` → `Client` ↔ `Host { requested }`.
Invariant: exactly one writer of agreed size. Unit test
`ping_pong_impossible_during_host_drive` must stay green.

| Reference | Behavior encoded |
|-----------|------------------|
| OWL `OwlSurface.commit` | `Client`: host follows buffer |
| OWL / xdg `configure(0,0)` | `AwaitingFirstCommit` then first buffer → `Client` |
| Smithay serial/ack | `Host` ignores lagging commits while pending serial ≠ 0 |
| WSLg/RAIL / waypipe (ref) | `Host` during drag; settle on match or client refuse |
| weston-flower / smoke | Refuse → `Client` at **200x200** |
| weston-simple-shm / simple-egl | Preferred square (250x250); never inject display size on map. Same host policy as flower. |

Research trees: `vendor-research/{owl,wslg,weston-upstream,weston-mirror}`
(gitignored; clone locally for diffs).

## Implementation hotspots

| Concern | Path |
|---------|------|
| CSD live resize | `WWNCompositorBridge.m` `handleWindowResizeRequested` → `injectWindowResize` each tick |
| SSD live resize | `WWNWindow.m` `windowWillResize` + `inLiveResize` debounce 0 |
| Host↔client size | `shell_handler` 0×0 seed; `surfaces.rs` OWL accept; macOS `handleWindowSizeChanged` |
| Live-resize authority | `Window.size_authority_host` + scene stretch only while set (#111) |
| SSD/CSD policy | `decoration.rs`, `applyPresentationPolicyForServerSideDecorations` |
| Metal CSD plate | `WWNIlandPresenter` opaque=NO + blend; iOS `_ensureMetalPresentationLayer` |
| content_rect crop | `scene.rs` + presenters (`contentsRect` / UV crop) |

## Verification (per phase)

Do not mark a phase complete until the acceptance matrix in the plan is green:
Force SSD **ON** and Force SSD **OFF** (CSD + client-requested SSD), mid-drag
live resize evidence, compile matrix for every required platform.

Tool loop: wwn-mcp → compile → unit → agent-device → Instruments → LLDB on fail.
