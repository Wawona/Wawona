---
name: wawona-apple-sidebar-icons
description: >-
  Section-tinted SF Symbols in Machines and Settings sidebars. Accents also
  tint Settings detail controls. Never colored rounded-square icon tiles.
---

# Apple sidebar icons (tinted SF Symbols)

## Do

- Machines and Global Settings sidebars: SF Symbols tinted with section
  accent via `WawonaSettingsHubChrome.hubRow` / `sidebarIcon` (`iconColor`).
- Settings **detail** panes: same accent on Toggle / Picker / Button /
  Link via `.settingsSectionAccent` + `.backport.tint` (watch: `.accentColor`).
- Accent source: `WawonaSettingsHubChrome.accentColor(for:)` /
  `section.swiftUIIconColor` (same colors as before the tile removal).
- Settings split chrome matches Machines: system sidebar toggle (never
  strip / never a second custom `sidebar.left`). Detail trailing:
  `settingsCloseAction(onClose:chromeBridge:)`. Pass `showSidebar:` only
  on pre-16 HStack.

## Hard rejects

- Colored rounded-square tiles with white glyphs in any Machines or Settings
  sidebar row
- Painting section accent into sidebar icon **backgrounds**
- Re-adding Settings.app General-style hub tiles for Wawona sidebars
- Dropping section colors so sidebar glyphs are only `.primary`

## Where

| Surface | Path |
|---------|------|
| Hub helpers | `Sources/WawonaUIContracts/WawonaSettingsHubChrome.swift` |
| Settings sidebar | `Sources/WawonaUI/Settings/WWNGlobalSettingsHostView.swift` |
| Machines sidebar | `Sources/WawonaUI/WawonaMainWindowView.swift` (`sidebarRowLabel`) |
| Settings detail tint | `Sources/WawonaUI/Settings/WWNSettingsSectionView.swift` |
| Settings toolbar | `Sources/WawonaUI/Compatibility/WawonaPresentation.swift` |
| Watch detail tint | `Sources/WawonaWatch/WatchKitGlobalSettings.swift` |

Rule: `wawona-apple-sidebar-icons`. Related:
`wawona-global-settings-exclusive`, `wawona-swiftui-backports`.
