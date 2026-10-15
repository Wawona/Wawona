---
name: wawona-apple-sidebar-icons
description: >-
  Plain SF Symbols in Machines and Settings sidebars. Section accents tint
  Settings detail controls only. Never colored rounded-square icon tiles.
---

# Apple sidebar icons (plain SF Symbols)

## Do

- Machines and Global Settings sidebars: plain system SF Symbols via
  `WawonaSettingsHubChrome.hubRow` / `sidebarIcon`.
- Settings **detail** panes: section accent on Toggle / Picker / Button /
  Link via `.settingsSectionAccent` + `.backport.tint` (watch: `.accentColor`).
- Accent source: `WawonaSettingsHubChrome.accentColor(for:)` /
  `section.swiftUIIconColor`.

## Hard rejects

- Colored rounded-square tiles with white glyphs in any Machines or Settings
  sidebar row
- Painting section accent into sidebar icon backgrounds
- Re-adding Settings.app General-style hub tiles for Wawona sidebars

## Where

| Surface | Path |
|---------|------|
| Hub helpers | `Sources/WawonaUIContracts/WawonaSettingsHubChrome.swift` |
| Settings sidebar | `Sources/WawonaUI/Settings/WWNGlobalSettingsHostView.swift` |
| Machines sidebar | `Sources/WawonaUI/WawonaMainWindowView.swift` (`sidebarRowLabel`) |
| Settings detail tint | `Sources/WawonaUI/Settings/WWNSettingsSectionView.swift` |
| Watch detail tint | `Sources/WawonaWatch/WatchKitGlobalSettings.swift` |

Rule: `wawona-apple-sidebar-icons`. Related:
`wawona-global-settings-exclusive`.
