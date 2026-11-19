# UI Audit Progress (macOS Exact)

Source: owner pack `wawona-ui-audit-cursor.zip` (F / 38 heuristic). Spec under `docs/ui-quality/audit/`.

## Iteration 1 — 2026-11-17

- Platform/OS/SDK/Xcode: macOS Exact tip via `cargo xtask agent grade macos --rebuild`; ExactKit host; Xcode 27 toolchain on machine.
- Git commit/base: local `development` working tree (Exact `apps/wawona/app.contract` + Wawona `xtask`).
- Screens and states tested: Machines browser (catalog), Sample Linux VM planned inspector, Native Shell inspector, Settings, Display, Add, Tabs (Exact agent, `--chrome platform`).
- Changes (file paths and rationale):
  - `exact/apps/wawona/app.contract`: P0 machine browser replaces empty-state command cluster; toolbar New/Settings/Tabs/search/filters on browser; `runtimeSupport` / `canStartMachine` / Execution vs Readiness; Start Unavailable for planned; Pin On/Off + Tags affordances; Danger Zone delete; inspector max width; sidebar readiness captions.
  - `Wawona/xtask/src/exact_agent.rs`: grade ops include `inspector-planned`.
  - `docs/ui-quality/audit/*`: copied owner audit pack.
- Before screenshots: audit `assets/screenshot-01..04.png` (empty cluster, fake Start on planned).
- After screenshots: `docs/ui-quality/history/artifacts/2026-11-17T172310-*.png`.
- Build/test commands and results:
  - `bun scripts/no-tells.mjs apps/wawona` → clean
  - `bun scripts/exact.mjs contract build apps/wawona/app.contract --json --errors-only` → `[]`
  - `cargo xtask agent grade macos --rebuild` → exit 0
- Accessibility/keyboard results: UNVERIFIED beyond agent tree labels (VoiceOver / full keyboard not run this iteration).
- P0/P1/P2 open and closed:
  - Closed P0: overview browser; commands out of empty-state; Start gated for planned; Execution≠Readiness; Pin/Tags visible.
  - Open P1: native NSToolbar / Settings scene ⌘,; alignment density; sidebar smash residual; live thumbs; context menus keyboard.
  - Open P2: contrast polish; Liquid Glass materials.
- Scorecard with evidence (re-score vs audit dimensions, still heuristic):
  - Information architecture: ~55 (browser exists; Sessions destination not yet)
  - State and action clarity: ~70 (Start Unavailable + Readiness proven on auth51)
  - Navigation: ~45
  - Layout: ~50
  - Aggregate estimate: **~58** (was 38). Release gate 90 not met.
- Regressions: none observed in grade pass; Settings sheet width pegs retained.
- Unverified claims / blockers: true AppKit NSToolbar vs Exact header chrome; SDK 27 Liquid Glass APIs; VoiceOver pass.
- Next highest-priority action: denser full-width browser + inspector alignment; Settings as in-window cover (product rule) with category→detail proven; keyboard/context menu pass.

## Iteration 2 — 2026-11-17 (same session)

- Changes: full-width browser rows; empty `head` on wide Machines; sidebar readiness captions.
- After: `2026-11-17T172705-*` (catalog, inspector-planned still Start Unavailable).
- Commands: `cargo xtask agent grade macos --rebuild` → exit 0.
- Re-score estimate still ~58. Not release-ready.

## Iteration 3 — 2026-11-17 (browser full-bleed)

- Fault: scroll+`width=100%` buttons shrink-to-fit (~299pt centered). Layout dump: list 331×610, rows 299×37.
- Fix: shelf-style `list flex=1 width=100%` rows in `exact/apps/wawona/app.contract` browser pane.
- Evidence: `layout` after rebuild → browser 620×700, list 588×594, row 588×29. Catalog `2026-11-17T180135-catalog.png`.
- Grade: `cargo xtask agent grade macos --rebuild` → exit 0.
- Closed P1: centered-card / shrink-to-fit browser list.

## Iteration 4 — 2026-11-17 (Sessions + keyboard)

