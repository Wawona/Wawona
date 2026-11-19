---
name: wawona-exact-ui-design
description: >-
  Mandatory UI/UX agent-skill gate for Wawona Exact Contract chrome. Load
  installed global design skills (frontend-design, impeccable, ui-ux-pro-max,
  better-*, web-design-guidelines, frontend-ui-engineering) then apply only
  Contract-safe rules. Use before editing apps/wawona/app.contract or Exact
  chrome grading.
---

# Exact UI design skills (mandatory)

Wawona Machines/Settings chrome is **forced Exact**. Design craft comes from
global agent skills. **Output stays Contract**, never React / JSX / Tailwind.

## Install / refresh (operator)

```bash
npx skills@latest add https://github.com/anthropics/skills --skill frontend-design -g -a cursor -y
npx skills@latest add https://github.com/pbakaus/impeccable -g -a cursor -y
npx skills@latest add https://github.com/nextlevelbuilder/ui-ux-pro-max-skill -g -a cursor -y
npx skills@latest add https://github.com/jakubkrehel/skills -g -a cursor -y
npx skills@latest add https://github.com/vercel-labs/agent-skills -g -a cursor -y
npx skills@latest add https://github.com/addyosmani/agent-skills -g -a cursor -y
```

Skills land under `~/.agents/skills/`. Symlink into `~/.cursor/skills/<name>`
if discovery misses them.

## Before any Exact Contract / chrome edit

Read **in this order**, then edit:

1. Exact checkout `AGENTS.md` + `docs/start-here.md` (LLP 1115 / no-tells).
2. `wawona-exact-contract` + Exact `llp-orient` (structure).
3. `wawona-exact-forced` + `wawona-ui-five-layers` +
   `wawona-platform-native-interaction`.
4. **Design skills** (global):
   | Skill | Use for |
   |-------|---------|
   | `frontend-design` | Creative brief: hierarchy, density, distinct POV |
   | `impeccable` | Critique / polish / distill / audit playbooks |
   | `ui-ux-pro-max` | Compare style systems before picking one |
   | `better-ui` / `better-layout` / `better-typography` / `better-colors` / `better-accessibility` | Craft: optical alignment, rhythm, contrast |
   | `web-design-guidelines` | A11y, focus, responsive stability audits |
   | `frontend-ui-engineering` | Component structure + WCAG mindset (map to Contract, not React) |

5. Query `wwn-mcp` for product gates. Verify with Exact CLI /
   `cargo xtask agent`.

## Apply vs discard

| From design skills | Into Exact Contract |
|---|---|
| Hierarchy, grouping, progressive disclosure | `header` / `section` / `tablist` / routes / lists |
| Spacing rhythm, optical density | Structure + unsaid platform metrics (no px tells) |
| Semantic roles / emphasis | `-exact-*` text styles / system colors only |
| A11y labels, focus order, empty states | `testId`, titles, one primary action |
| Palette / Inter / purple gradients / card grids | **Discard** for Contract (no-tells; platform paints) |
| React, Tailwind, JSX, CSS modules | **Hard reject** |
| Hex / `font-size` / `font-weight` in Contract | **Hard reject** (`no-tells.mjs`) |

**Wawona wins on conflict.** Exact no-tells + forced Exact + platform-native
interaction beat upstream skill examples that emit web CSS or RN.

## Verify

```bash
cd <exact>
bun scripts/exact.mjs contract build apps/wawona/app.contract --json --errors-only
bun scripts/no-tells.mjs apps/wawona
# from Wawona/
cargo xtask agent grade macos --rebuild
```

## Hard rejects

- Editing Exact chrome without reading this skill + `frontend-design` (or
  `impeccable` for polish/critique)
- Installing Expo RN / EAS skills as a substitute for Exact CLI
- Pasting Tailwind/React from design skills into `app.contract`
- Hex / font-size / font-weight tells in Contract
- Pixel-parity across ALL_TARGETS as the pass bar

## Related

- `wawona-exact-contract`, `wawona-exact-forced`, `wawona-ui-five-layers`
- Exact `AGENTS.md`, `docs/start-here.md`, `apps/shelf/app.contract`
