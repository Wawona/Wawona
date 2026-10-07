# macOS System Settings PrefPane

Authority: `wwn-mcp/knowledge/wawona/macos-prefpane-autolayout-navigation.md`,
`docs/settings.md`.

## Width

`Info.plist` must set `NSPrefPaneSupportsAutoLayout` = true (Network / Dock).
`mainView` fills the System Settings content column. Min size only. Never a
fixed 700×720 island or a hard `maxWidth: 668` that leaves empty chrome.

## Navigation

System Settings toolbar back/forward is **sidebar history**, not SwiftUI
`NavigationPath`. Own in-pane Back (`path.removeLast` / `dismiss`). Never
remount `NavigationStack` with `.id` on every defaults write (traps the user
in a section).

## Env Vars

Env Vars must be editable **inside** the PrefPane (`PrefPaneEnvironmentVariablesView`
+ `WawonaModel` / `WawonaPreferences` suite `com.aspauldingcode.Wawona`). Never
hand off with `openApplication` + `--show-settings` (that spawned extra
`Wawona.app` UI instances).

## Hard rejects

- Fixed PrefPane frame as the only size
- Cap content narrower than the host column for "Network-style" cosmetics
- Relying on System Settings arrows to pop section drill-down
- `.id(refreshTick)` (or similar) on the PrefPane root after each toggle
- "Open Wawona…" handoff for Env Vars instead of in-pane editing
- PrefPane `NSWorkspace.openApplication` that creates a second Regular UI

