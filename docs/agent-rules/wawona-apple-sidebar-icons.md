# Apple sidebar icons (plain SF Symbols)

Authority for Machines and Global Settings sidebar glyphs on Apple SwiftUI.

## Rule

Sidebars use **plain SF Symbols** (system style). Never colored rounded
squares with white glyphs. Section accent colors tint Settings **detail**
controls only (Toggle, Picker, Button, Link, section headers).

## Hard rejects

- Colored icon tiles in Machines or Settings sidebars
- Section accent as sidebar icon background fill
- Settings.app General hub tile chrome for Wawona list rows

## Code

`WawonaSettingsHubChrome` in `Sources/WawonaUIContracts`. Detail tint in
`WWNSettingsSectionView` (`.settingsSectionAccent` + `.backport.tint`).

Skill: `wawona-apple-sidebar-icons`. Related:
`wawona-global-settings-exclusive`.
RAG: `wwn-mcp/knowledge/wawona/apple-sidebar-icons.md`.
