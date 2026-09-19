---
description: Centralize Swift and SwiftUI backwards compatibility through Backport shims
alwaysApply: true
---

# Wawona Swift / SwiftUI backports

Organization-wide rule for every Wawona repository that ships Swift or
SwiftUI. This follows Dave DeLong's
[Backport technique](https://davedelong.com/blog/2021/10/09/simplifying-backwards-compatibility-in-swift/).

## Hard rules

1. **Keep availability out of feature views.** Do not scatter
   `if #available` through SwiftUI view bodies. Put checks in the shared
   `Backport<Content>` namespace and call them through `.backport` or
   `Backport<Any>`.
2. **Every backport has an honest fallback.** Newer OSes call the native API;
   older supported OSes receive a project-owned implementation that preserves
   the feature's essential behavior. A no-op is acceptable only for optional
   decoration and must be documented in the shim. Backports own presentation
   compatibility only; behavior or policy decisions belong in Rust.
3. **Match system API names and shapes.** Backported modifiers should use the
   system modifier's name where practical. Backported types should use a nested
   type or static `@ViewBuilder` factory. This keeps call sites searchable and
   makes removing `.backport` mechanical when the deployment floor rises.
4. **One compatibility home.** Extend the existing shared backport source
   (`Sources/WawonaUI/Backport.swift` in Wawona) instead of creating local
   wrappers in individual feature files.
5. **Do not fake incompatible types.** Environment keys, property wrappers, and
   APIs whose old/new types differ need a Wawona-owned abstraction with one
   stable type. Do not force-cast framework values or erase safety to imitate a
   backport.
6. **Imperative platform code is separate.** Lifecycle, UIKit/AppKit, Metal,
   scene, and delegate availability may remain in centralized platform
   adapters when a SwiftUI backport is not the right abstraction. Do not move
   platform integration into feature views.
7. **Backport is not a deployment target.** A wrapper does not make the binary,
   Rust/static libraries, embedded frameworks, or transitive dependencies
   compatible with an older OS. Keep XcodeGen, SwiftPM, Rust target triples,
   Nix recipes, and framework `MinimumOSVersion` aligned with the claimed floor.
8. **Prove both paths.** Compile with the oldest supported deployment target,
   test the fallback on the oldest supported runtime, and test the native path
   on the newest runtime. An availability wrapper without fallback-path
   evidence is only wired, not supported.

## Required pattern

```swift
public struct Backport<Content> {
    public let content: Content

    public init(_ content: Content) {
        self.content = content
    }
}

public extension View {
    var backport: Backport<Self> { Backport(self) }
}

public extension Backport where Content: View {
    @ViewBuilder
    func systemFeature() -> some View {
        if #available(iOS 26.0, *) {
            content.systemFeature()
        } else {
            content.wawonaFallback()
        }
    }
}
```

Feature call site:

```swift
content.backport.systemFeature()
```

For new framework types, use `Backport<Any>.TypeName(...)` with either a
nested `View` or a static `@ViewBuilder` factory.

## Review checklist

- Search changed feature views for `#available`; move presentational branches
  into the shared backport namespace.
- Confirm the fallback works at the repository's claimed minimum OS.
- Audit unguarded newer types too (`App`, `StateObject`, `NavigationStack`,
  environment values, scene APIs); modifiers are not the only availability
  surface.
- Rebuild every Apple target that compiles the shared source.
- Do not alter Wawona's production `WWNCore*` C polling FFI while introducing
  UI compatibility shims.
- Do not put business logic in a backport shim.
