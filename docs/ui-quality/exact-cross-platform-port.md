# Exact cross-platform port (demo lessons → Wawona)

Authority from Exact demos + `docs/start-here.md` (LLP 1115). Use this when
cloning macOS concept art into Exact Contract for ALL_TARGETS.

## Motto

**Write the web, ship the platform.**

One Contract. Many native looks. Shared **semantics** (actions, state, routes).
Divergent **chrome** (AppKit source list, UITabBar, Material nav, Fluent, web).

## Demo map (what to copy)

| Demo / pattern | Lesson for Wawona |
|---|---|
| **`apps/shelf`** | Chrome oracle. Structure only; **no-tells**. Header → nav bar; `list appearance="auto"` → grouped list; modal → sheet; `contextPopover` → long-press menu. Leave accent unsaid. |
| **`docs/patterns/list-detail`** | Phone **pushes** detail. Wide window **auto-splits** list \| detail when rows are `link` + `symbol:forward-chevron` (or a press that writes the router). Use `replace` when swapping detail. Placeholder when nothing selected. |
| **`docs/patterns/tabs`** | Root `tablist` → iOS tab bar; on Mac / wide web → **sidebar**. Each tab keeps its own stack. |
| **`apps/fieldnotes`** | Desktop window frame + list beside editor (wide). Shortcuts map to same actions as buttons. Share / files only where host capability exists. |
| **`apps/messages`** | Pixel-match of an Expo reference with **hex and points**. That is a fidelity lab, **not** the style for new product chrome. New apps leave look unsaid. |
| **`apps/windows-desk`** | Same Contract semantics; Windows HWND adapter paints. Proves host ownership of controls. |
| **`docs/recipes/grouped-form`** | Settings / identity forms = inset-grouped list, not cards of fields. |
| **`docs/recipes/responsive-columns`** | `flex="1 1 280px"` / `exactViewport` for wrap; do not hardcode phone vs desktop trees unless needed. |

## Flawless port checklist

1. **One Contract file** owns routes, state, actions, accessible names.
2. **Leave look unsaid:** roles (`-exact-secondary-label`, `font="-exact-footnote"`). Gate: `bun scripts/no-tells.mjs apps/wawona`.
3. **Portable symbols only** for ALL_TARGETS (`symbol:layers`, never `symbol:sf/…`).
4. **Compose as the platform does:**
   - Row → detail = `link` + chevron (unsaid `navigationSplit` on wide).
   - Create / edit / Settings = **modal** sheets.
   - Delete confirm = `alertdialog`.
   - Long-press = `contextPopover`.
5. **Root destinations** that belong in a Mac Library / iOS tab bar = **root tabs**, not painted fake sidebars.
6. **Wide vs compact:** prefer Exact unsaid split over a second hand-authored three-column tree. Phone pushes; desktop splits.
7. **Verify per host:** `verify` / Exact agent / `cargo xtask agent grade macos`. Never mark an unrun target passed.
8. **Concept art is host-local.** macOS concept grades macOS only. iOS / Android / watch get their own concepts + idioms (`wawona-platform-native-interaction`).

## Wawona Machines (concept 1:1) architecture

Concept wants three columns on macOS. Exact's native shape for that:

```text
Root tablist (Library)     → Mac sourceList / iOS tab bar
  tab Machines             → list of machines (middle) | machine detail (inspector)
  tab Sessions             → sessions list [| detail]
  tab Images               → images catalog
  tab Runtimes             → runtime status
Settings                   → gear cover (modal). NEVER a root tab peer.
```

| Pane | Exact mechanism | Not |
|---|---|---|
| Left Library | Root `tab` destinations + hidden `tablist` promote | Rows stuffed into `navigationSplit` list column |
| Middle browser | Machines tab **list** (`link` + chevron / card face) | Placeholder-only cards that vanish when detail opens |
| Right inspector | Pushed `machine` route beside list (unsaid split) | Always-on third pane invented outside the router |
| Settings | `openSettings` modal | Machines\|Settings tab pair |

Prefer one inset-grouped list for all widths (`wwn.machines.row.*`). After
unsaid split, `exactViewport` can shrink to the detail pane and flip an
`isWide` fork, swapping testIds mid-grade. Card faces stay optional polish;
rows must still **navigate** (`link` + chevron) so Exact splits.

## Hard rejects (Exact + Wawona)

- Hex / font-size / font-weight in product Contract (Messages-style tells)
- Forcing macOS concept pixels onto phone / watch / tv
- Machines\|Settings root tablist
- Wayland surface inside the inspector
- Hand-rolled second navigation stack beside Exact routes
- Claiming 1:1 without a running-host grade on that host
- Root tablist plus explicit `navigationSplit="320"` / `placeholder` on the
  same Machines stack. SidebarMac install re-enters `SplitHost.present` then
  `layoutSubtreeIfNeeded` then `apply`, and `--chrome platform` never reaches
  `ready`. Use unsaid list-detail (`link` + `forward-chevron`) so Library tabs
  and the machine list share one sidebar (navigator strip + sourceList).

## Related

- Exact: `AGENTS.md`, `docs/start-here.md`, `apps/shelf/app.contract`
- Wawona: `wawona-exact-contract`, `wawona-platform-native-interaction`,
  `wawona-ui-five-layers`, `platform-concepts/macos/CONCEPT_GRADE.md`