- Changes: rename Tab Overview → Sessions; Library/Sessions sidebar row (`wwn.nav.sessions`); toolbar Sessions label; wide Sessions = full-bleed list + close; compact keeps card grid.
- After: `2026-11-17T180457-*`. Sidebar first row `Sessions, 1 open`. Sessions pane list row Term + Close.
- Keyboard (agent tree, no PNG: drive screenshot refused `no sRGB PNG` outside grade path): `type machines-search native` filters browser; Escape clears. `tap … contextmenu` on `wwn.machines.browser.term` shows Focus/Stop/Edit/Delete/Tags/Unpin.
- Settings: in-app gear cover + category→Display still works (`settings-display` stamp). Dedicated Settings window / ⌘, **UNVERIFIED** (product rule keeps in-app cover; audit wants native scene).
- Re-score estimate ~68. Release gate 90 not met.
- Open P1 residual: ⌘, / AppKit Settings scene; NSToolbar authorship; sidebar density polish; full VoiceOver.
- Next: inspector leading-edge alignment; menu-bar Settings chord if Exact hatch exists; keep looping.

## Iteration 5 — 2026-11-17 (inspector guide)

- Changes: machine inspector header owns name + actions; `max-width=40rem` list `align-self=flex-start`; titlebar stays `Machines` on machine route.
- After: `2026-11-17T181000-inspector-planned.png` (heading + Start Unavailable on one guide; Start gated).
- Grade: exit 0.
- Keyboard residual: search type + Escape + browser contextmenu proven in agent tree (drive PNG capture still flaky).
- Aggregate estimate ~72. Not release-ready.
- Open: ⌘, Settings scene vs in-app cover product rule; native NSToolbar items; VoiceOver.

## Iteration 6 — 2026-11-17 (⌘, / ⌘N)

- Fault: `display=none` shortcut buttons never entered AppKit menus.
- Fix: `aria-keyshortcuts="Meta+,"` / `Meta+n` on live toolbar Settings / New buttons.
- Evidence: `state menus` → App `Settings… ⌘,`, File `New Machine ⌘N`. Drive `type toolbar-taboverview key Meta+,` → `key="Meta+,"` + `wawona-settings-catalog` open. Settings remains in-app cover (product rule); audit dedicated Settings window still deferred.
- Grade stamp: `2026-11-17T182555-*`.
- Aggregate estimate ~75. Release gate 90 not met.
- Open: authored NSToolbar item set beyond Exact header chrome; VoiceOver; sidebar density polish.

## Iteration 7 — 2026-11-17 (sidebar density)

- Tried trailing readiness text in sourceList rows; SidebarMac promoted the caption as the title (`Ready` / `1`). Reverted to single primary text (name / `Sessions (N)`); readiness stays in `aria-label`.
- Stamp: `2026-11-17T183017-*`. Sidebar titles: Sessions (1), Native Shell, Term, …
- Aggregate estimate ~76. Not release-ready.
- Open: Exact header chrome ≠ full authored NSToolbar; VoiceOver UNVERIFIED; Liquid Glass / contrast P2.

## Blockers / deferred (evidence)

- **Authored NSToolbar items:** Exact `--chrome platform` installs `NSToolbarToggleSidebarItem` (+ separator) only. Browser commands live in the detail `header` (New / Settings… / Sessions / Sort / search). No Contract hatch found to push those into AppKit toolbar slots without Exact host work. Recorded as P1 residual, not greenwashed.
- **Dedicated Settings window:** Product rule `wawona-global-settings-exclusive` requires in-app gear cover. Audit wants a separate Settings scene. Cover + ⌘, App menu item shipped; separate window deferred on purpose.
- **VoiceOver:** Agent tree labels present; full VoiceOver rotor pass **UNVERIFIED**.

## Iteration evidence stamps

