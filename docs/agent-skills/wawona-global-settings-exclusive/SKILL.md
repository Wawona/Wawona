---
name: wawona-global-settings-exclusive
description: Exactly one Global Wawona Settings host per platform. In-app only. Never OS PrefPane / Settings.bundle / App Info Preferences.
---

# Global Settings exclusivity

Open the rule: `wawona-global-settings-exclusive` /
`docs/agent-rules/wawona-global-settings-exclusive.md`.

## Do

- macOS / iOS / iPadOS / tvOS / visionOS → in-app Machines sidebar catalog
- watchOS → in-app `WatchGlobalSettingsView`
- Android → Compose `SettingsDialog` only
- Linux → in-app libadwaita dialog
- Store prefs in the app container (`UserDefaults.standard` / SharedPreferences)

## Hard rejects

- PrefPane / Settings.bundle / Settings-Watch.bundle
- System Settings or Settings.app as the Settings entry
- `APPLICATION_PREFERENCES` as a second host
- Gemini toy keys / `group.com.wawona.global`
