# Wawona Swinging Bridge (formerly anowaW)

**Not Desktop Replacement and not LockScreen Replacement.** Those are a
separate product surface (host DE / greeter). Swinging Bridge is an
**application bridge**: macOS Cocoa, Android, and (future / Mode B) UIKit apps
become Wayland clients — locally in Wawona or forwarded with **waypipe-rs**
onto a Linux compositor with real resize/HID.

Status: **⏳ planned / coming soon**. Mode A and Mode B are designed; **neither
is implemented**. Do not document as shipping. Do not equate with
MediaProjection “screen mirror” UX.

Repo: `github.com/Wawona/Wawona-Swinging-Bridge` (renamed from `wwn-anowaW`).
Flake input: `wwn-swinging-bridge`. Legacy Nix recipe / C ABI keys may still
say `anowaw` / `anowaw_*` until fully renamed.

## Goal

```text
macOS / Android (/ iOS Mode B) app
    → Swinging Bridge
    → waypipe-rs (wwn-waypipe) or nested local Wayland
    → Linux / nested compositor (niri, weston, …)
```

Protocol-aware Wayland client (buffers, xdg, seat) — not whole-device video.

Helps Desktop later (e.g. Android home = Wawona while apps still appear as
Wayland surfaces in niri) — that home/DE path remains Desktop/LockScreen.

## Platforms

| Platform | Swinging Bridge |
|---|---|
| macOS | ⏳ Mode A + Mode B |
| Android | ⏳ Mode A + Mode B |
| iOS / iPadOS | ⏳ **Mode B only** (`repo.wawona.io` / jailbreak) — **forbidden** in App Store IPA |
| tvOS / watchOS / visionOS / Linux | ❌ forbidden |

## Mode A vs Mode B

| | Mode A | Mode B |
|---|---|---|
| Intent | Store/Play–approved (stream-like) | Privileged full bridge |
| Store / Play | May ship when ready | **Forbidden** in IPA/AAB |
| macOS | Store-safe / notarized | Partial SIP (Debugging Restrictions), same bar as Desktop `.dylib` |
| Android | Play-approved | Root / privileged outside Play |
| iOS / iPadOS | Not in store app | Jailbreak / Sileo Mode B |

**App Store / TestFlight / Play copy must never mention jailbreak.**

## Hard rules

1. Never call Swinging Bridge “Desktop Replacement”, “LockScreen”, or
   “MediaProjection desktop”.
2. Never ship Mode B artifacts or copy in App Store / Play products.
3. iOS/iPadOS: Mode B only — no Mode A Swinging Bridge in the store IPA.
4. Do not conflate with iland macOS Desktop `.dylib` or iOS Mode B compositor IPA.
5. Gate: `PlatformCapabilities.swingingBridgeGate` (planned on macOS/Android;
   forbidden on iOS family in store builds).

Canonical: `Wawona/docs/swinging-bridge.md`, wawona.io `/docs/swinging-bridge/`.