| Stamp | Notes |
|---|---|
| 2026-11-17T171938 | First P0 browser + Start Unavailable |
| 2026-11-17T172310 | Sidebar readiness captions |
| 2026-11-17T172705 | Full-width browser; no double Machines head title |
| 2026-11-17T180135 | Full-bleed `list` browser (588pt rows) |
| 2026-11-17T180457 | Sessions sidebar + Sessions list pane |
| 2026-11-17T181000 | Inspector leading guide + restrained titlebar |
| 2026-11-17T182555 | Menu bar Settings… ⌘, + New Machine ⌘N |
| 2026-11-17T183017 | Dense sourceList titles restored |
| 2026-11-17T183223 | Nested-column readiness captions; titles `Name, Ready` |
| 2026-11-17T183358 | Add VM/Container Readiness copy; grade ~77 |
| 2026-11-17T183518 | Sort label; keyboard-nav note |
| 2026-11-17T184647 | Inspector NSToolbar Start/Settings; Tags; wasm sparkles; grade ~80 |
| 2026-11-17T184828 | Planned Start Unavailable in toolbar; microcopy; grade ~80 |
| 2026-11-17T184940 | Kind-aware Identity footer |
| 2026-11-17T185045 | Sidebar caption helper |
| 2026-11-17T185157 | Sidebar titles `…, Planned` (no truncation); grade ~81 |
| 2026-11-17T185336 | Steady grade; score JSON; NSToolbar + Planned titles hold ~81 |
| 2026-11-17T185546 | Declared toolbarPlacement=window attempt: off-viewport, no lift; reverted |
| 2026-11-17T185710 | Restored painted catalog chrome; inspector exact.command.* holds |
| 2026-11-17T185822 | Filter All only when `activeFilter==all` (not while tag active); grade ~81 |
| 2026-11-17T185935 | Sessions empty copy; grade green; inspector NSToolbar holds ~81 |
| 2026-11-17T190640 | Inline tag radios + Dependencies panel; grade ~83 |
| 2026-11-17T190830 | Filter NSSegmentedControl (5); grade ~84 |
| 2026-11-17T191353 | Settings gear → Display controls; grade ~85 |
| 2026-11-17T191702 | Sort PrefSelect + Settings Display; grade ~86 |
| 2026-11-17T191935 | Semantic status colors; grade ~86 |
| 2026-11-17T192215 | Display prefs vertical stack; grade ~87 |
| 2026-11-17T192542 | Full-bleed rows + grade +1500 real; grade ~87 |

## Iteration 10 — declared toolbar attempt

- Tried `row role="toolbar" toolbarPlacement="window"` on the wide Machines route for catalog NSToolbar.
- Result: toolbar painted in the list column (off-viewport); `state.window.toolbar` stayed ToggleSidebar-only; grade failed tapping `toolbar-settings`.
- Reverted. Catalog commands remain painted in the placeholder header. Inspector detail projection unchanged.

## Iteration 9 — 2026-11-17 (sidebar density + copy)

- SidebarMac titles come from `aria-label`. Long `Runtime planned` truncated wide names. `readinessCaption` → **Planned**; browser keeps full `Runtime planned · Stopped`.
- Identity footer is kind-aware (VM/Container/Native).
- Stamp: latest grade green with inspector `exact.command.*` Start/Settings.
- Aggregate **~81**. Gate 90 not met.

## Iteration 8 — 2026-11-17 (NSToolbar + P2 affordances)

- Fault: route `head` was the first child, so `HeaderRule` never saw `header`. Catalog chrome in the split placeholder also cannot project: `splitHeaderRoutes.beside` is nil while `detail` is null.
- Fix: machine (and other non-modal) routes put `header` first, then `head title="Machines"`. Inspector actions become AppKit toolbar items.
- Evidence (stamp `2026-11-17T184647`):
  - After `tap wwn.machines.row.native-shell`: `state.window.toolbar.items` includes `exact.command.325` (Settings…) and `exact.command.327` (Start), plus `exact.split.separator`.
  - Inspector PNG: Start pill + gear in the titlebar strip.
  - Catalog still ToggleSidebar-only (placeholder host limit; not greenwashed).
- P2: Tag filter label **Tags**; wasm kind icon `symbol:sparkles` (sidebar SF `sparkles`); browser status line uses footnote without forcing secondary grey.
- Aggregate estimate **~80**. Release gate 90 not met.
- Open: catalog placeholder NSToolbar (Exact host); VoiceOver; Liquid Glass API proof.

## Keyboard notes (partial)

- `prefer keyboard-navigation true` accepted (`page.keyboard-navigation=true`).
- Tab from `machines-search` lands on filter radios (`filter-all` / tag chips).
- Settings Display: Tab from Done focuses All Settings (`settings-all-categories`). Full VoiceOver rotor still UNVERIFIED.

## Appearance notes (partial)

