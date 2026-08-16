# Wawona Swinging Bridge

> **Public subset** for wawona.io. Formerly **anowaW** (“Wawona” reversed).
> **Not** Desktop/LockScreen replacement and **not** MediaProjection-as-desktop.

Status: **planned / coming soon** (Mode A and Mode B designed; neither shipping).

Repo: [`Wawona/Wawona-Swinging-Bridge`](https://github.com/Wawona/Wawona-Swinging-Bridge)
(flake input name `wwn-swinging-bridge`; historical Nix recipe key may still be
`anowaw` until recipes finish renaming).

## What it is

**Wawona Swinging Bridge** is the **Cocoa / Android / (future) UIKit → Wayland
application bridge**. It turns host apps into Wayland clients so they can be
composited, resized, focused, and driven with HID like any other client.

Primary remote story:

```text
macOS AppKit / Android app  →  Swinging Bridge  →  waypipe-rs (wwn-waypipe)
        →  Linux Wayland compositor (niri, weston, …)
```

The Linux side sees a normal Wayland client: buffers, `xdg` geometry, seat
pointer/keyboard/touch, resize and placement. Fully protocol-aware, not a
dumb video stream of the whole device.

Local story (same bridge): attach to a **nested** compositor inside Wawona
(Weston/niri) so host apps tile beside Linux clients on-device.

## What it is not

- Not [Desktop Replacement](iland-mode-a-b-desktop.md)
- Not LockScreen Replacement
- Not “mirror the phone/desktop with MediaProjection as the product”
- Not a [VM or container](vms-containers.md)

Desktop replacement becomes *easier* once Swinging Bridge works (e.g. Android
Default Home App = Wawona, while individual Android apps still appear as Wayland
surfaces inside niri). That home/DE path is still Desktop/LockScreen. Separate.

## Platforms

| Platform | Gate | Notes |
|---|---|---|
| **macOS** | ⏳ planned Mode A + Mode B | Cocoa/AppKit → Wayland (+ waypipe to Linux) |
| **Android** | ⏳ planned Mode A + Mode B | App surfaces → Wayland (+ waypipe to Linux) |
| **iOS / iPadOS** | ⏳ planned **Mode B only** | UIKit → Wayland via jailbreak / `repo.wawona.io`; **not** in App Store IPA |
| tvOS / watchOS / visionOS / Linux | ❌ forbidden | |

## Mode A vs Mode B

Neither mode is implemented yet. Both must be designed in from day one; Mode B
never ships inside App Store / Play artifacts.

| | **Mode A** (store / Play compliant) | **Mode B** (privileged) |
|---|---|---|
| Intent | App Store / Play-approved capture/stream-style bridge | Full privileged surface bridge |
| macOS | Store-safe / notarized methods (closer to streaming) | Partial SIP / system-debugging bar (same class as Desktop `.dylib`) |
| Android | Play-approved path (stream-like) | Root / privileged paths outside Play |
| iOS / iPadOS | **Not offered** in the store app | Jailbreak / Sileo Mode B IPA + tweaks from `repo.wawona.io` |
| Store binary | May ship Mode A when ready | **Forbidden** |

App Store / TestFlight / Play copy must **never** mention jailbreak or Mode B.

## waypipe

Forwarding to a remote Linux compositor uses **`wwn-waypipe`** (waypipe-rs):
socket/FD forwarding so the remote compositor owns the Wayland connection.
HID and resize round-trip through that client connection.

## Agent rules

- `.cursor/rules/wawona-swinging-bridge.mdc` (replaces `wawona-anowaw`)
- Platform matrix: `.cursor/rules/wawona-platform-targets.mdc`
- Gates: `Sources/WawonaModel/PlatformCapabilities.swift` (`swingingBridgeGate`)
