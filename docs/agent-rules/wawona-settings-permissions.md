# Settings → Permissions

Authority for the **Permissions** Global Settings section and update checks.
Pairs with `wawona-global-settings-exclusive` (in-app host only).

## Who shows Permissions

| Host | Permissions section |
|---|---|
| macOS | Yes (Launch Agents, Login Item, updates, Swinging Bridge TCC links) |
| Linux | Yes (rename of Launch Agent page + updates) |
| Android | Yes (updates stub; no Launch Agents) |
| iOS / iPadOS / tvOS / visionOS / watchOS | No (store / mobile hosts omit the section) |

Catalog: Rust `SettingsSectionId::Permissions`, Swift
`GlobalSettingsSectionID.permissions`, Android `SettingsTab.PERMISSIONS`.

## Check for Updates

Pref key: `CheckForUpdatesEnabled` (default **on**).

Flow:

1. Toggle enables or disables network checks.
2. **Check Now** hits `GET /repos/Wawona/Wawona/releases/latest`.
3. Compare CalVer `CFBundleShortVersionString` / `VERSION` to `tag_name`
   (strip leading `v`).
4. When newer: **Download Update** opens the matching release asset
   (macOS `.dmg`, else Releases page).

Never ship a silent in-place updater that rewrites the running bundle.
User installs from the downloaded DMG / APK / AppImage.

## macOS Launch Agents / Login Item

Controls live in Settings → Permissions (and a one-shot post-welcome offer):

- Compositor host + menubar Launch Agents (`WWNLaunchAgentManager`)
- Open Wawona at login (app launch agent; quit stays quit)

DMG install is **drag `Wawona.app` to Applications**. Agents are not
auto-loaded by a pkg `postinstall` on the release volume. Optional
maintainer `WawonaAgent.pkg` stays off the GitHub Release DMG.

## Hard rejects

- PrefPane / System Settings as the Permissions host
- Hiding Check for Updates behind a dead toggle with no Check Now path
- Claiming pkg-only DMG while the release volume is drag-install
- Putting Permissions on Watch / phone store Settings catalogs

## Code

- UI: `WWNPermissionsSettingsView`, `WWNUpdateChecker`
- Agents: `WWNLaunchAgentManager`
- Welcome offer: `WelcomeAgentsOfferModifier`
- Catalog: `src/domain` settings + `SettingsContracts.swift`

See also: `wawona-release-assets` (DMG layout), `docs/settings.md`.