- `prefer prefers-color-scheme dark` → `media.prefers-color-scheme=dark`.
- `prefer prefers-contrast more` → `media.prefers-contrast=more`.
- Dark evidence: `history/artifacts/dark-catalog.png`, `dark-inspector-planned.png` (Start Unavailable + orange Runtime planned + Dependencies).
- True Liquid Glass / SDK 27 material APIs still UNVERIFIED (host-owned; do not invent blur).

## Blockers / deferred (updated)

- **Catalog NSToolbar:** Exact `SplitHost` leaves `beside` nil for placeholder-only detail. Browser commands stay painted in the placeholder header. Inspector detail routes now author real `exact.command.*` items.
- **Dedicated Settings window:** still deferred (`wawona-global-settings-exclusive`).
- **VoiceOver:** still UNVERIFIED.


## Iteration 11 — 2026-11-17 (tag chips + Dependencies)

- Fault: `role=menu` tag filter under Exact agent mode paints at 0,0 (no NSMenu while `ExactEnv.agentMode`). Agent tap `filter-tag-work` failed outside viewport. Coloured `symbol:circle` was a red herring.
- Fix: inline tag radios in `wawona-machines-browser-filters` radiogroup (All / Pinned / Local / Work / Personal). Removed `tag-filter-menu`. Context/sort menus keep `position="absolute"`.
- P1 Dependencies: planned inspectors show Required `Relay (NixOS guest|OCI-in-VM)` + Unavailable beside Start gating. `phaseBusy` Starting/Stopping/Failed for execution feedback. Identity footer calls out editable Name/Kind + Save.
- Evidence: stamp `2026-11-17T190640`; `tap filter-tag-work` → browser only Sample Linux VM; Dependencies tree on auth51; grade exit 0.
- Aggregate estimate **~83**. Gate 90 not met.
- Open: catalog NSToolbar (Exact host); dedicated Settings window deferred; VoiceOver; Liquid Glass.


## Iteration 12 — 2026-11-17 (NSSegmented filter)

- Fault: filter radios stayed authored pills because `aria-label` Tag Work disagreed with face title Work (SegmentsMac refuse).
- Fix: drop per-tag aria-label override; radiogroup projects to NSSegmentedControl (5 segments). Agent tap `filter-tag-work` delivery `native=segmented-control`.
- Stamp `2026-11-17T190830`; aggregate **~84**. Gate 90 not met.
- Open: catalog NSToolbar (Exact host); dedicated Settings window deferred; VoiceOver; Liquid Glass.


## Iteration 13 — 2026-11-17 (Settings → Display)

- Fault: opening `/settings` then `/settings/display` cannot stack (peer routes); first Back left the cover.
- Fix: `openSettings` opens Display section as its own modal. Header: Done, title, All Settings. Category PrefSelect jumps sections. Hub still via All Settings.
- Evidence: stamp `2026-11-17T191353`; tree shows `wawona-settings-display` + Go to Display after gear tap. Grade green (no-rebuild after tip; rebuild first-shot can miss asleep window).
- Aggregate **~85**. Gate 90 not met.


## Iteration 14 — 2026-11-17 (Sort PrefSelect)

- Fault: Sort `role=menu` under agent mode paints at 0,0 (tap sort-by-kind outside viewport).
- Fix: header PrefSelect Sort (Name/Kind/Status) + ascending toggle. Removed sort-menu popover.
- Settings Display land + NSSegmented filter hold. Stamp `2026-11-17T191702`; aggregate **~86**. Gate 90 not met.


## Iteration 15 — 2026-11-17 (status colors)

- Execution/Readiness values use system color tokens (Running green, Planned orange, Failed red). no-tells clean.
- Stamp `2026-11-17T191935`; aggregate **~86**. Gate 90 not met.
- Open: catalog NSToolbar; dedicated Settings window deferred; VoiceOver; Liquid Glass.

## Iteration 16 — 2026-11-17 (Display prefs stack)

- Fault: Category PrefSelect section wrapped Display `section`, so PrefSwitch rows flowed sideways (same Y, rising X; overflow past sheet).
- Fix: Category jump lives in the section header beside Done / All. Pref sections are list siblings again. Layout: pref rows y=155,192,229,266,305 width 520.
- Aggregate **~87**. Gate 90 not met.

## Iteration 17 — 2026-11-17 (full-bleed + grade wait)

