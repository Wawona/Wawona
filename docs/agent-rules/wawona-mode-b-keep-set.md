# Mode B keep-set (P5)

Mode B artifacts stay **separate** from App Store / Play Mode A. Never merge
JIT, IOMFB, ElleKit, or Desktop engage into store IPA/AAB.

## Keep shipping and testing

| Artifact | Channel | Notes |
|---|---|---|
| macOS `libwayland-mac.dylib` + igetty / Classic DRM | `.#wawona-macos-desktop-host` | SIP fully disabled; watchdog safety |
| iOS tipa | TrollStore | JIT + IOMFB Desktop/LockScreen; no ElleKit |
| iOS Sileo `.deb` | `repo.wawona.io` | Full Mode B + Swinging Bridge + host APT |
| Android root | outside Play | Mode B engines |

## Planned tracks (do not block P0–P3)

- Desktop / LockScreen replacement (macOS + Android; iOS via tipa/Sileo)
- Wawona Swinging Bridge (macOS/Android Mode A+B; iOS Mode B only)

## Hard rejects

- Mode B symbols or jailbreak copy in store IPA
- Ship: beta for tipa / Mode B deb
- Conflating iland macOS Desktop dylib with iOS tipa or Swinging Bridge

Canonical: `docs/mode-a-b.md`, `wawona-ios-mode-b-channels`,
`wawona-iland-mode-b-desktop`, `wawona-swinging-bridge`.
