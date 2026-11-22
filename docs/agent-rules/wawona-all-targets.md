# Platform scope (`ALL_TARGETS`)

Authority: repo-root [`platforms.json`](../../platforms.json).

## Aliases

| Alias | Meaning |
|---|---|
| `ALL_TARGETS` | Every product platform in `platforms.json` `aliases.ALL_TARGETS` |
| `APPLE_TARGETS` | iOS, iPadOS, macOS, visionOS, tvOS, watchOS |
| `MOBILE_TARGETS` | iOS, iPadOS, Android |
| `DESKTOP_TARGETS` | macOS, Windows |
| `WEARABLE_TARGETS` | watchOS, Wear OS, AsteroidOS |
| `VEHICLE_TARGETS` | CarPlay, Android Auto (template hosts; entitlement fail-closed) |
| `DISPLAY_TARGETS` | External display (Exact paint, no touch) |
| `TV_TARGETS` | tvOS |
| `WEB_TARGETS` | Web |
| `EXACT_HOSTS` | Targets with an Exact host path today (includes vehicle / external) |
| `SHARED_CORE` | Exact Contract + Rust domain (not a paint host) |

## When a prompt says `ALL_TARGETS`

1. Read `platforms.json` (do not hardcode the list from memory).
2. Discover applicable implementations (Exact Contract, product Swift/Compose, seams).
3. Apply the change on every applicable target.
4. Preserve native conventions; leave Exact chrome look unsaid (`wawona-exact-contract`).
5. Prefer shared Contract / Rust domain over per-toolkit forks.
6. Build, test, and validate each target independently when claimed verified.
7. Report a completion matrix per target.
8. Never silently omit a target. Mark `planned` / `blocked` / `forbidden` / `n/a` with reason.

`ALL_TARGETS` is **not** "whatever boots on this Mac."

## Exact UI

Wawona Exact chrome lives in `exact/apps/wawona/app.contract` (sibling Exact
checkout). One file paints every Exact host. Skills: `wawona-exact-contract`,
Exact `llp-orient`, shelf recipe. Gate: `bun scripts/no-tells.mjs apps/wawona`.

## Related

- `wawona-platform-targets` (capability four-state gates)
- `wawona-exact-contract` (Contract UI skill)
- Issue #67 close path: Exact UI + Rust UniFFI (`exact/apps/wawona/docs/issue-67-exact-path.md`)
