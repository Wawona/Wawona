# Exact UI iteration task graph

Diamond loop for macOS Exact Contract chrome. Graph-engineering task half:
workers fix, verifier grades in separate evidence, one merge owner.

```text
        ┌─ contract edit ──────────┐
plan ───┼─ cargo xtask run --rebuild ┼─→ cargo xtask agent grade ─→ merge ─→ next plan
        └─ (optional --open) ──────┘
```

## Nodes

| id | job | reads | writes |
|---|---|---|---|
| plan | Pick top issues from last grade + hard gates | `history/*.json`, rubric | `loop-state.json` |
| contract | Edit `exact/apps/wawona/app.contract` only | plan | contract |
| rebuild | `cargo xtask run macos --rebuild` or `agent grade --rebuild` | contract | `.build/exact/macos/Wawona.app` |
| grade | `cargo xtask agent grade macos` (Exact agent via bun wrap) | tip app, rubric | `history/artifacts/*.png` + score JSON |
| merge | One owner: rank issues, stop or next plan | grade | `loop-state.json` |

## Stop rule

Stop when any of:

1. Catalog + inspector + settings each score ≥ `release_gate_score` (90) and no hard gates.
2. Same top issue twice with no measurable score delta (plateau).
3. `max_rounds` (default 5) reached.

Human gate: commit / push / Ship only. Local tip rebuild and grade need no gate.

## Fake edges (do not serialize)

- Grade does not wait on docs-only edits.
- Compact iOS grade does not block macOS catalog fix.
- Session end-to-end can fan out after catalog hard gate clears.

## Provenance

Every grade JSON stores `build`, `pid`, `evidence`, `extracted_at`.
Loop state stores `round`, `last_score`, `open_issues`, `stop_reason`.
