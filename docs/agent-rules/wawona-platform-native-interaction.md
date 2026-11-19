# Platform-native interaction paradigms

Hard rule for every Wawona Exact / product UI target.

## Principle

**Shared functionality, native interaction.**

Cross-platform consistency preserves **semantics, state, and capabilities**.
It does **not** preserve identical layouts, gestures, or chrome.

## Terms

| Term | Meaning |
|---|---|
| Interaction modality | mouse, keyboard, touch, stylus, remote, gaze, hand |
| Interaction paradigm | desktop windowing, mobile stack, spatial, focus-remote |
| Platform-native UX | conventions users expect on that OS |
| Adaptive UX | experience changes with device class and input |
| Platform idioms | established patterns on one platform |

Wawona uses **platform-native interaction paradigms** (adaptive cross-platform
UX with platform-native interaction semantics).

## Per-target idioms (must)

| Host | Paradigm |
|---|---|
| macOS / Windows / Linux | Pointer-first desktop. Keyboard shortcuts. Context menus. Drag-drop. Resizable windows. Sidebar + list + inspector where the OS idiom expects it |
| iOS / Android phone | Touch-first. Navigation stacks. Sheets / covers. Large hit targets |
| iPadOS / Android tablet | Hybrid touch + pointer + keyboard. Multiwindow when the OS allows |
| watchOS / Wear OS / asteroidOS | Glanceable. Compact. Gesture-first |
| visionOS / Android XR | Spatial. Gaze / hand / direct manipulation |
| tvOS | Focus engine. Remote. No pointer chrome |

## Exact Contract layering

1. **Contract** = what the user can do (shared actions / state).
2. **Adapter** = how that host presents and drives it.
3. **Native guidelines** = how it must feel on that host.
4. **Bend** = laws that never break.
5. **Computer-use critic** = prove it on a running build.

macOS concept art is the **macOS** visual/UX target. It is **not** a pixel
template for iOS, Android, or watches. Grade each host against its own
concept + HIG / Material / focus rules.

## Hard rejects

- Desktop windowing chrome forced onto phone or watch
- Mobile stack / bottom-sheet forced onto macOS as the only navigation
- Machines\|Settings root tablist (Settings stays a gear cover)
- Pixel-parity as a cross-platform pass criterion
- Claiming 1:1 with a concept without a running-host grade

## Related

`wawona-ui-five-layers`, `wawona-exact-contract`, `wawona-all-targets`,
`docs/ui-quality/platform-concepts/`.
