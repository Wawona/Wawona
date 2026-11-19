# Wawona Compositor — macOS Native UI/UX Remediation Specification

> **Cursor agent entrypoint.** Treat this document as an implementation and verification specification, not as permission to rewrite unrelated architecture. Inspect the repository before making changes. Preserve the Rust core and cross-platform contracts. Implement the macOS presentation according to native macOS conventions, and verify behavior with a running application.

**Audit date:** 2026-11-17  
**Target declared by project owner:** macOS 27 / SDK 27 / Xcode 27  
**Evidence:** Four supplied screenshots; no source code or live interaction was examined.  
**Baseline heuristic score:** **38/100 (F)**; proposed next milestone **75+**, release target **90+**. These are subjective audit targets, not empirical usability-study measurements.  
**Important:** SDK 27-specific APIs have not been independently verified in this document. Inspect the installed SDK, headers, release notes and compiler before choosing API symbols. Prefer native system-managed materials and behavior, not simulated glass.

## Agent mission and operating constraints

1. Discover the current UI architecture (AppKit, SwiftUI, generated Exact contracts, or mixed). Identify which files own navigation, machine state, settings, and session windows.
2. Establish a reproducible baseline: build, launch, screenshot every reachable view, inspect accessibility trees and test actual interactions. Record commands, device/OS versions, build errors and findings.
3. Fix P0 issues first, then P1, then P2. Make small reviewable changes; do not break existing machine/session functionality.
4. Follow **host-platform conventions**. Shared Rust/contract semantics do not imply identical visual layouts on iOS, Android, macOS or other targets.
5. For every change: build → launch → exercise mouse/keyboard/accessibility → capture before/after → compare → run regression tests. Iterate until gates pass or record an explicit blocker.
6. Do not claim a behavior passes without observing or testing it. Do not claim a screenshot proves the underlying implementation uses or does not use Liquid Glass.
7. Do not delete user machines, change persistent user data, publish releases, or perform irreversible actions without authorization. Use test profiles.

## Supplied evidence: annotated by screenshot

### Screen 1 — Machines overview (22/100)

![Machines overview](assets/screenshot-01.png)

**Observed:** Five machine profiles appear in the sidebar, but the main pane says “Select a Machine” and is largely empty. Add, Settings, Tabs, sort, search and All/Pinned/Tag controls appear in a central empty-state cluster.

**Fix:** Build an actual machine browser in the content pane. Move persistent commands to a native toolbar or appropriate browser controls. A welcome/empty state is valid only when the library truly has no entries or nothing matches a filter. Show machine name, type, execution state, runtime readiness, connection and contextual actions.

### Screen 2 — Sample Linux VM (42/100)

![Sample Linux VM](assets/screenshot-02.png)

**Observed:** “Sample Linux VM” is repeated in titlebar, heading and Name row. Page heading and grouped rows have different leading edges. Status says `Stopped`; Runtime says `NixOS · planned`; `Start` appears prominently enabled. Large simple form rows stretch across the window. Pin and Tags do not show clear controls.

**Fix:** Separate *runtime capability/readiness* from *machine execution state*. Gate Start based on actual capability and dependencies; explain unavailable actions. Use a compact inspector for status and actions, with a dedicated configuration editor. Align heading and sections on a common content guide.

### Screen 3 — Dev Container (40/100)

![Dev Container](assets/screenshot-03.png)

**Observed:** Same alignment and oversized form problems. Runtime `OCI · planned` alongside `Stopped` and a prominent `Start`. Pin is an unlabeled row without an evident affordance; Tags is `None` without a visible editor. Delete appears in an ordinary Actions group. Relay dependency information is detached from Start.

**Fix:** Show dependencies beside relevant actions; distinguish read-only values from editors; put destructive operations in a distinct section or context menu with appropriate confirmation. Use a visible pin toggle/menu and tag editor.

### Screen 4 — Settings (48/100)

![Settings modal](assets/screenshot-04.png)

**Observed:** Large modal containing nine settings categories (Display, Input, Graphics, Env Vars, iCloud Sync, Waypipe, SSH, About, Dependencies) and unused space. Done button sits next to Settings title. No settings detail view is shown.

**Fix:** Implement a dedicated native macOS Settings scene/window, accessible through the app menu and `⌘,`. Each category must navigate to its actual settings controls. Avoid a generic modal for global preferences. Verify proper focus, accessibility and window sizing.

## Quantified screenshot geometry

