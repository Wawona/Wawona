---
name: wawona-swiftui-backports
description: Central SwiftUI availability shims for Apple products.
---

# SwiftUI backports

Read `Wawona/docs/agent-rules/wawona-swiftui-backports.md` before changing
SwiftUI availability. Use `WawonaBackport` for iOS/iPadOS 13+ APIs (Dave
DeLong namespace pattern: availability only inside `.backport.*` shims). The
product floor is iOS 13, so SwiftUI is the UI. There is no iOS 11 or 12
UIKit-only product. After a new durable shim, update this rule and Wawona RAG.

## iOS 26 bottom search

For the iPhone Machines Messages-style bottom search row, `.searchable(text:)`
must use its default placement. `DefaultToolbarItem(kind: .search, placement:
.bottomBar)` is the sole owner of the search slot. Do not add
`placement: .toolbar`, which vends a conflicting navigation item during
split-detail restoration. Keep `usesNativePhoneSearchToolbar` true on iOS 26+.
Top-trailing toolbar buttons use `.automatic`, not `.glass` (glass-on-glass).
Add Machine / editor Save checkmark: `Image(systemName:)` +
`.backport.composeCircleButton()` (`.iconOnly` + `.borderedProminent` +
`.circle` + accent tint) + `sharedBackgroundVisibility(.hidden)`. iOS 26
`.glassProminent` on toolbar/sheet icon buttons often paints a bare glyph
with no fill. Toolbar `Label` also drops the bubble. Keep Add in
top-trailing on phone: the split forces `.regular` width and the bottom
compose slot can collapse, which made + vanish.

## Machine editor sheets

Use `backport.editorSheet()` for both machine editors. iPad gets system page
sizing and a large detent; phone keeps medium/large. iPadOS 13 remains supported.
The actual iPad Simulator page presentation was verified on 2026-10-02.

Selected machine configuration goes immediately after identity/type, before
Display/Input/Graphics. Native and shared editors use
`backport.editorChromeActions` (one X, one blue checkmark on
`.topBarLeading` / `.topBarTrailing`). Never put custom SF Symbol buttons in
`.cancellationAction` / `.confirmationAction` on iOS 26 (Liquid Glass doubles
close/done).
