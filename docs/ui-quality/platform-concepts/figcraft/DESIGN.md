# Wawona ALL_TARGETS FigCraft design

Skills in force: `wawona-ui-skills`, `frontend-design`, `impeccable` (Operate),
`figcraft-design`, `better-ui` / `better-colors` / `better-typography`,
`ui-ux-pro-max` as needed. Exact handoff later: visual rules only, no Tailwind.

## Brief

- **Product:** Wawona Compositor. Universal Wayland compositor + Machines hub.
- **Audience:** developers / operators starting Native Shell, VM, Container sessions.
- **Primary job:** browse machines, open session, configure via Settings cover.
- **Mode:** Operate (impeccable). Native idioms per host. Concept PNGs = approved comps.
- **References:** `../` concept pack (2026-11-18). Comps win over agent taste.

## One memorable thing

Frosted glass Machines deck over a valley landscape. Neon status. Bridge mark.

## Tone

valley-glass, trail-map dense, neon-status

## Metaphor

Wawona footbridge: left bank = library, span = machine list, right bank = inspector.

## World (from comps, not SaaS defaults)

| Axis | Choice |
|---|---|
| Material | Translucent charcoal-violet glass over photo landscape (not flat #12101C admin) |
| Accent | Electric blue / violet neon for selection + primary CTA |
| Status | Green Running, grey Stopped, blue Ready |
| Type | SF-class sans (FigCraft: system / Inter only if SF missing). Display bold, body regular |
| Density | Operate-dense. Real machine names, real specs |
| Per host | macOS Aqua glass · iOS Liquid Glass phone · iPad multi-window · Android Material glass · Windows Fluent · Linux GTK · watch glance · tvOS focus hero · vision spatial panes |

## Product constraints (hard)

1. Settings = gear cover. Never Machines|Settings peer root tab.
2. Machines kinds = Native Shell / Virtual Machine / Container only.
3. Images / Runtimes may appear as Library destinations in concepts; not type-picker kinds.
4. Shared semantics; diverge chrome per platform PNG.
5. No annotation footnotes inside product chrome.

## Tokens (Dark deck, sampled from `macOS.png`)

| Token | Hex | Notes |
|---|---|---|
| landscape | photo | Valley still — magenta/violet must bleed through glass |
| glass | `#1C2440B8` | Blue-navy frosted panel (not charcoal) |
| glass-hi | `#2A3458C8` | Raised chips / rows |
| veil | `#1A104828` | Light blue-violet — keep titlebar reading lavender |
| fg | `#F5F7FF` | Primary text |
| muted | `#A8B0C8` | Secondary |
| border | `#D0C8E838` | Cool rim light |
| primary | `#0078F8` | Open Session / mark (concept electric blue) |
| select | `#3A90DF` | Selected row stroke |
| on-primary | `#FFFFFF` | |
| running | `#38E078` | |
| stopped | `#8E96A8` | |
| ready | `#48C8F8` | |
| pill | `#C8B0E028` / on `#E8D0F055` | Segmented nav wash |
| radius-card | 14–16 | |
| radius-control | 10–12 | |
| radius-pill | 999 | |

Light mode: reserved for Windows Fluent / web light comps when those frames ship.

## Anti-patterns (banned here)

- Flat dark admin clone stamped on every preset
- White auto-layout frames with light text
- Missing thumbnails / heroes present in the comp
- Purple-gradient SaaS card kit unrelated to the valley glass world
- Inter-only + cream/terracotta Claude-default kit
- Product footnotes (“concept only”, “gear cover”) drawn inside chrome

## Acceptance

- [x] macOS editable near `macOS.png` IA (valley glass, pill nav, gear cover, thumbs)
- [x] Concept plates for every ALL_TARGETS id (+ Android XR)
- [ ] iOS editable near `iOS.png` (next)
- [ ] Other hosts editable from their concept plates
- [ ] Human accept export vs `refs/` side-by-side
- [ ] Exact later: tokens → roles only (`no-tells`)

## Rebuild order

1. macOS (flagship Operate desktop)
2. iOS (phone Liquid Glass)
3. iPadOS / Android tablet
4. Windows / Linux / Web
5. tvOS / visionOS / watches
