# Global Settings exclusivity

Exactly **one** Global Wawona Settings interface per platform target
(further split by OS version only when the out-of-app API is
**product-usable** on that version and install channel).

Prefer OS System Settings / PrefPane / Settings.bundle / Watch app Settings
whenever that path can host the global catalog. In-app Global Settings exists
**only** when the OS path is unavailable or not product-usable.

**Product-usable** means the user can open and edit Wawona globals in the OS
Settings UI for that artifact. An SDK class existing is not enough (Android 16
`SettingsPreferenceService` discovery is system-app-only for Play/sideload).

## Matrix

| Target / band | Sole Global Settings host |
|---|---|
| macOS | System Settings PrefPane (`com.aspauldingcode.Wawona.prefPane`) |
| iOS / iPadOS | Settings.bundle (`Settings > Apps > Wawona`) |
| watchOS prefs | iPhone Watch app `Settings-Watch.bundle` |
| tvOS / visionOS | In-app only |
| Android (Play / typical sideload today) | In-app Compose + `APPLICATION_PREFERENCES` |
| Android when OS inject is product-usable | System Settings only; remove Compose hub on that band |

## Schema

Rust `settings_catalog` + Swift `GlobalSettingsCatalog` + `wawona.pref.*`.
Suite for PrefPane sync: `com.aspauldingcode.Wawona`. Never invent Gemini toy
keys or `group.com.wawona.global`.

## Not Global Settings (may stay in-app)

Machine editors, sidebar Desktop / About / Dependencies, and one-shot actions
(Watch send, import, log copy). They must **not** re-host Display / Input /
Graphics / Env Vars catalog toggles under a second "Wawona Settings" hub.

Env Vars: macOS PrefPane hosts the editor. iOS: Settings.bundle for simple
keys; complex table editors are Machines/About actions, not a second Global
Settings hub.

## Hard rejects

- In-app Global Settings panel **and** PrefPane / Settings.bundle / system
  Settings inject on the same target
- PrefPane missing → fall back to a full in-app duplicate catalog
- `SettingsPreferenceService` **and** Compose Settings hub as dual Global
  Settings for the same API band
- On-watch Global Settings UI when Settings-Watch.bundle owns Watch prefs
- Desktop / Mode B / jailbreak copy in App Store Settings.bundle

Cursor rule: `.cursor/rules/wawona-global-settings-exclusive.mdc`.
Product: `docs/settings.md`. RAG: `wwn-mcp/knowledge/wawona/global-settings-exclusive.md`.
