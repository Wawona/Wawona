# Machines: select then act (detail-first)

Authority for Machines grid → detail across Apple, Android, and Linux.
Skill: `wawona-machine-card-actions`. RAG:
`wwn-mcp/knowledge/wawona/machine-card-actions.md`.

## Required

1. Selecting a machine from the grid or list opens a detail screen.
2. Start, Stop, Focus, Edit, Delete, Tags, and Pin appear only on that
   detail screen (or Linux detail dialog).
3. Grid cards stay display-only (banner, badges, summary). No action chips.
4. Platforms without context menus (tvOS) still get Tags and Pin in detail.

## Implementation

| Piece | Path |
|---|---|
| Apple detail | `Sources/WawonaUI/Machines/WWNMachineDetailView.swift` |
| Apple grid | `Sources/WawonaUI/Machines/WWNMachinesGridView.swift` (`detailMachineId`) |
| Display card | `Sources/WawonaUI/Machines/WWNMachineCardView.swift` |
| Detail actions | `Sources/WawonaUI/Machines/MachineActionBar.swift` |
| watch detail | `Sources/WawonaWatch/QuickConnectView.swift` |
| Android | `android/.../MachineHomeScreen.kt` (`MachineDetailScreen`) |
| Linux | `src/linux/ui/home.rs` (card click → Adw dialog) |

A11y: `wwn.machines.detail`, `wwn.machines.detail.back`.

macOS split pane: swap detail in-place. Do not nest a second
`NavigationStack`.

## Detail action wrap

Inside detail, Focus/Stop/Edit/Delete (and Start when idle) stay fully
visible. Chip titles one line. `.flow` uses `MachineActionFlow` with
finite `resolvedMaxWidth`. tvOS / watchOS use `.stack`.

## Hard rejects

- Restoring action chips on grid cards
- Tags/Pin only on a context menu for tvOS
- Measuring wrap layout at infinite width then clipping the second row
- Hiding Delete/Edit to fit one row
