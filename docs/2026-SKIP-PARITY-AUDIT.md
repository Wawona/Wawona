# 2026 Skip Parity Audit

This audit inventories all `#if SKIP` branches in `Sources/WawonaUI` and classifies each branch as `keep`, `remove`, or `refactor` for Android/iOS parity.

## Inventory

| File | Branch | Current behavior | Decision | Reason |
| --- | --- | --- | --- | --- |
| `Sources/WawonaUI/Components/AdaptiveNavigationView.swift` | `#if SKIP` | Android path forces `NavigationStack { detail }` and drops sidebar entirely | `refactor` | Removes nav parity with desktop/tablet and weakens settings/machine information architecture |
| `Sources/WawonaUI/Components/GlassCard.swift` | `#if SKIP` | Uses plain padded content with no card surface/elevation/stroke | `refactor` | Causes visible styling drift versus iOS material/glass intent |
| `Sources/WawonaUI/CompositorBridge.swift` | `#if os(Android)` + `#if SKIP` | Android compositor renders empty Compose `Box` placeholder | `remove` | Placeholder breaks functional parity and must be replaced by real host surface |
| `Sources/WawonaUI/Machines/MachinesGridView.swift` | `#if SKIP` | Uses custom empty-state stack instead of `ContentUnavailableView` | `refactor` | UI copy is close but visual behavior diverges; can unify through shared fallback component |
| `Sources/WawonaUI/Machines/MachinesRootView.swift` | `#if SKIP` | Uses basic list of buttons; non-SKIP uses selection-tagged list | `refactor` | Selection model parity needed for consistent machine navigation |
| `Sources/WawonaUI/Settings/SettingsRootView.swift` | `#if SKIP` | Duplicate code branch with same behavior | `remove` | No functional difference; branch increases drift risk and maintenance burden |

## Action mapping

- `remove`: delete branch and use one shared code path.
- `refactor`: replace platform branch with shared component or equivalent behavior on both paths.
- `keep`: none in current `WawonaUI` audit set.

## Outcome target

After migration, `Sources/WawonaUI` should avoid `#if SKIP` for purely visual/navigation behavior. Platform branching should remain only where host/compositor APIs differ and cannot be represented in shared SwiftUI.
