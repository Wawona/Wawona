# SwiftUI availability backports

For Apple SwiftUI UI that runs on iOS or iPadOS 13 through current, use
`Sources/WawonaUI/Compatibility/WawonaBackport.swift` at the call site:

```swift
card.backport.liquidGlass(cornerRadius: 20)
button.backport.glassButtonStyle()
```

The compatibility namespace owns every `#available` check and its fallback.
Do not scatter availability branches through feature views. Add a named shim to
`WawonaBackport` when adopting a newer SwiftUI API, preserve the nearest older
system behavior as the fallback, and test both paths. The product floor is
iOS 13, so SwiftUI is the UI. There is no iOS 11 or 12 UIKit-only product.
Business and graphics policy stay in Rust; this rule covers presentation APIs only.

Hard rejects:

- Calling iOS 26 Liquid Glass APIs outside `WawonaBackport`
- Raising the app deployment target to adopt a SwiftUI modifier
- Using an imitation of Liquid Glass as a substitute for the system effect
- Moving availability or compositor capability policy into SwiftUI

Before claiming one Mode A IPA is proven across its supported OS range, migrate
every post-13 SwiftUI API into named shims and run both forced compatibility
paths. Physical proof starts at iOS 13 devices.

Machine settings use `backport.editorSheet()` in both editor hosts. iPadOS 18+
uses `.presentationSizing(.page)` with the large detent so the system adapts to
the current window. iPadOS 16/17 opens large; older hosts retain native sheets.
Phone keeps medium/large. Do not apply the default medium phone detent to iPad.
