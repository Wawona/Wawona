---
name: wawona-global-settings-exclusive
description: Exactly one Global Wawona Settings host per platform. Prefer OS Settings when product-usable. Never dual OS + in-app hubs.
---

# Global Settings exclusivity

Open the rule: `wawona-global-settings-exclusive` /
`docs/agent-rules/wawona-global-settings-exclusive.md`.

## Do

- macOS → PrefPane only
- iOS / iPadOS → Settings.bundle only
- Watch prefs → Settings-Watch.bundle on iPhone Watch app
- tvOS / visionOS → in-app only
- Android Play → Compose + `APPLICATION_PREFERENCES` only (until OS inject is product-usable)

## Hard rejects

- In-app Global Settings **and** PrefPane / Settings.bundle on same target
- PrefPane missing → full in-app duplicate catalog
- Gemini toy keys / `group.com.wawona.global`
