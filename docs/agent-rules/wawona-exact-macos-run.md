# Exact macOS UI: xtask run + Exact agent

Exact UI is built for agents. Control it with the **Exact agent driver**, not
macOS computer-use, osascript, or host screencapture.

## Launch (Wawona product checkout)

```bash
cargo xtask run macos
cargo xtask run ios
cargo xtask run macos --no-rebuild
```

Always Exact-builds the tip then launches (same shape as `cargo run`).
`--no-rebuild` launches the existing tip only. macOS: `open`
`.build/exact/macos/Wawona.app`. iOS family: `simctl install` + `launch`
(`com.aspauldingcode.Wawona`). Override sim with `WAWONA_SIM_UDID` or
`EXACT_SIM`. Bun stays under Exact; cargo xtask is the Rust-driven entry.

## Drive / grade (Exact agent via xtask)

```bash
cargo xtask agent grade macos --rebuild

cargo xtask agent drive macos -- tree state check \
  "screenshot docs/ui-quality/history/artifacts/catalog.png" \
  "tap toolbar-settings" "clock settle"
```

xtask sets `EXACT_APP_DIR` / `EXACT_MAC_BIN` to the mirrored tip when present.
Targets are `testId`s. Never raw coordinates. Never computer-use.

Docs: Exact `AGENTS.md`, `docs/start-here.md`. Skill: `wawona-exact-contract`.
`cargo xtask tip macos` stays Appium / agent-device product proof.

## Hard rejects

- Computer-use / AX screenshot of Exact chrome as the grade path
- `open …/target/clients/…/Wawona.app` or bare `bun host/apple/build.mjs` then
  hand-open for Exact UI dogfood
- `cargo xtask build macos` alone when the ask is run / grade
- agent-device / Appium as the Exact Contract chrome driver on macOS

Skill: `wawona-exact-contract`. Cursor: `wawona-exact-macos-run`.
