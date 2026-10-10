# SwiftUI availability backports

Pattern follows Dave DeLong's `Backport` namespace
(https://davedelong.com/blog/2021/10/09/simplifying-backwards-compatibility-in-swift/):
one holding type owns every `#available` shim; call sites stay clean.

For Apple SwiftUI UI that runs on iOS or iPadOS 13 through current, use
`Sources/WawonaUI/Compatibility/WawonaBackport.swift` at the call site:

```swift
card.backport.liquidGlass(cornerRadius: 20)
button.backport.composeCircleButton()
```

iPhone Machines Add and editor Save checkmark: use `Image(systemName:)`
plus `.backport.composeCircleButton()` and
`sharedBackgroundVisibility(.hidden)`. That shim uses `.borderedProminent` +
`.circle` (opaque blue fill). iOS 26 `.glassProminent` on toolbar/sheet icon
buttons often paints a bare glyph with no bubble. A toolbar `Label` does the
same.

The compatibility namespace owns every `#available` check and its fallback.
Do not scatter availability branches through feature views. Add a named shim to
`WawonaBackport` when adopting a newer SwiftUI API, preserve the nearest older
system behavior as the fallback, and test both paths. The product floor is
iOS 13, so SwiftUI is the UI. There is no iOS 11 or 12 UIKit-only product.
Business and graphics policy stay in Rust; this rule covers presentation APIs only.

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
- Custom SF Symbol Cancel/Save in `.cancellationAction` /
  `.confirmationAction` on iOS 26 (system also vends close/done)

iPhone Machines bottom search: see skill `wawona-swiftui-backports` and
`wwn-mcp/knowledge/wawona/ios-iphone-machines-messages-chrome.md`.

Before claiming one Mode A IPA is proven across its supported OS range, migrate
every post-13 SwiftUI API into named shims and run both forced compatibility
paths. Physical proof starts at iOS 13 devices.

Machine settings use `backport.editorSheet()` in both editor hosts. iPadOS 18+
uses `.presentationSizing(.page)` with the large detent so the system adapts to
the current window. iPadOS 16/17 opens large; older hosts retain native sheets.
Phone keeps medium/large. Do not apply the default medium phone detent to iPad.
