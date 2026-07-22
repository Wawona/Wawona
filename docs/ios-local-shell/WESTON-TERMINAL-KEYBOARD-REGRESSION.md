# weston-terminal blackscreen + size mismatch (keyboard / size work)

LLM-oriented postmortem. Use this when changing iOS soft/hard keyboard policy,
xdg `configure(0,0)` seeding, in-process weston-terminal sizing, or
`followHostSize` on iOS.

## Symptoms

### A. Blackscreen (PTY alive, no GUI)

- weston-terminal **PTY worked**: typing reached in-process `wwn-zsh`, commands ran.
- **No GUI**: black compositor surface, no terminal chrome/text.
- Host tick: `Buffers popped: 0, scene nodes: 1, cache size: 0`.
- Startup overlay could stick until soft OSK / first-responder was deferred.

### B. Loads but does not match iOS compositor size

- GUI paints (`Buffers popped: 1`, `IOS present via frameView`).
- Terminal appears as a **floating** CSD window with black gutters vs the
  container (e.g. container `402×778`, client preferred ~80×25 cells or
  cell-snapped `386×730` / commit `398×763`).
- Screenshot: title bar “Weston Terminal” inset in a larger black host view.

## Verdict

Keyboard / size-authority work did **not** break the PTY. It changed who owns
toplevel size and when the soft OSK may become first responder. Combined with
historical terminal patches and toytoolkit’s `configure(0,0)` rules, that
produced (A) no SHM buffer, then after paint was restored (B) a floating grid
that does not fill the phone compositor.

## Causal chain (why keyboard work triggered it)

```
┌─────────────────────────────────────────────────────────────────────────┐
│ A. SizeAuthority / OWL: new toplevel configure is 0×0 (client decides) │
│    Host must NOT inject wl_output size on map for flower/smoke 200×200.│
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
┌───────────────────────────────▼─────────────────────────────────────────┐
│ B. iOS WindowCreated (first native toplevel):                          │
│    SetWindowActivatedSilent only — NO injectWindowResize fill.         │
│    Soft OSK / accessory FR deferred until first Wayland frame.         │
│    (Goal: UIKit keyboard animation must not stall configure/ticks.)    │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
┌───────────────────────────────▼─────────────────────────────────────────┐
│ C. weston-terminal iOS patch (historical):                             │
│    Skipped terminal_resize(80,25) at create — “wait for configure”.    │
└───────────────────────────────┬─────────────────────────────────────────┘
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Toytoolkit window.c xdg_toplevel_handle_configure:                     │
│   if (width > 0 && height > 0) schedule_resize(...);                   │
│   else if (saved_allocation non-zero) schedule_resize(saved);          │
│   else /* configure(0,0) with no preferred size → NO-OP */             │
└───────────────────────────────┬─────────────────────────────────────────┘
                                ▼
        allocation stays 0×0 → redraw commits 0×0 → SizeAuthority
        ignore_non_positive_commit → Buffers popped: 0 → blackscreen
        (PTY/grid path independent → shell still accepts input)
```

Soft/hard keyboard policy did **not** clear SHM buffers. It **removed the
host-side fill configure** and deferred FR; terminal patches had removed the
client preferred size. Net: no resize_handler, no buffer.

### Size mismatch after paint returned

Restoring `terminal_resize(80,25)` (or pace fallback `80×24`) makes toytoolkit
honor `configure(0,0)` via `saved_allocation` → floating ~80-col window.

Even when the host injects fill `402×778`:

1. Stock weston-terminal **cell-snaps** floating windows down (e.g. `386×730`).
2. CSD geometry → commit slightly smaller than container (`398×763`).
3. `handleWindowSizeChanged` used to set `followHostSize = (commit ≥ 90% host)`.
   A first commit below 90% (classic 80×25) **cleared** map-time `followHostSize`,
   so present **centered** the buffer instead of full-bleed.

Keyboard deferral of OSK made the stuck splash obvious; it did not invent the
0×0 allocation. Size mismatch is the same policy stack plus cell-snap +
followHost heuristic.

### Mapping to keyboard / size plan changes

| Change | Intent | Effect on terminal |
|---|---|---|
| `configure(0,0)` seed + no fill on first toplevel | Keep flower/smoke 200×200; OWL client-preferred | Terminal never got non-zero host configure |
| Defer `activateKeyboard` / FR until first frame | Soft OSK must not stall ticks / configure | Exposed paint failure (splash stuck); did not cause 0×0 |
| Soft OSK from TI-v3 / terminal synthesis | Phosh-style IME | Orthogonal; typing used PTY inject |
| Historical skip of `terminal_resize` on Apple mobile | Wait for host configure before grid | Removed only preferred size toytoolkit honors on 0×0 |
| ClientCommit `followHost = fillsHost≥90%` | Demos stay client-sized | Cleared shell followHost on first small commit → gutters |

## Evidence (logs)

Healthy after fill + honor-host-configure (excerpt):

