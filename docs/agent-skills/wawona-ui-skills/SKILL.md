---
name: wawona-ui-skills
description: >
  Router for UI/UX agent skills when designing or polishing Wawona chrome
  (FigCraft concepts, Exact Contract, product hosts). Load before any UI
  visual work. Exact: visual/token/spacing rules only; never React/Tailwind
  output into app.contract.
---

# Wawona UI skills router

## Load order (every UI task)

1. This skill.
2. `figcraft-design` when the deliverable is a `.figcraft` file / ArtCraft MCP.
3. `frontend-design` (Anthropic) for creative direction / anti-slop.
4. `impeccable` for Operate/Read polish, critique, craft floor (`DESIGN.md`).
5. `better-ui` / `better-colors` / `better-typography` / `better-layout` for craft.
6. `ui-ux-pro-max` when comparing style systems or picking a palette/type pairing.
7. `web-design-guidelines` for a11y / focus / contrast audits (web or transferable).
8. Wawona product: `wawona-exact-contract`, `wawona-ui-five-layers`,
   `wawona-platform-native-interaction`, concept PNGs under
   `docs/ui-quality/platform-concepts/`.

## Exact / Contract (hard)

Skills above may show React, Tailwind, or CSS examples. For Exact:

- Take **only** palette, type scale, spacing rhythm, hierarchy, density, a11y.
- Output **Contract** + Taffy / role tokens (`-exact-*`). No hex in Contract
  chrome (`no-tells`). No second Machines UI outside Exact.
- Never paste Tailwind class strings into `app.contract`.

## FigCraft concepts

- Concept PNGs are the **approved comps** (impeccable: build from comp).
- Do not invent a second visual world. Match platform idiom per PNG.
- Product filters still win: Settings = gear cover; Machines kinds =
  Native Shell / VM / Container.
- Ban the skeletal “one dark admin clone on every preset” failure mode.

## Mode

Machines / Settings = **Operate** (impeccable). Scanability and native
expectations outrank marketing flourish. Brand lives in material (glass,
landscape, status neon), not decoration kits.

## Ban list (AI slop)

Inter-only + purple gradient kit, identical card grids, cream/terracotta
Claude-default, annotation footnotes inside product chrome, white
auto-layout frames with light text, missing thumbs/heroes from the ref.

## Where design lives

| Artifact | Path |
|---|---|
| Concept PNGs | `Wawona/docs/ui-quality/platform-concepts/*.png` |
| FigCraft file | `…/platform-concepts/figcraft/Wawona-ALL_TARGETS.figcraft` |
| Design brief | `…/figcraft/DESIGN.md` |
| Exact Contract | sibling Exact `apps/wawona/app.contract` |
