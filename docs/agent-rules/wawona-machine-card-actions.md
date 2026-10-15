# Machine card actions must fit inside the card

Authority for Machines grid card action chips on Apple (iPhone/iPad/macOS
SwiftUI). Skill: `wawona-machine-card-actions`. RAG:
`wwn-mcp/knowledge/wawona/machine-card-actions.md`.

## Required

Focus, Stop, Edit, Delete (and Start when idle) are always fully visible
inside the machine grid card. Chip titles stay one line. The action bar may
wrap chips onto a second row; the card height must include that row.

## Implementation

| Piece | Path |
|---|---|
| Bar + Flow layout | `Sources/WawonaUI/Machines/MachineActionBar.swift` |
| Card hug height | `Sources/WawonaUI/Machines/WWNMachineCardView.swift` |

- `.flow`: always `MachineActionFlow`. Never `ViewThatFits` + single-line
  `HStack` first.
- Nil / infinite proposal width: `resolvedMaxWidth` (~2 chips/line for 3-4
  actions) so `sizeThatFits` reports wrap height before place.
- Card: vertical `fixedSize` before `maxHeight: .infinity`.

## Hard rejects

- Measuring wrap layout at infinite width then clipping the second row
- Hiding or omitting Delete/Edit to fit one row
- Restoring `ViewThatFits(HStack)` for card actions without a proven
  finite-width measure that matches place height