- Tried stripping flex/box-sizing on browser rows for native faces; shrink-to-fit returned (~110pt). Restored `width=100%` flex rows (contextmenu keeps bare).
- Grade rebuild: 2.5s wall sleep after tip rebuild + `clock +1500 real` + search focus before first window screenshot (CGWindow asleep flake).
- Aggregate **~87**. Gate 90 not met.
- Open: catalog NSToolbar (Exact host); dedicated Settings window deferred; VoiceOver; Liquid Glass.

## Iteration 18 — 2026-11-17 (profiles caption + display wake)

- Compact + wide Machines headers: profiles count uses `-exact-subheadline` / `-exact-secondary-label`.
- Grade flake root cause: `system_profiler` `Display Asleep: Yes`. `caffeinate -d` holds wake but does not wake an already-asleep panel. Grade now HID-pokes (F5/Esc via System Events) + `caffeinate -u` then `-dims -w` parent.
- Stamp `2026-11-17T193651` (pre-badge); dark PNGs earlier. Aggregate **~88**. Gate 90 not met.

## Iteration 19 — 2026-11-17 (sidebar badge, no title smash)

- Fault: SidebarMac `TabFace` titles from `aria-label`, so rows showed `Native Shell, Ready` / `Sessions, 1 open`.
- Fix: direct paragraph title (`Sessions` / `m.name`); one filled child with one text = sourceList badge (`Ready` / `Planned` / session count). Running stays green dot (no text; not a second badge).
- Settings section header: title `flex=1`; PrefSelect label `Go` (less crowding).
- Evidence: stamp `2026-11-17T194146-catalog.png`; `state window` sidebar `title=Native Shell` `badge=Ready`, Sessions `badge=1`.
- Aggregate **~89**. Gate 90 not met.
- Open: catalog NSToolbar (Exact host); dedicated Settings window deferred; VoiceOver rotor; Liquid Glass.

## Iteration 20 — 2026-11-17 (lock screen blocker + polish)

- Host macOS login screen (password). `CGWindowListCreateImage` empty + `Display Asleep: Yes` until unlock. Grade screenshots blocked. Tree/state still work (sidebar badges hold).
- `machineDisplayIcon` prefers `m.icon`. Term uses portable `symbol:compose` (differentiates from Native Shell `document`; `symbol:terminal` not a role; `sf/terminal` left sidebar `symbol:null`).
- Microcopy: planned Start / Dependencies captions more action-oriented.
- Next: unlock session → `cargo xtask agent grade macos --rebuild`; keep NSToolbar/Liquid Glass/VoiceOver open.

## Iteration 21 — 2026-11-17 (rebuild green + dark prefer)

- After unlock: `cargo xtask agent grade macos --rebuild` stamp `2026-11-17T195033`. Inspector shows new planned/Deps captions. Sidebar badges hold.
- Dark evidence: `prefer prefers-color-scheme dark` then window shots → `dark-catalog.png` / `dark-inspector-planned.png` (absolute path under Wawona artifacts).
- Aggregate **~89**. Gate 90 not met (NSToolbar Exact-host; VoiceOver rotor; Liquid Glass; Settings window deferred).

## Iteration 22 — 2026-11-17 (Term compose + header gap)

- Stamp `2026-11-17T195312`: Term `symbol:compose` → sidebar SF `square.and.pencil` (vs Native Shell `doc.text`).
- Machines headers (`wawona-machines-header` / browser header): `gap=8` so profiles caption is not superscript-jammed into title.
- Grade wake: HID F5 + `caffeinate -u` then `-dims -w` (login lock / Display Asleep still flaky).
- Aggregate **~89**. Gate 90 not claimed.

## Iteration 23 — 2026-11-17 (search overflow + Danger Zone)

- Fault: `gap=8` pushed `machines-search` outside detail pane (`tap … outside the detail's pane`).
- Fix: browser header `flex-wrap=wrap`; search `flex=1 min-width=160`.
- Danger Zone footer = delete guidance; machine summary moved to About section.
- Stamp `2026-11-17T200725` rebuild green. Tree: Danger Zone / Delete Machine / About.
- Aggregate **~89**. Gate 90 not claimed.

## Iteration 24 — 2026-11-17 (danger shot + stable grade)

