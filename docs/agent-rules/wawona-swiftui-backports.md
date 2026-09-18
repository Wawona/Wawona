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
system behavior as the fallback, and test both paths. UIKit remains mandatory
for iOS 11 and 12 and must not load SwiftUI. Business and graphics policy stay
in Rust; this rule covers presentation APIs only.

Hard rejects:

- Calling iOS 26 Liquid Glass APIs outside `WawonaBackport`
- Raising the app deployment target to adopt a SwiftUI modifier
- Using an imitation of Liquid Glass as a substitute for the system effect
- Moving availability or compositor capability policy into SwiftUI

Before claiming one Mode A IPA is proven across its supported OS range, migrate
every post-13 SwiftUI API into named shims and run both forced compatibility
paths. Physical iOS 11/12 devices remain the final UIKit proof.