The source screenshots are approximately 1312 × 1138 pixels. The app window spans roughly x=65–1247 and y=44–1065, or **1182 × 1021 screenshot pixels**. These are *screenshot pixels*, not guaranteed AppKit points.

| Element | Approximate screenshot measurement | Finding |
|---|---:|---|
| Sidebar | 230 px | Reasonable initial width; should be resizable |
| Main pane | 952 px | Severely underutilized on overview |
| Machine detail grouped form | 810 px | Too wide for sparse key/value content |
| Detail heading leading edge | x≈295 | Inconsistent with grouped content |
| Section/form leading edge | x≈366–378 | ~70–80 px shift from heading |
| Overview controls cluster | x≈602–940 | Commands misplaced in empty state |
| Settings modal | ~643 × 558 px | Excessively spacious for a category list |

**Starting design targets (not Apple-mandated constants):** resizable sidebar 220–280 pt; main content padding 24–32 pt; detail maximum width 640–760 pt; section spacing 24–32 pt; grouped rows approximately 36–44 pt as appropriate to native controls; native toolbar intrinsic sizes. Test small windows, accessibility scaling and localization rather than hardcoding these numbers.

## Scorecard (weighted heuristic assessment)

| Dimension | Score /100 | Weight |
|---|---:|---:|
| Information architecture | 25 | 15% |
| Navigation and discoverability | 35 | 15% |
| Desktop interaction design | 30 | 15% |
| Layout and spacing | 38 | 15% |
| Visual hierarchy | 48 | 10% |
| Native macOS conventions | 40 | 10% |
| State and action clarity | 30 | 10% |
| Typography and legibility | 58 | 5% |
| Visual consistency | 60 | 5% |

The headline grade of 38 is an editorial assessment; do not present it as an instrument-derived measurement. Re-score using the same rubric and include screenshot/test evidence.

## Full defect register

| Priority | Area | Fault | Required remedy |
|---|---|---|---|
| P0 | Machine overview | No meaningful overview despite existing profiles | Machine list/table with metadata and actions |
| P0 | Empty state | Persistent commands embedded in empty-state cluster | Native toolbar/browser controls |
| P0 | Start | Appears available for planned runtime | Capability-gated actions with explanations |
| P0 | Status | Stopped and Planned are semantically conflated | Separate runtime support, readiness, connection and execution state |
| P0 | Inspector | Pin and Tags lack visible edit affordances | Native toggles, menus, editors as appropriate |
| P1 | Navigation | Machines and sessions lack clear separation | Distinct library and active-session destinations |
| P1 | Titles | Repeated machine title | One dominant heading, restrained titlebar |
| P1 | Alignment | Heading and sections have different leading edges | Shared layout guide |
| P1 | Width | Simple forms occupy huge width | Readable max width; adaptive layout |
| P1 | Sidebar | No state/secondary metadata | Compact state or metadata where useful |
| P1 | Toolbar | No conventional command toolbar | New, Start, Search and contextual actions |
| P1 | Search | Only visible when nothing selected | Persistent search in machine browser |
| P1 | Filters | Disconnected All/Pinned/Tag cluster | Coherent filter toolbar/menu |
| P1 | Settings | Global settings presented as category-only modal | Dedicated Settings scene/window |
| P1 | Delete | Destructive action buried in generic group | Explicit destructive action and suitable confirmation |
| P1 | Editing | Name and Kind editability ambiguous | Native fields, menus and read-only presentation |
| P1 | Feedback | No visible loading/failure/recovery examples | Starting/Running/Stopping/Failed/Unsupported states |
| P1 | Sessions | “Tabs” command ambiguous | Open Session and native tab/window conventions |
| P1 | Dependencies | Relay requirement buried in footnote | Contextual readiness/dependency panel |
| P2 | Typography | Faint secondary text | Semantic styles, contrast verification |
| P2 | Icons | Faint, poorly differentiated machine icons | Meaningful SF Symbols and consistent weight |
| P2 | Settings icons | Arbitrary saturated colors | Purposeful semantic/accent colors |
| P2 | Spacing | Huge blank areas beside dense groups | Adaptive content density |
| P2 | Control style | Menu-like controls resemble disabled pills | Native controls with clear affordances |
| P2 | Microcopy | Implementation-centric explanatory text | Actionable, user-centric explanations |

**Evidence distinction:** All above are visual/semantic observations or inferred risks. Keyboard, VoiceOver, menu behavior, actual Start gating, state restoration, performance and true SDK material usage remain **UNVERIFIED** until live testing.

