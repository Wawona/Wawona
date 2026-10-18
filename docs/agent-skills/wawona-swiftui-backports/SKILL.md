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

`ScrollViewReader`: `WawonaBackport<Any>.scrollViewReader` +
`WawonaScrollViewProxy` in `Compatibility/WawonaBackport.swift`. Required for
Wawona Terminal on iOS 13+. Never bare `ScrollViewReader` at phone call sites.

## iOS 26 bottom search

For the iPhone Machines Messages-style bottom search row, `.searchable(text:)`
must use its default placement so the visible controller owns the
`UISearchController`. The bottom slot is `WWNPhoneIntegratedSearchToolbar`:
copy `navigationItem.searchBarPlacementBarButtonItem` into that controller's
`toolbarItems` with a flexible space and one prominent `+`. Do not use
`DefaultToolbarItem(kind: .search, placement: .bottomBar)`. That vends the
button from a bridge navigation item, UIKit ignores it, and SwiftUI inserts
a zero-height `UIKitToolbar` under `UIHostingController.view`. Do not add
`placement: .toolbar`. Keep `usesNativePhoneSearchToolbar` true on iOS 26+.
Top-trailing toolbar buttons use `.automatic`, not `.glass` (glass-on-glass).
Editor Cancel/Save stay plain `xmark` / `checkmark`. **One Add only:**
phone = bottom toolbar `+`; iPad/vision = top-trailing.

## Machine editor sheets

On **iOS / visionOS**, present Add/Edit with
`backport.machineEditorSheet(item:)` (resizable **sheet**, not
`fullScreenCover`). Phone: `.medium` then pull to `.large`. iPad: page/large.
iOS 26: keep system Liquid Glass sheet material (no custom
`presentationBackground`). Attach via the zero-size background helper so
NavigationSplitView detail + iOS 26 bottom search still present. macOS:
sheet + `editorSheet()`. tvOS: fullScreenCover (10-foot).

`WawonaStateObject` must capture the factory only (never construct the
`ObservableObject` in `init`). Eager construction leaked
`NotificationCenter` observers on discarded `WWNMachinesViewModel` instances
and rebuilt heavy drafts on every body eval.

Selected machine configuration goes immediately after identity/type, before
Display/Input/Graphics. Native and shared editors use
`backport.editorChromeActions` (plain toolbar `xmark` / `checkmark` on
`.topBarLeading` / `.topBarTrailing`). Never put custom SF Symbol buttons in
`.cancellationAction` / `.confirmationAction` on iOS 26 (Liquid Glass doubles
close/done). Global Settings dismiss: `backport.settingsCloseAction`
(trailing `xmark` on iOS / iPadOS / visionOS; `Done` on macOS / tvOS /
watchOS).
