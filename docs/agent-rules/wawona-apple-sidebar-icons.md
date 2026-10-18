# Apple sidebar icons (tinted SF Symbols)

Authority for Machines and Global Settings sidebar glyphs on Apple SwiftUI.

## Rule

- Sidebars: **section-tinted SF Symbols** (`WawonaSettingsHubChrome.sidebarIcon`
  / `hubRow` with `iconColor`). Glyph color = section accent. No colored
  rounded-square tile, no white glyph on colored fill.
- Settings **detail**: same section accent tints Toggle / Picker / Button /
  Link / section headers (`.settingsSectionAccent` + `.backport.tint`; watch
  uses `.accentColor`).
- Accent palette: `WawonaSettingsHubChrome.accentColor(for:)` and section
  `swiftUIIconColor`. Tint glyphs and detail controls; never paint that color
  onto sidebar icon backgrounds.
- Settings split chrome matches Machines: system `NavigationSplitView`
  sidebar toggle (do not strip / do not add a second custom `sidebar.left`).
  Detail trailing: `settingsCloseAction(onClose:chromeBridge:)` (`[+][x]`).
  Pass `showSidebar:` only on pre-16 HStack (no system toggle there).

## Hard rejects

- Settings.app General-style colored hub tiles in Wawona Machines or Settings
  sidebars
- Section accent as sidebar icon chrome (background fill)
- Monochrome / `.primary`-only sidebar glyphs that drop section colors

## Code

`WawonaSettingsHubChrome` in `Sources/WawonaUIContracts`. Detail tint in
`WWNSettingsSectionView` (`.settingsSectionAccent` + `.backport.tint`).
Toolbar: `WawonaPresentation.settingsCloseAction(onClose:chromeBridge:)`.

Skill: `wawona-apple-sidebar-icons`. Related:
`wawona-global-settings-exclusive`.
RAG: `wwn-mcp/knowledge/wawona/apple-sidebar-icons.md`.
