# Global Settings exclusivity

Exactly **one** Global Wawona Settings interface per platform target. That host
is **inside the Wawona app**. The user never leaves the app for Global Settings.

OS System Settings, PrefPane, Settings.bundle, Settings-Watch.bundle, and
Android App Info Preferences are **retired** as Global Settings hosts. Do not
rebuild them.

## Matrix

| Target / band | Sole Global Settings host |
|---|---|
| macOS | In-app Machines sidebar catalog (`WWNSettingsSectionView`) |
| iOS / iPadOS | In-app Machines sidebar catalog |
| watchOS | In-app `WatchGlobalSettingsView` on the wrist |
| tvOS / visionOS | In-app Machines sidebar catalog |
| Android | In-app Compose `SettingsDialog` |
| Linux | In-app libadwaita settings dialog |

Storage is the **app container**: `UserDefaults.standard` on Apple,
app `SharedPreferences` on Android. Never a PrefPane suite
(`com.aspauldingcode.Wawona`) and never `group.com.wawona.global`.

## Schema

Rust `settings_catalog` + Swift `GlobalSettingsCatalog` + `wawona.pref.*`.
Never invent Gemini toy keys.

## Not Global Settings (may stay separate)

Machine editors, one-shot actions (Watch send, import, log copy). They must
**not** become a second Global Settings hub with a different Display / Input
catalog.

Sidebar Destinations may still list Desktop / About / Dependencies as part of
the same in-app catalog (`visibleSections`).

## Hard rejects

- PrefPane / `Settings.bundle` / `Settings-Watch.bundle` as a Global Settings host
- `x-apple.systempreferences:…Wawona.prefPane` or `UIApplication.openSettingsURLString`
  as the Settings entry
- `ACTION_APPLICATION_PREFERENCES` / `SettingsPreferenceService` as a second host
- Dual OS Settings inject **and** in-app Global Settings for the same catalog
- Desktop / Mode B / jailbreak copy in any retired Settings.bundle

Cursor rule: `.cursor/rules/wawona-global-settings-exclusive.mdc`.
Product: `docs/settings.md`. RAG: `wwn-mcp/knowledge/wawona/global-settings-exclusive.md`.
Verify: `Wawona/scripts/verify-settings-bundle-keys.py`.

## History (do not revive)

Introducing OS hosts: `8f2335a` (macOS PrefPane + iOS Settings.bundle),
later Watch redirect / Settings-Watch.bundle, Android App Info Preferences.
Superseded by in-app-only Global Settings.
