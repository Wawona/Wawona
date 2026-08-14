# anowaW — host-app → Wayland bridge

**anowaW is not Desktop Replacement and not LockScreen Replacement.** Those are
a separate product surface (host DE / greeter). anowaW is an **application
bridge**: run macOS, Android, or iOS apps as Wayland clients inside a Wawona
desktop (including nested compositors such as niri / weston).

Status: **⏳ planned / coming soon** (in development). Do not document it as
shipping, and do not equate it with MediaProjection “screen mirror” UX.

## Goal

Zero-copy (or near zero-copy) surface bridge: capture HID, resize, and
compositing of **UIKit / AppKit / Android** window surfaces onto a Wayland
surface so host apps tile beside other Wayland clients.

## Platforms

| Platform | anowaW |
|---|---|
| macOS | ⏳ planned (Mode A + Mode B) |
| Android | ⏳ planned (Mode A + Mode B) |
| iOS / iPadOS | ⏳ planned (Mode A in store app; Mode B via `repo.wawona.io` only) |
| tvOS / watchOS / visionOS / Linux | ❌ forbidden |

## Mode A vs Mode B (anowaW — do not confuse with iland Mode A/B)

| | Mode A | Mode B |
|---|---|---|
| Intent | App Store / Play–approved methods | Privileged / alternate distribution |
| Store / Play | **Ships** in store builds | **Forbidden** in App Store IPA and Play AAB/APK |
| macOS | Store-safe / notarized path as available | Bundled on 3rd-party macOS; needs **partial SIP** (system debugging / Debugging Restrictions disabled), same bar as Desktop `.dylib` |
| Android | Play-approved bridge (not “Desktop = MediaProjection”) | Root / privileged paths when offered outside Play requirements |
| iOS / iPadOS | Mode A only inside the App Store Wawona app | Jailbreak tweak from **`repo.wawona.io`** (Sileo source): UIKit apps as Wayland clients under nested Wawona / niri |

**App Store / TestFlight copy and in-app UI must never mention jailbreak.**
Website docs and `repo.wawona.io` may describe Mode B.

## Hard rules

1. Never call anowaW “Desktop Replacement”, “LockScreen”, or “MediaProjection
   desktop”. Desktop/LockScreen is a different feature.
2. Never ship anowaW Mode B artifacts or copy in App Store / Play products.
3. macOS may bundle Mode B (3rd-party); engage only when system debugging /
   partial SIP allows it.
4. iOS / iPadOS Mode B lives only as a tweak distributed from `repo.wawona.io`,
   not inside the App Store IPA. Treat iPhone and iPad the same for anowaW.
5. Gate in `PlatformCapabilities` / Android prefs as **planned** until ready;
   keep store iOS Desktop/LockScreen **forbidden** in-app.

Canonical website: `wawona.io` docs for Desktop vs anowaW. Repo prose:
`Wawona/docs/anowaw.md`, `Wawona/docs/iland-mode-a-b-desktop.md` (Desktop only).
