---
name: wawona-machine-card-actions
description: >-
  Machines grid card action chips (Focus/Stop/Edit/Delete/Start) must always
  fit inside the card. Use when editing MachineActionBar, MachineActionFlow,
  WWNMachineCardView, or any LazyVGrid machine card chrome on Apple.
---

# Machine card action chips (fit inside card)

Rule: `wawona-machine-card-actions`.
RAG: `wwn-mcp/knowledge/wawona/machine-card-actions.md`.
Code: `Sources/WawonaUI/Machines/MachineActionBar.swift`,
`Sources/WawonaUI/Machines/WWNMachineCardView.swift`.

Load `wawona-apple-swift` first for any Apple UI edit.

## Contract

On a running machine card, **Focus, Stop, Edit, Delete** (and Start when idle)
must all be fully visible inside the card glass. No clipped second row. Titles
stay one line per chip; the **bar** wraps chips, never letters inside a chip.

## Layout rules

1. **Always** `MachineActionFlow` for `.flow` (iOS 16+). Do **not** put
   `ViewThatFits` around a single-line `HStack` first. That path measures the
   Flow with infinite width, reports one-row height, then places a wrapped
   second row that the card clips (Delete cut off).
2. `MachineActionFlow.arrange`: when `proposal.width` is nil/infinite
   (common under `LazyVGrid`), use `resolvedMaxWidth` that assumes ~2 chips
   per line for 3-4 actions so `sizeThatFits` height includes wrap.
3. Card content: `.fixedSize(horizontal: false, vertical: true)` **before**
   `.frame(maxHeight: .infinity)` so the grid row grows with wrapped actions
   instead of stretching and clipping.

tvOS / watchOS stay `.stack` (one full-width chip per row).

## Verify

Start a Native Shell machine on iPhone Simulator. Card must show all four
running actions fully inside the glass. Screenshot under
`.agent-device/test-artifacts/`.

## Hard rejects

- `ViewThatFits { HStack { chips }; MachineActionFlow { chips } }` for card actions
- Treating nil proposal width as infinity in a custom `Layout` wrap
- Card chrome that clips overflow instead of growing height for wrap
- Truncating or dropping Delete/Edit to "make the row fit"