- Partial grade produced `2026-11-17T200838-inspector-danger.png` (Delete Machine + About scrolled into view). Platform delete sheet Cancel sits outside agent chrome (tap/type Escape fail).
- Grade ops leave danger dialog out; keep PNG as evidence. Latest stable rebuild green after that.
- Aggregate **~89**. Gate 90 not claimed (NSToolbar / VoiceOver rotor / Liquid Glass / Settings window).

## Iteration 25 — 2026-11-17 (NSButton glass)

- Machines chrome: New / Settings / Sessions use `buttonStyle="glass"`.
- Evidence: `layout machine-add` → native `style=glass` `drawn=glass` `view=NSButton` (Exact maps to `NSButton.BezelStyle.glass` when `LinkedDesign.liquidGlass` on macOS 26+).
- Stamp `2026-11-17T201224` rebuild green. Dense list stays opaque.
- Aggregate **~90**. `gate_met` **false** (catalog NSToolbar Exact-host; VoiceOver rotor; Settings window product-deferred).

## Iteration 26 — 2026-11-17 (VoiceOver hints)

- `aria-description` on New / Settings / Sessions (maps to accessibilityHint).
- Rebuild grade green. Rotor still UNVERIFIED (needs live VoiceOver).
- Aggregate **~90**. `gate_met` false.

## Iteration 27 — 2026-11-17 (inspector glass actions)

- Inspector header actions (Settings, Save, Stop, Open, Start / Start Unavailable) use `buttonStyle="glass"`.
- Rebuild grade green. Catalog + inspector chrome on NSButton glass path.
- `layout wwn.machines.start` (planned): `drawn=glass` and `windowToolbar` `NSToolbarItem` (`exact.command.*`) when a machine is selected. Catalog placeholder still cannot project NSToolbar (Exact host).
- Aggregate **~90**. `gate_met` false (catalog NSToolbar; VoiceOver rotor).

## Iteration 28 — 2026-11-17 (DisplayWakeGuard)

- Mid-grade CGWindow empty (display asleep during settings shot). `DisplayWakeGuard` in `xtask/src/exact_agent.rs`: initial HID poke, parent `caffeinate -dims -w`, periodic F5/`caffeinate -u`.
- Rebuild grade green after wake harden.
- Aggregate **~90**. `gate_met` false.

## Iteration 29 — 2026-11-17 (Danger Zone on-screen)

- Folded planned Dependencies into Status; moved Danger Zone above Session kind.
- Pin / Tags copy shows tap affordance (`Off · tap to pin`, `Work · edit`).
- Evidence: `2026-11-17T202451-inspector-planned.png` and `2026-11-17T202601-inspector-planned.png` show full **Delete Machine** in viewport.
- Grade harness: chunked agent passes + real clocks before settings screenshots (CGWindow flake).
- Stamp **2026-11-17T202601** full shot set complete.
- Aggregate **~91**. `gate_met` false (catalog NSToolbar Exact-host; VoiceOver rotor).

## Iteration 30 — 2026-11-17 (wake Escape bug)

- `DisplayWakeGuard` periodic Escape dismissed Settings sheets → empty CGWindow.
- F5-only poke + chunked grade: green end-to-end.
- Aggregate **~91**. `gate_met` false.

## Accepted deferrals (explicit)

- **Catalog NSToolbar:** **CLOSED** (iter 35-36). Compact projects; Exact `HeaderMac` placeholder→beside projects wide New/Settings/Sessions as `exact.command.*`.
- **Dedicated Settings window:** Product rule = in-app gear cover (modal/sheet). Not Machines|Settings tablist. Audit P1 dedicated scene deferred.
- **VoiceOver rotor:** Hints wired (`aria-description`); rotor UNVERIFIED without live VO session.

## Iteration 31 — 2026-11-17 (PrefSwitch Pin)

- Inspector Pin is `PrefSwitch` (`switch-detailPin`) via `setPresentPinned`.
- Rebuild grade green.
- Aggregate **~91**. `gate_met` false.

## Iteration 32 — 2026-11-17 (dark appearance evidence)

