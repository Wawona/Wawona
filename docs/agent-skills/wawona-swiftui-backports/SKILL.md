---
name: wawona-swiftui-backports
description: Central SwiftUI availability shims for Apple products.
---

# SwiftUI backports

Read `docs/agent-rules/wawona-swiftui-backports.md` before changing SwiftUI
availability. Use `WawonaBackport` for iOS/iPadOS 13+ APIs. iOS 11 and 12 are
UIKit-only. After a new durable shim, update this rule and Wawona RAG.

## iOS 26 bottom search

For the iPhone Machines Messages-style bottom search row, `.searchable(text:)`
must use its default placement. `DefaultToolbarItem(kind: .search, placement:
.bottomBar)` is the sole owner of the search slot. Do not add
`placement: .toolbar`, which vends a conflicting navigation item during
split-detail restoration.
