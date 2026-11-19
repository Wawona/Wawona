# macOS Exact vs concept grade (2026-11-18)

Concept: `machines-concept.jpg` (also mirrored from agent assets).
Product hard filters still apply: Settings = gear cover; no Machines|Settings
tablist; no Wayland surface in the inspector; no-tells clean.
Interaction: `wawona-platform-native-interaction` (shared semantics, native
paradigms).

## Verdict

| Area | Concept | Exact now | Gap | Score /10 |
|---|---|---|---|---|
| Window material | Dark vibrancy / glass | Exact glass + NSToolbar | Adapter owns feel | 7 |
| Top brand | Bridge + title + subtitle | Window title Machines | Brand strip still missing | 3 |
| Top segments | Machines / Sessions / Images / Runtimes | Library sidebar destinations + gear | Top capsule strip absent (OK: Library owns them) | 7 |
| Search | Cmd+F pill in toolbar | Browser search field | Toolbar projection still open | 5 |
| Sidebar Library | Machines/Sessions/Images/Runtimes + counts | Same destinations via `libraryDest` | Counts present; shell stays on `all` | 8 |
| Favorites / Tags | Pinned/Recent + colored tags | Pinned + Recent + tag dots | Platform Targets section still absent | 7 |
| Platform Targets | Host filter list | Absent | Optional filter section | 2 |
| Transfers | Progress card | Absent | Deferred (download lane) | 1 |
| Middle list | Card rows + thumb + status + play/stop | Card rows + status + start/stop/more | Selection glow / thumb density | 8 |
| Inspector | Always third column + Open Session primary | Push detail + Overview + bordered-prominent Open | True persistent third column while browsing still weak | 6 |
| Runtime copy | NixOS planned in concept art | macOS available (Relay) | Product truth preferred | 8 |
| Interaction idiom | Desktop pointer + shortcuts | Context menu, Meta+,, glass | Keep desktop paradigm; brand toolbar next | 7 |

**Aggregate (Machines chrome, macOS only): ~62/100** (was ~44). Gate 90 not met.
Evidence: `cargo xtask agent grade macos --rebuild` stamp `2026-11-18T103536`
(`docs/ui-quality/history/2026-11-18T103536-macos-concept-grade.json`).
Sidebar now Library-only (Machines/Sessions/Images/Runtimes + Favorites/Tags);
middle pane is card browser; inspector Overview + bordered-prominent Start/Open.

### Exact-correct path to true 3-column (from demos)

See `docs/ui-quality/exact-cross-platform-port.md`. Oracles: `apps/shelf`,
`docs/patterns/list-detail`, `docs/patterns/tabs`.

1. Promote Library destinations to **root tabs** (Mac sourceList), not rows
   inside `navigationSplit`'s list column.
2. Machines tab content = **machine list** with `link` + chevron (card face OK).
3. Opening a machine **unsaid-splits** list \| inspector on wide; phone pushes.
4. Stop replacing the card browser placeholder with the detail (that collapses
   to two columns). Settings stays gear modal.

Next grade after that restructure. Then toolbar search / brand. Platform
Targets optional. Transfers deferred. Dark vibrancy = system/adapter.

## Concept filters (do not ship)

- Settings as a peer top segment → **reject** (gear cover only)
- Pixel-forcing Liquid Glass tells into Contract → **reject** (adapter)
- Runtime "planned" on macOS VM/container → **reject** (gates available)

## Evidence plan

1. `cargo xtask agent grade macos --rebuild` after each chrome pass
2. Screenshot middle + inspector beside concept PNG
3. Re-score this table until aggregate ≥ 90 and no hard-gate fail
