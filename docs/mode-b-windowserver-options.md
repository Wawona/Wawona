# Mode B: three WindowServer options

> **Not** IOWatchdog Path A / Path B. Those are how we cover the kernel
> watchdog before Classic may unload Apple `watchdogd`. This file is only
> about **Apple WindowServer** while Desktop Mode B is engaged.
>
> Plain language: how much of macOS’s normal window system stays around
> when Wawona takes over (or probes) the machine.

Status: **Classic** and **KEEP_WS** are implemented (Classic own-display
proven with kmscube). **Path C** is **planned** (after Mode B multi-TTY).
Do not ship Path C UI until it is implemented and safety-reviewed.

## The three options

| Option | WindowServer | What the user sees | Why it exists |
|---|---|---|---|
| **Classic** (bootout) | Unloaded for the session | Wawona owns the panel (cube, Mode B TTY, nested compositor) | Full Desktop Replacement |
| **KEEP_WS** | Left running normally | Normal macOS Aqua stays up | Safe probe / inject while Aqua lives |
| **Path C** (parked) | Process kept, display ownership parked / suspended (planned) | Wawona owns the panel; Cocoa still has a live WindowServer to talk to | Let **Wawona Swinging Bridge** host AppKit apps without rewriting every SkyLight/AppKit path |

```text
                    ┌─────────────────────────────┐
                    │  IOWatchdog Path A or B     │
                    │  (safety coverage only)     │
                    └─────────────┬───────────────┘
                                  │
          ┌───────────────────────┼───────────────────────┐
          ▼                       ▼                       ▼
   Classic bootout            KEEP_WS                 Path C (planned)
   WS gone; panel =           WS + Aqua up;           WS alive but parked;
   Mode B present             probe inject only       panel = Mode B;
                                                      Cocoa apps → Bridge
```

## Classic (bootout)

- Helper unloads WindowServer after IOWatchdog Disable ACK.
- `framebufferd` presents Mode B clients (kmscube, Mode B TTY, weston/niri).
- Escape: Settings/CLI disengage, or Ctrl+Alt+Backspace (Mode B chord) →
  restore Aqua.
- Best for: “replace the Mac desktop for this session.”
- Cost: Cocoa/AppKit apps that need WindowServer do not run unless fully
  bridged or rehosted. That is why Path C exists as a future option.

## KEEP_WS

- WindowServer and Aqua stay up. File stamp: `/tmp/wawona-modeb-keep-ws`.
- CLI: `Wawona --mode-b-probe` (and related KEEP_WS engage).
- Does **not** claim the panel. Use to prove Mach inject / framebufferd
  register without taking the screen.
- Never unload Apple `watchdogd` without sticky ACK (same hard forbids as
  Classic).

## Path C (parked WindowServer) — planned

**Intent:** Wawona draws on the panel (Desktop own-display) while Apple
WindowServer remains a living process in the background (suspended or
otherwise not owning the display). Cocoa apps can still speak AppKit /
SkyLight to that process, so **Wawona Swinging Bridge** can turn them into
Wayland clients without a full AppKit/SkyLight rewrite.

**Not implemented.** Track after Mode B multi-TTY lands. Design must:

1. Keep product split: Path C is a **Desktop display option**, not “Swinging
   Bridge is Desktop.” Bridge remains [`swinging-bridge.md`](swinging-bridge.md).
2. Never use sticky `launchctl disable` / `unload -w` on WindowServer (same
   restore panic class as Classic incidents).
3. Reuse IOWatchdog Path A/B rules unchanged; Path C does not replace them.
4. Define park/suspend vs unload so logout and `--restore-aqua` always return
   a healthy Aqua login without force reboot.
5. Gate in Settings only when Path C is proven; until then Classic + KEEP_WS
   only.

**Why friends suggest it:** full Classic bootout forces either “no Cocoa
apps” or heavy patching. Parking WindowServer is the middle path for
Bridge + Desktop on the same session.

## Do not confuse names

| Phrase | Means |
|---|---|
| **iland Mode A / Mode B** | In-window present vs macOS Desktop dylib |
| **IOWatchdog Path A / Path B** | Two ways to cover the kernel watchdog |
| **Classic / KEEP_WS / Path C** | Three WindowServer strategies (this file) |
| **Wawona Swinging Bridge Mode A / Mode B** | Store vs privileged **app bridge** (separate product) |

## Related

- Desktop engage / dylib: [`iland-mode-a-b-desktop.md`](iland-mode-a-b-desktop.md)
- Watchdog safety: [`agent-rules/wawona-mode-b-watchdog-safety.md`](agent-rules/wawona-mode-b-watchdog-safety.md)
- Swinging Bridge: [`swinging-bridge.md`](swinging-bridge.md)
- Cursor rule: `.cursor/rules/wawona-iland-mode-b-desktop.mdc`