## Proposed navigation architecture

```text
Wawona main window
├── Native unified toolbar
│   ├── New Machine (with supported-type choices)
│   ├── Search / filter / sort (context-sensitive)
│   ├── Start / Stop / Open Session (context-sensitive, capability-gated)
│   └── Inspector toggle
├── Resizable navigation sidebar
│   ├── Machines
│   ├── Sessions
│   ├── Pinned
│   └── Recent (only if genuinely useful)
├── Main content
│   ├── Machine browser: list/table of all profiles
│   └── Optional focused detail/configuration view
└── Optional collapsible inspector
    ├── Identity, type, tags
    ├── Runtime support and dependencies
    ├── Execution and connection state
    └── Contextual actions

Separate native Settings scene/window (⌘,)
Separate session windows/tabs using native macOS semantics
```

### Schematic demonstration

![Proposed browser and inspector wireframe](assets/proposed-layout.svg)

This is an **information-architecture wireframe**, not a pixel-perfect Liquid Glass mockup. In a narrow window the inspector should collapse or move to a separate presentation.

## State model and action rules

Avoid a single string that conflates readiness and execution. Inspect the actual Rust contract before changing types; adapt existing APIs carefully.

```text
runtimeSupport: supported | planned | unsupported | unknown
readiness: ready | missingDependency | configurationRequired | checking | failed
execution: stopped | starting | running | stopping | failed
connection: local | remote | disconnected | connecting | error
```

Examples:
- `planned + stopped`: show “Runtime planned”; disable Start with explanation, not a fake working button.
- `supported + missingDependency + stopped`: show which dependency is missing, offer a safe setup/retry path.
- `supported + ready + stopped`: Start enabled.
- `supported + ready + starting`: Start disabled; progress indicator; cancellation only if supported.
- `supported + ready + running`: show Open Session and Stop as appropriate.
- `failed`: show error details, log access, retry and recovery.

State transitions must be validated against real backend behavior; do not invent machine functionality merely to make the UI appear complete.

## Native macOS and Liquid Glass rules

- Use system-managed window chrome, toolbars, sidebar styling, materials, popovers, menus and focus where appropriate.
- Use native AppKit APIs such as `NSWindow`, `NSToolbar`, `NSSplitViewController`, `NSTableView`/`NSOutlineView`, `NSVisualEffectView` when appropriate; SwiftUI equivalents may include `NavigationSplitView`, `Table`, `List`, `Form`, `Settings`, `.toolbar`, `.searchable` and inspector presentation.
- Use actual SDK-supported Liquid Glass APIs only where their semantics fit; **verify availability against installed SDK 27**. Do not simulate Liquid Glass with arbitrary blur, gradients, strokes or translucent rounded cards.
- Keep dense machine/console content legible on mostly opaque surfaces. Do not put decorative glass over Wayland client content.
- Honor light/dark appearance, system accent, high contrast, reduced transparency, reduced motion, accessibility scaling and localization.
- Use SF Symbols with consistent visual weight; do not make color the sole state indicator.
- Prefer intrinsic native sizing and adaptive layout over screenshot-specific absolute coordinates.

## Interaction acceptance checklist (live tests required)

- [ ] Window resize, minimize, zoom, close, restore, fullscreen and state restoration
- [ ] Sidebar navigation, selection persistence, keyboard navigation and correct focus
- [ ] Tab, arrow, Return, Escape, Delete and relevant Command shortcuts
- [ ] Right-click/context menus on machines and sessions
- [ ] Command-click and Shift-click multi-selection if batch operations are supported
- [ ] Drag/drop or reorder favorites only if meaningful and implemented
- [ ] Search focus, filtering, clear action, zero-results state and selection preservation
- [ ] Native toolbar enable/disable state, tooltips and customization where appropriate
- [ ] Visible focus and no keyboard traps
- [ ] VoiceOver labels, roles, values, hints, focus order and full keyboard access
- [ ] Light/dark, accent, contrast, reduced motion and transparency settings
- [ ] Startup/progress/error/retry/cancellation and crash recovery
- [ ] Open, reconnect, detach and close sessions; multiwindow and tabs
- [ ] Application/File/Edit/View/Window/Help menus with appropriate commands
- [ ] Safe destructive operations, confirmation and undo where feasible
- [ ] Settings scene opens via application menu and `⌘,`
- [ ] Planned/unsupported machines never misleadingly appear runnable
- [ ] Window sizes: compact, typical laptop, large desktop; screenshots at each

