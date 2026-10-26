# Apple sidebar icons (tinted SF Symbols)

Authority for Machines and Global Settings sidebar glyphs on Apple SwiftUI.

## Rule

Sidebars use **section-tinted SF Symbols** (glyph `foregroundColor` =
section accent). Never colored rounded squares with white glyphs.

The same section accents tint Settings **detail** controls (Toggle, Picker,
Button, Link, section headers) via `.settingsSectionAccent` +
`.backport.tint`.

## Hard rejects

- Colored icon tiles (rounded square fill + white glyph) in Machines or
  Settings sidebars
- Section accent as sidebar icon **background** fill
- Settings.app General hub tile chrome for Wawona list rows
- Monochrome / `.primary` sidebar glyphs that drop the section colors

## Code

`WawonaSettingsHubChrome.hubRow` / `sidebarIcon` in
`Sources/WawonaUIContracts`. Detail tint in `WWNSettingsSectionView`.
Settings split chrome matches Machines: system sidebar toggle (never strip /
never a second custom `sidebar.left`). Detail trailing:
`settingsCloseAction(onClose:chromeBridge:)`. Pass `showSidebar:` only on
pre-16 HStack.

Skill: `wawona-apple-sidebar-icons`. Related:
`wawona-global-settings-exclusive`, `wawona-swiftui-backports`.
RAG: `wwn-mcp/knowledge/wawona/apple-sidebar-icons.md`.
