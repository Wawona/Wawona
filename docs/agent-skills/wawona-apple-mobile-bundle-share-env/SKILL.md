---
name: wawona-apple-mobile-bundle-share-env
description: >-
  FONTCONFIG_FILE and WESTON_DATA_DIR for Apple-mobile in-process weston.
  Use when weston-desktop-shell logs missing /usr/share/weston icons, unset
  FONTCONFIG, or blank panel text on iOS/iPadOS/tvOS/visionOS/watchOS.
---

# Apple mobile bundle share env

Open rule `wawona-apple-mobile-bundle-share-env` and
`docs/agent-rules/wawona-apple-mobile-bundle-share-env.md`.

Code: `Sources/WawonaApple/Shell/BundleShareEnvironment.swift`.

Hard reject: Watch-only share env while iPhone Start leaves FONTCONFIG unset.