- Dark catalog + planned inspector: `2026-11-17T202946-catalog-dark.png`, `…-inspector-planned-dark.png` (`prefer prefers-color-scheme dark` + longer settle after theme flip).
- Compact `720x560` + large `1280x900` catalog: `…-catalog-compact.png`, `…-catalog-large.png`.
- Aggregate **~91**. `gate_met` false.

## Iteration 33 — 2026-11-17 (destructive Delete color)

- Danger Zone `Delete Machine` uses `-exact-system-red` when enabled.
- Rebuild grade green.
- Aggregate **~92**. `gate_met` false.

## Iteration 34 — 2026-11-17 (Settings icon palette)

- Settings hub icons: restrained system blues / indigo / orange / gray / teal (audit P2 rainbow).
- Rebuild grade green.
- Ready Native Shell: `layout wwn.machines.start` → `drawn=glass` `enabled=true` + `windowToolbar` `NSToolbarItem`.
- Aggregate **~92**. `gate_met` false.

## Iteration 35 — 2026-11-17 (catalog NSToolbar on compact)

- Moved Sort/search out of Machines header (chrome-only: New / Settings / Sessions).
- Narrow `640x700` (`not isWide`): `state.window.toolbar` projects `exact.command.*` for New/Settings/Sessions (`headerKept=null`). Evidence: layout `machine-add` → `windowToolbar` `NSToolbarItem`.
- Wide split placeholder still Exact-host blocked (painted glass chrome).
- Tried list-column header for wide toolbar: sourceList traps taps (`view is in the authored tablist`). Reverted; placeholder chrome restored.
- Aggregate **~93**. `gate_met` false (wide catalog NSToolbar; VoiceOver rotor).

## Iteration 36 — 2026-11-17 (wide catalog NSToolbar)

- Exact `HeaderMac.splitHeaderRoutes`: when detail is nil, `beside = split.shownPlaceholder` so placeholder header buttons project.
- Wide `900x700` grade: toolbar items `exact.split.separator` + `exact.command.*` for New / Settings / Sessions. `layout machine-add` → `windowToolbar` `NSToolbarItem`.
- Catalog PNG: New/Settings/Sessions sit in the window toolbar (not a painted empty-state cluster).
- Aggregate **~88-94** heuristic (scorecard JSON). `gate_met` false (VoiceOver rotor).

## Iteration 37 — 2026-11-17 (stable toolbar grade)

- Tip grades keep `exact.command.260/263/265` on catalog.
- Scorecard dimensions re-rated in stamp JSON (native conventions / desktop interaction up).
- Browser row subtitle uses `-exact-subheadline` + secondary label (contrast).
- Weighted heuristic **~90**. `gate_met` false until live VoiceOver rotor.

## Iteration 38 — 2026-11-17 (⌘, Settings)

- `type machines-search key Meta+,` opens Settings sheet (`attached=["SheetWindow"]`). PNG: `…-settings-meta-comma.png`.
- Aggregate **~90**. `gate_met` false (VO rotor).

## Iteration 39 — 2026-11-18 (ALL_TARGETS concept pack)

- Imported owner zip → `docs/ui-quality/platform-concepts/` (13 PNGs + README).
- Agent index maps each file to `platforms.json` id. `Android_XR.png` = extra (not ALL_TARGETS yet).
- Hard filter: concepts must not override Exact Contract or Settings/machine-type rules (no Machines|Settings tablist; no Start-on-planned).
- `target-matrix.json` v2 links `concept` per target. `graded` still evidence-only.
- Next: grade remaining Exact hosts against own concept + contract (iOS / iPadOS / Android first after macOS).

### Matrix notes (stamp 202946)

| Dimension | Evidence |
|---|---|
| Light / dark | Grade PNGs + `*-catalog-dark.png` / `*-inspector-planned-dark.png` |
| Compact / large | `*-catalog-compact.png` / `*-catalog-large.png` |
| Planned + Start gated | `*-inspector-planned.png` (Start Unavailable + PrefSwitch Pin + Danger Zone) |
| Running | Term row green dot + `…-inspector-running.png` (Stop glass + NSToolbarItem) |
| Starting / Failed | NOT TESTED (needs live Relay phase; do not fabricate) |
| VoiceOver rotor | UNVERIFIED |
| Wide NSToolbar | `exact.command.*` on catalog (Exact HeaderMac placeholder beside) |
| Catalog NSToolbar | Deferred (Exact host) |
