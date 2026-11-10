---
name: wawona-machine-card-actions
description: >-
  Machines: select a grid/list card, then act on the machine detail view
  (Start/Stop/Focus/Edit/Delete + Tags/Pin). Use when editing MachineActionBar,
  WWNMachineDetailView, WWNMachineCardView, QuickConnectView, Android
  MachineDetailScreen, or Linux home card detail.
---

# Machines: select then act (detail-first)

Rule: `wawona-machine-card-actions`.
RAG: `wwn-mcp/knowledge/wawona/machine-card-actions.md`.

Load `wawona-apple-swift` / `wawona-android-compose` before host UI edits.

## Contract (all platforms)

1. **Grid / list cards are select-only.** Tap/click opens machine detail.
   No Start/Stop/Focus/Edit/Delete chips on the card face.
2. **Detail owns actions.** Start, Stop, Focus, Edit, Delete, Tags, and Pin
   live only on the machine detail screen (or Linux detail dialog).
3. **tvOS / platforms without context menus:** Tags and Pin must appear in
   detail. Do not rely on long-press / right-click for those.

| Host | Detail host |
|---|---|
| Apple (macOS / iOS / iPadOS / tvOS / visionOS) | `WWNMachineDetailView` |
| watchOS | `QuickConnectView` (+ Tags / Pin / Delete) |
| Android | `MachineDetailScreen` |
| Linux | Adw detail dialog from card click |

A11y: `wwn.machines.detail`, `wwn.machines.detail.back`.

## Action bar layout (detail only)

`MachineActionBar` / `MachineActionFlow` still apply **inside detail**:

1. `.flow` (phone / Mac / pad): always `MachineActionFlow`. Do not wrap with
   `ViewThatFits` + single-line `HStack` first.
2. Nil / infinite proposal width: `resolvedMaxWidth` (~2 chips/line).
3. tvOS / watchOS detail: `.stack` (one full-width chip per row).

## Card appearance

Keep a visible one-point outline around each machine card in light and dark
appearance. Adaptive semantic color (macOS separator; iOS primary at 16%/28%;
Android `outlineVariant`). Never fixed white on light iOS fills.

## Hard rejects

- Action chips on grid cards again
- Hiding Tags/Pin on tvOS because there is no context menu
- Nested `NavigationStack` on macOS split for detail (swap in-pane /
  `detailMachineId` instead)
- Truncating or dropping Delete/Edit to "make the row fit" on detail
