# Native Machines sidebar

Machines list belongs in the host’s **native sidebar region**, never as a
painted fake sidebar inside the content view.

## Required

| Host | Sidebar API |
|---|---|
| macOS product (SwiftUI dual-run) | `NavigationSplitView` sidebar column |
| macOS Exact | AppKit `.sourceList` via root `tablist`, or by promoting the `navigationSplit` list when that tablist is `display="none"` |
| iPadOS / visionOS / tvOS | System split / `NavigationSplitView` sidebar |
| Windows | WinUI `NavigationView` (or Fluent NavigationView-shaped chrome). Never Aqua-looking sidebar |
| Android | Material navigation rail / drawer when the OS pattern fits |
| Linux | libadwaita / GTK sidebar patterns |

## Exact (macOS)

Exact maps the **root `role="tablist"`** to AppKit `.sourceList`.

Wawona Exact keeps that tablist at `display="none"` so Settings / Tab Overview
stay toolbar-only (`select()` still works). The Mac host then **promotes** the
selected stack’s `navigationSplit` list (Machines profiles, Settings catalog)
into the same AppKit `.sourceList`, covers the authored list, and collapses the
painted list column. Contract: flat `listRows` list (no `section`, no
`listStyle` / `appearance="auto"`). Filters and other chrome sit in the header
(or outside the list), per `contract/lower` `cells.rs`.

1. Product SwiftUI `NavigationSplitView` remains the dual-run macOS Machines oracle.
2. Exact Wawona Machines / Settings catalog rows must not paint a second
   “sidebar look” inside the detail/content view.
3. Do not put Settings or Tab Overview in the AppKit source-list rows. Those
   are toolbar / bar buttons.

## Hard rejects

- Fake sidebar UI drawn inside the main content column when a native sidebar
  API exists on that host
- Claiming a painted `navigationSplit` list column is AppKit `.sourceList`
  (promotion covers that list; the source list is the sidebar column)
- Settings / Tab Overview as AppKit sidebar rows (use toolbar)
- One shared sidebar skin across macOS and Windows
