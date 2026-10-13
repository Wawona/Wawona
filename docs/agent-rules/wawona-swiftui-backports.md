# SwiftUI availability backports

Pattern follows Dave DeLong's `Backport` namespace
(https://davedelong.com/blog/2021/10/09/simplifying-backwards-compatibility-in-swift/):
one holding type owns every `#available` shim; call sites stay clean.

For Apple SwiftUI UI that runs on iOS or iPadOS 13 through current, use
`Sources/WawonaUI/Compatibility/WawonaBackport.swift` at the call site:

```swift
card.backport.liquidGlass(cornerRadius: 20)
button.backport.glassToolbarButton() // .automatic on Liquid Glass bars
```

iPhone Machines Add and machine-editor Cancel/Save are **plain toolbar
buttons**: `ToolbarItem` + `Button` + `Image(systemName:)` (`plus`,
`xmark`, `checkmark`). Default system size and spacing. No custom circle
fill, glassProminent compose shim, fixed frame, font weight, or
`sharedBackgroundVisibility` hacks on those items. iPhone bottom Add sits
next to `DefaultToolbarItem(kind: .search)` with a `ToolbarSpacer`.

**Exactly one Add Machine control.** iPhone: bottom toolbar only (iOS 26
Messages search bar, or pre-26 `safeAreaInset` chrome). iPad / visionOS:
top-trailing only. Never mount Add in both top-trailing and bottom on
phone.

The compatibility namespace owns every `#available` check and its fallback.
Do not scatter availability branches through feature views. Add a named shim to
`WawonaBackport` when adopting a newer SwiftUI API, preserve the nearest older
system behavior as the fallback, and test both paths. The product floor is
iOS 13, so SwiftUI is the UI. There is no iOS 11 or 12 UIKit-only product.
Business and graphics policy stay in Rust; this rule covers presentation APIs only.

`ScrollViewReader` is iOS 14+. Wawona Terminal uses
`WawonaBackport<Any>.scrollViewReader` plus `WawonaScrollViewProxy` in
`Compatibility/WawonaBackport.swift`. Never bare `ScrollViewReader` in
phone/iPad/tv/vision feature views. iOS 13 fallback: plain `ScrollView`
(`scrollTo` no-op). Watch (watchOS 10) may use native `ScrollViewReader`.

Upgrade path (DeLong): when dropping an old OS floor, delete the shim and
search `backport.` call sites, then remove the `.backport` segment.

Hard rejects:

- Binding `List(selection:)` to `@Published` on a shared `ObservableObject`
  (iOS 16 NavigationSplitView exclusivity crash on Settings tap). Use `@State`
  for the List and sync the router on the next main-queue turn.
- Calling iOS 26 Liquid Glass APIs outside `WawonaBackport`
- Raising the app deployment target to adopt a SwiftUI modifier
- Using an imitation of Liquid Glass as a substitute for the system effect
- Moving availability or compositor capability policy into SwiftUI
- `.buttonStyle(.glass)` on iOS 26 navigation toolbar items (glass-on-glass)
- Custom glass search capsule on iPhone Machines when iOS 26 system
  `DefaultToolbarItem(kind: .search)` is available
- Custom opaque / glassProminent / fixed-frame styling on iPhone toolbar Add
  or editor sheet xmark/checkmark (use default toolbar `Button` + SF Symbol)
- Custom SF Symbol Cancel/Save in `.cancellationAction` /
  `.confirmationAction` on iOS 26 (system also vends close/done)
- Global Settings dismiss: use `backport.settingsCloseAction` (trailing
  `xmark` on iOS / iPadOS / visionOS; `Done` on macOS / tvOS). Never a
  leading `Done` string in `.cancellationAction` for Settings close.

iPhone Machines bottom search: see skill `wawona-swiftui-backports` and
`wwn-mcp/knowledge/wawona/ios-iphone-machines-messages-chrome.md`.

Before claiming one Mode A IPA is proven across its supported OS range, migrate
every post-13 SwiftUI API into named shims and run both forced compatibility
paths. Physical proof starts at iOS 13 devices.

Machine Add/Edit on iOS / visionOS uses `backport.machineEditorSheet(item:)`
from `WWNMachinesGridView`: half sheet on phone (`.medium` → `.large`), page
or large on iPad, system Liquid Glass on iOS 26. Do not use `fullScreenCover`
for that editor. Direct `.sheet` on the NavigationSplitView detail can no-op;
the backport attaches via a zero-size background. macOS keeps sheet +
`editorSheet()`. tvOS stays fullScreenCover. `WawonaStateObject` must not
construct the wrapped object in `init` (factory only), or ViewModel observers
leak and Add freezes.