## Mandatory test matrix

For each of **Machines overview, Native Shell, Term, Dev Container, Relay Wasm, Sample Linux VM, Settings and every reachable session view**, record:

| Test dimension | Required evidence |
|---|---|
| Appearance | Screenshots in dark and light mode |
| Sizing | Compact, default and large window captures |
| State | Ready, stopped, starting, running, failed, planned/unsupported where applicable |
| Input | Pointer, keyboard and contextual menu interaction |
| Accessibility | Accessibility-tree capture, VoiceOver inspection and focus sequence |
| Regression | Build/test command, pass/fail, logs and before/after comparison |

Never fabricate a runtime state to mark a test as passing. Mark unavailable scenarios `NOT TESTED` with reason.

## Implementation order

### Phase 0 — Baseline and architecture discovery
- Map UI entrypoints, generated files, Exact contracts, Rust machine/session types, AppKit/SwiftUI ownership.
- Record installed Xcode/SDK and supported APIs. Build and launch the existing app.
- Capture baseline screenshots and test results. Establish safe sample profiles.

### Phase 1 — P0 structural repair
- Implement a real Machines browser, native toolbar and persistent search/filter.
- Model capability/readiness/execution separately in presentation and action gating.
- Make Pin and Tags unmistakably interactive or explicitly read-only.

### Phase 2 — Native macOS navigation and inspector
- Resizable sidebar and appropriately bounded inspector.
- Separate browsing, inspecting, editing and session display.
- Align all page content to a consistent grid; remove redundant headings.

### Phase 3 — Settings and interaction completeness
- Native Settings scene and `⌘,`.
- Keyboard, context menus, accessibility, multiwindow/tab behavior, recovery states.

### Phase 4 — System visual polish
- Native toolbar, materials, Liquid Glass where supported and appropriate.
- SF Symbols, typography, density, contrast, appearance adaptations.

### Phase 5 — Regression and quality gate
- Test all target macOS views and states. Capture before/after screenshots.
- Fix P0 and P1 regressions. Produce a final scorecard and unresolved-issues log.

## Release quality gates

- **Zero unresolved P0** usability or misleading-state defects.
- **Zero inaccessible primary workflows** in supported functionality.
- **Zero known broken keyboard/focus paths** for core operations.
- **Zero critical clipping/overflow** in tested sizes and accessibility modes.
- **Zero known major native navigation violations**.
- **No known visual regressions** against approved baselines.
- Heuristic score **≥90/100** is a secondary target, not a substitute for passing tests.

## Required agent report format

At the end of every iteration, append to `UI_AUDIT_PROGRESS.md`:

```markdown
## Iteration N — YYYY-MM-DD
- Platform/OS/SDK/Xcode:
- Git commit/base:
- Screens and states tested:
- Changes (file paths and rationale):
- Before screenshots:
- After screenshots:
- Build/test commands and results:
- Accessibility/keyboard results:
- P0/P1/P2 open and closed:
- Scorecard with evidence:
- Regressions:
- Unverified claims / blockers:
- Next highest-priority action:
```

## Reference links for the agent

These are official starting points, **not proof that a particular SDK 27 API exists**. Verify current documentation and installed SDK symbols.

- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [Apple Design: Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/liquid-glass)
- [AppKit documentation](https://developer.apple.com/documentation/appkit)
- [SwiftUI documentation](https://developer.apple.com/documentation/swiftui)
- [NSToolbar](https://developer.apple.com/documentation/appkit/nstoolbar)
- [NSWindow](https://developer.apple.com/documentation/appkit/nswindow)
- [NSVisualEffectView](https://developer.apple.com/documentation/appkit/nsvisualeffectview)
- [NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview)
- [Apple Accessibility](https://developer.apple.com/accessibility/)
- [SF Symbols](https://developer.apple.com/sf-symbols/)
- [Xcode documentation](https://developer.apple.com/documentation/xcode)

## Definition of done

The work is **not done** when the app merely looks more glassy. It is done when the machine browser, inspector, settings and sessions follow native macOS interaction conventions; state/action affordances accurately reflect the runtime; core workflows pass keyboard/accessibility tests; screenshots show consistent responsive layouts; and the evidence-based release gates pass.

---

**Source attribution:** Screenshot descriptions, scores and recommendations originate from the UI audit in the ChatGPT conversation and four images supplied by the project owner. Proposed wireframe and state model are recommendations, not screenshots or verified current architecture.