```
[BRIDGE] First native toplevel window 1 — immediate activate + fill configure 402x778 (shell)
[COMPOSITOR] send_toplevel_configure: … size=402x778 …
weston-terminal: surface size 402x778 for grid CxR (host configure)
weston-terminal: resize_handler 402x778 (configure received)
[BRIDGE] iOS ClientCommit SizeChanged window=1 402x778 followHost=yes hostLocked=no
[TICK] Buffers popped: 1, scene nodes: 1, cache size: 1
[RENDER] IOS present via frameView: … frame=0,0 402x778 …
```

Broken blackscreen pattern:

```
[STATE] SizeAuthority hold: … ignore_non_positive_commit committed=0x0
[TICK] Buffers popped: 0, scene nodes: 1, cache size: 0
# no "IOS present via frameView"
# no "resize_handler … (configure received)" / no non-zero surface size
```

Broken size-mismatch pattern:

```
# fill missing OR cell-snap / 80×25 preferred:
weston-terminal: surface size 650x410 for grid 80x25   # or 386x730 without "(host configure)"
[BRIDGE] iOS ClientCommit SizeChanged … followHost=no
[RENDER] IOS present … frame=…  (centered, not 0,0 container)
# screenshot: floating CSD window in black host view
```

Note: `still waiting for configure (iter 50…300)` can appear for ~1.2s while
the client pumps before `ios_configure_count` increments; host may already have
sent `send_toplevel_configure`. Prefer `(host configure)` / `ClientCommit` lines
over the wait spam alone.

## Fixes applied

1. **Client (`wwn-weston` `patch-terminal.py`)**
   - Keep `terminal_resize(20,5)` / `(80,25)` on Apple mobile (preferred ≠ 0×0).
   - `terminal_ios_apply_surface_size` / pace fallback so SHM never stays 0×0.
   - `terminal_ios_apply_configure_size`: on Apple mobile, **widget_set_size =
     exact xdg configure pixels** (no floating cell-snap gutters).
   - Font metric fallbacks when fontconfig fails.

2. **Host (`WWNCompositorBridge.m` iOS)**
   - Bundled shells (`weston-terminal` / `wayland-terminal` / `foot`): inject
     fill configure to container bounds; `followHostSize = YES`; optional
     `syncHostMaximized` so stock weston skips floating snap.
   - Prefs fallback `NativeClientId` if `activeIOSBundledClientId` is empty at
     WindowCreated; title-based late fill for “Weston Terminal”.
   - ClientCommit must **not** clear an already-set `followHostSize`.
   - Demos still client-preferred 0×0 (no fill inject).

3. **Present (`WWNCompositorView_ios.m`)**
   - When `hostLocked || followHostSize`, presentation frame is full container
     (CSD crop must not leave gutters).

## Invariants (do not regress)

1. **Never** inject output-sized configure on map for weston-flower / smoke /
   simple-shm (fixed or client-driven demo sizes).
2. Soft OSK Expand stays tied to committed TI-v3 / terminal synthesis — not
   mere window focus; do not `becomeFirstResponder` before first buffer.
3. weston-terminal / foot on iOS/iPadOS should **fill** the compositor view;
   grid tracks host layout (`followHostSize` + fill configure / layout inject).
4. PTY working ≠ GUI working; always check `Buffers popped` / `IOS present`.
5. Do not let ClientCommit heuristics turn shell `followHostSize` back off.

## Touch points

| Layer | Path |
|---|---|
| Toytoolkit configure | weston `clients/window.c` `xdg_toplevel_handle_configure` |
| Terminal patches | `wwn-weston/.../terminal-patches/patch-terminal.py` |
| iOS map / fill | `WWNCompositorBridge.m` `handleWindowCreated` (iOS) |
| ClientCommit followHost | `WWNCompositorBridge.m` `handleWindowSizeChanged` (iOS) |
| Present full-bleed | `WWNCompositorView_ios.m` present path (`hostOwnsPresent`) |
| Size SM | `src/core/window/size_authority.rs`, rule `wawona-host-client-size-sync` |
| Soft OSK | `WWNCompositorView_ios.m` `applyHostKeyboard*` / `armHostKeyboardAfterFirstFrame` |
| TI brain | `src/core/wayland/ext/text_input.rs` |

## Quick verification

```bash
# Sim build + install Wawona-iOS; prefs:
#   scripts/agent-device-set-client-ios.sh weston-terminal <UDID>
# Console (keep attached; do not steal with a second launcher):
xcrun simctl launch --console-pty <UDID> com.aspauldingcode.Wawona
# After Start → weston-terminal, expect:
#   fill configure <containerW>x<containerH> (shell)
#   surface size … (host configure)
#   ClientCommit … followHost=yes
#   Buffers popped: 1  and  IOS present via frameView with frame ≈ container
# Screenshot: terminal chrome edge-to-edge in the compositor view (no floating gutters).
```

Rebuild note: simulator weston is `nix build .#weston-ios-gl-sim --override-input wwn-weston path:…/wwn-weston`; copy `libweston-terminal.a` into the `.nix-deps/lib/*weston-ios*` hash Xcode links before relinking the app.
