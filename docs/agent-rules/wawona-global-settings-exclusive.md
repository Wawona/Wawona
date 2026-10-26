# Global Settings exclusivity

Exactly **one** Global Wawona Settings interface per platform target. That host
is **inside the Wawona app**. The user never leaves the app for Global Settings.

OS System Settings, PrefPane, Settings.bundle, Settings-Watch.bundle, and
Android App Info Preferences are **retired** as Global Settings hosts. Do not
rebuild them.

## Matrix

| Target / band | Sole Global Settings host |
|---|---|
| macOS | In-app `WWNGlobalSettingsHostView` slides up over Machines (gear / Cmd-,). Never a modal sheet (macOS sheet backport is a floating popup). Section sidebar + detail |
| iOS / iPadOS | In-app `WWNGlobalSettingsHostView` slides up over Machines (gear) |
| watchOS | In-app `WatchGlobalSettingsView` sheet (system slide-up) |
| tvOS / visionOS | In-app `WWNGlobalSettingsHostView` slides up over Machines (gear) |
| Android | In-app Compose `SettingsDialog` with `AnimatedVisibility` slide-up |
| Linux | In-app `adw::Dialog` `BottomSheet` (slide-up) |

Text and password fields on iOS / tvOS / visionOS use a push editor page
(Settings.app pattern: row → new view → Save → back), not sheets or inline
fields in the section list.

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

Machines home sidebar lists Machines / Project / Tags only. Global Settings
sections live in the dedicated Settings host sidebar (`visibleSections`).

## Sidebar icons (Apple)

Section-tinted SF Symbols in Machines and Settings sidebars. Same accents
tint Settings detail controls. Never colored rounded-square icon tiles.
See `wawona-apple-sidebar-icons`.

## Hard rejects

- PrefPane / `Settings.bundle` / `Settings-Watch.bundle` as a Global Settings host
- `x-apple.systempreferences:…Wawona.prefPane` or `UIApplication.openSettingsURLString`
  as the Settings entry
- `ACTION_APPLICATION_PREFERENCES` / `SettingsPreferenceService` as a second host
- Dual OS Settings inject **and** in-app Global Settings for the same catalog
- Desktop / Mode B / jailbreak copy in any retired Settings.bundle
- macOS Global Settings as `.sheet` / floating popup (must replace Machines chrome in-window)
- Colored rounded-square tiles with white SF Symbols in Settings or Machines sidebars

Cursor rule: `.cursor/rules/wawona-global-settings-exclusive.mdc`.
Product: `docs/settings.md`. RAG: `wwn-mcp/knowledge/wawona/global-settings-exclusive.md`.
Verify: `Wawona/scripts/verify-settings-bundle-keys.py`.

## History (do not revive)

Introducing OS hosts: `8f2335a` (macOS PrefPane + iOS Settings.bundle),
later Watch redirect / Settings-Watch.bundle, Android App Info Preferences.
Superseded by in-app-only Global Settings.
