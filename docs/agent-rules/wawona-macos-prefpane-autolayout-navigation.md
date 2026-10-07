# macOS PrefPane: width and in-pane navigation

Updated 2026-10-07. System Settings → Wawona (`Wawona.prefPane`).

## Reference dump: System Settings → General

Binary (macOS 26.5):

`/System/Applications/System Settings.app/Contents/PlugIns/GeneralSettings.appex`

| Fact | Evidence |
|---|---|
| **Not** a classic `NSPreferencePane` | `EXExtensionPointIdentifier` = `com.apple.Settings.extension.ui` |
| Developed as | SwiftUI + ExtensionKit. Internal path `SystemPrefsApp/GeneralSettings/GeneralSettings.swift` (Xcode 17E6107 / SDK 26.5) |
| Links | `Settings.framework`, `SwiftUI`, `ExtensionKit`, `AppKit`, `Combine` |
| Size / layout owner | Host (`System Settings` / `SettingsHost`). Pane uses Settings form scales `formLarge` / `formMedium` / `formSmall`. Content column + `$__lazy_storage_$_maxContentWidth` live in the host. Classic panes opt in with `NSPrefPaneSupportsAutoLayout` (Network / Dock / Wawona). Host also knows `NSPrefPaneMinimumWidth`. |
| Hub model | `GeneralSettings.Model` holds `_subPanes`, `selectedSubPane`, `settingsHost`, `serviceHost`. Each `GeneralSubpane` has `ext`, `name`, `icon`, `identifier`, badge / disabled. |
| Row catalog | `Info.plist` `hosted_bundles`: About, Software Update, Storage, AirDrop, Login Items, Coverage, Localization, Date & Time, Sharing, Time Machine, Transfer/Reset, Startup Disk, Profiles. |
| In-pane navigation | Imports private `Settings.SettingsNavigationPath` + `NavigationToken` (`hasPushedContent`, `pathToken`). Host exposes `popNavigationStack`, `_canGoBack`, `_canGoForward`. |

GhidraVibe MCP headless timed out on this host during the dump. Findings above are from `Info.plist`, `otool -L`, `nm` + `swift-demangle`, and `strings` on a thinned arm64e copy under `/tmp/wawona-re/`.

## iOS Settings.bundle vs macOS PrefPane (why not "just a plist")

| | iOS Settings.app | macOS System Settings |
|---|---|---|
| Third-party surface | `Settings.bundle` + `Root.plist` / `PreferenceSpecifiers` | `.prefPane` (`NSPreferencePane`) or first-party `Settings.extension.ui` |
| UI | Apple renders the plist (toggles, groups, multi-value). Almost never custom SwiftUI inside Settings.app | Custom `mainView` (our SwiftUI). Host sizes the column |
| Wawona today | `src/resources/Settings.bundle` (shares `NSUserDefaults` keys) | `Wawona.prefPane` + `WawonaPrefPaneRootView` |

Yes: iOS app settings in Settings.app are usually plists. That works because Settings.app **hosts** `Settings.bundle`.

macOS System Settings does **not** host third-party `Settings.bundle` as a sidebar pane the way iOS does. `Root~mac.plist` can appear for some Mac Catalyst / legacy cases; it is **not** a substitute for a PrefPane in the modern sidebar. So we cannot "ship only a plist" for System Settings → Wawona on macOS. PrefPane (or a private ExtensionKit Settings extension) is required.

Global Settings exclusivity (`wawona-global-settings-exclusive`): macOS PrefPane
is the **sole** Global Settings host. iOS Settings.bundle is the sole host on
iPhone/iPad. `WawonaGlobalSettingsPanelView` is tvOS/visionOS only. Do not ship
PrefPane **and** an in-app Global Settings catalog on macOS. Shared Form chrome
helper: `WawonaSettingsHubChrome` (PrefPane + tvOS/visionOS).

## What that means for Wawona

Wawona ships a **classic** `NSPreferencePane` (third-party path). We do **not** get `Settings.SettingsNavigationPath`, so System Settings toolbar arrows will **never** pop our SwiftUI section stack.

Map **iOS Settings.bundle** (+ General Form chrome) → Wawona PrefPane:

| iOS Settings.app → Wawona | macOS PrefPane |
|---|---|
| `PSGroupSpecifier` sections | `Form` + `Section(header:)` per catalog section |
| `PSToggleSwitchSpecifier` | Inline `Toggle` |
| `PSMultiValueSpecifier` | Inline `Picker` (menu); long lists → checkmark page |
| `PSTextFieldSpecifier` | Inline `TextField` |
| Child pane (Env Vars) | `NavigationLink` → `PrefPaneEnvironmentVariablesView` |
| Host content column | `NSPrefPaneSupportsAutoLayout` + zero-frame `mainView` |

Not a General **hub of section links**. Flat grouped Form like the iOS Wawona
Settings page. General teaches Form sizing / host column; Settings.bundle
teaches row inventory shape.

Section inventory: `GlobalSettingsCatalog.systemSettingsPaneSections` →
`WWNPreferencesSectionsBuilder.buildSections()`. Keep `NavigationPath` stable
across `reload()` (only Env Vars / long pickers push).

## Width (match Network / Dock)

First-party classic panes set `NSPrefPaneSupportsAutoLayout = true` in Info.plist.
System Settings then sizes `mainView` to the content column.

Hard rejects:

- Fixed `NSRect(0,0,700,720)` (or similar) as the only size
- SwiftUI `.frame(maxWidth: 668)` that leaves an island beside empty chrome
- Missing `NSPrefPaneSupportsAutoLayout` in PrefPane `Info.plist`

Do:

- Zero-frame host + Auto Layout pin to edges
- `minWidth` / `minHeight` only (fill max width/height)
- Same pattern as Network.prefPane / Dock.prefPane

## Navigation (why System Settings Back fails)

System Settings toolbar back/forward is **sidebar selection history**
(General → Network → Wawona). It does **not** pop a nested SwiftUI
`NavigationPath` inside a classic `NSPreferencePane`.

Hard rejects:

- Remounting `NavigationStack` with `.id(refreshTick)` on every defaults
  write (drops path; traps the user in a section)
- Assuming System Settings chrome arrows will return to the section list
- Expecting private `SettingsNavigationPath` without migrating to
  `com.apple.Settings.extension.ui` (not the current product path)

Do:

- Keep `NavigationPath` stable across `reload()`
- Own in-pane Back (`path.removeLast()` / `@Environment(\.dismiss)`)
- Document that chrome arrows leave the Wawona pane for another sidebar item
- Home list = General-style Form of section rows (not a capped List island)

## Future (not now)

A first-party-style `Settings.extension.ui` appex could use
`SettingsNavigationPath` so chrome arrows pop subpanes. That is a packaging
and entitlement change, not a PrefPane tweak. Stay on `.prefPane` until product
explicitly migrates.

## Code

- `Sources/WawonaApple/Lifecycle/WawonaPrefPaneRootView.swift`
- `Sources/WawonaApple/Lifecycle/WawonaSystemPreferencePane.swift`
- `src/platform/macos/ui/Settings/PrefPane/Info.plist`

Rule mirror: `.cursor/rules/wawona-macos-prefpane.mdc` when present.
