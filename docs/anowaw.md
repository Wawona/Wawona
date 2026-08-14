# anowaW — host-app → Wayland bridge

> **Public subset** for wawona.io. anowaW is **not** Desktop/LockScreen
> replacement and is **not** MediaProjection-as-desktop.

Status: **planned / coming soon** (in development).

## What it is

anowaW is an **application bridge**: run **macOS, Android, or iOS** apps as
Wayland clients inside a Wawona desktop environment (including nested
compositors such as niri and weston). The intended path is a zero-copy (or near
zero-copy) surface bridge for HID, resize, and compositing of UIKit / AppKit /
Android window surfaces onto Wayland surfaces so host apps tile beside other
Wayland clients.

## What it is not

- Not Desktop Replacement
- Not LockScreen Replacement
- Not “screen mirroring via MediaProjection” as the product definition

Desktop / LockScreen docs: [`iland-mode-a-b-desktop.md`](iland-mode-a-b-desktop.md).

## Platforms

| Platform | Gate |
|---|---|
| macOS | planned (Mode A + Mode B) |
| Android | planned (Mode A + Mode B) |
| iOS | planned (Mode A in store app; Mode B via `repo.wawona.io` only) |
| iPadOS / tvOS / watchOS / visionOS / Linux | forbidden |

## Mode A vs Mode B

| | Mode A | Mode B |
|---|---|---|
| Store / Play | Ships in App Store / Play builds | **Forbidden** in store IPA / Play AAB |
| macOS | Store-safe / notarized methods as available | Bundled on 3rd-party macOS; needs partial SIP (system debugging), same bar as Desktop `.dylib` |
| Android | Play-approved bridge methods | Privileged / root paths outside Play requirements |
| iOS | Mode A only inside the App Store Wawona app | Jailbreak tweak from **`repo.wawona.io`** (add as Sileo source): UIKit apps as Wayland clients under nested Wawona |

**App Store / TestFlight UI and strings must never mention jailbreak.** Website
and `repo.wawona.io` may describe Mode B.

## iOS Mode B sketch (`repo.wawona.io`)

A jailbreak tweak that presents UIKit apps as Wayland clients on a nested
Wayland compositor hosted by Wawona on iOS, so iOS apps can tile beside other
Wayland clients inside native ports such as niri. Distributed only from
`repo.wawona.io`, never from the App Store IPA.

## Agent rules

- Workspace: `.cursor/rules/wawona-anowaw.mdc`
- Platform matrix: `.cursor/rules/wawona-platform-targets.mdc`
- Gates: `Sources/WawonaModel/PlatformCapabilities.swift`
