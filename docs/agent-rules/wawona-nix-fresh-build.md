# Nix fresh build (hard). Never stale apps

Wawona products and deps are **Nix Flakes**. Agents that invent host `cargo`,
overlay `/tmp` archives, launch `/Applications/Wawona.app`, or boot the wrong
Apple simulator are wrong. Authority: `docs/compilation.md`,
`wawona-test-tip-app`, `wawona-direnv-nix`, skill `wawona-nix-fresh-build`.

## Before any build or launch

1. Query **wwn-mcp** (`search_docs` / `where_to_edit`) for the attr and tip path.
2. Query **nixos** MCP or skill when the question is nixpkgs / flake syntax.
3. Read `docs/compilation.md`. Do not invent attribute names.

## Canonical fresh commands (from Wawona flake root)

| Goal | Command |
|------|---------|
| macOS app build + run | `nix run .#wawona-macos` (or `nix run .#wawona`) |
| macOS store-shaped package | `nix build .#wawona-macos` → use `$out` / `result` |
| Low RAM | `./scripts/nix-build-low-mem.sh .#wawona-macos` |
| Wawona Terminal standalone | `nix run .#terminal` |
| Local Terminal tree | `nix run .#terminal --override-input terminal path:../Terminal` |
| Tip macOS for Appium / agent-device | `eval "$(WAWONA_TEST_REBUILD=1 cargo xtask tip macos)"` after product sources change |
| iOS sim product | `nix run .#wawona-ios` / `nix build .#wawona-ios-app-sim` |
| Xcode / Android Studio | `nix run .#deps -- <sdk>` (or `android`), then open the root project |
| Rust from the working tree | `scripts/build-backend.sh <sdk>` (uses the slice's Nix environment) |
| Android | `nix run .#wawona-android` |
| Linux | `nix run .#wawona-linux` |

`--rebuild` is not "make it fresh" slang. Prefer a real `nix build` of the
attr after input / source change. Tip rebuild: `WAWONA_TEST_REBUILD=1`.

## Tip vs Nix product

- **Product proof / dogfood of Nix packaging:** prefer `nix run .#wawona-macos`
  or the `result` from `nix build .#wawona-macos`.
- **Appium / agent-device macOS UI:** tip tree via `cargo xtask tip macos`
  (`nix run .#deps -- macosx`, then Debug under `/tmp/wawona-macos-tip`). Still refuse
  `/Applications` and foreign DerivedData (`wawona-test-tip-app`).
- Changing Rust/Swift/flake inputs requires rebuild. A matching `git-HEAD`
  stamp on an old binary after you only patched `/tmp` libs is **stale**.

## Match the device to the task (hard)

Boot **only** the platform under test.

| Task | Allowed run target |
|------|--------------------|
| Wawona Terminal / Ghostty / macOS host UI | macOS tip or `nix run .#wawona-macos` / `.#terminal` |
| iOS phone Terminal | iPhone Simulator / device (`wawona-ios`) |
| visionOS feature work | visionOS sim **only then** (`.#wawona-visionos-app-sim`) |

**Forbidden while resolving Wawona Terminal (or any non-visionOS task):**

- Booting **Vision Pro** / visionOS Simulator
- `nix build` / `xcodebuild` / XcodeBuildMCP defaults aimed at visionOS
- Claiming Terminal fixed because a visionOS sim launched

Wrong sim wastes hours and produces false evidence.

## Hard rejects

- `/Applications/Wawona.app`, `~/Applications`, random `DerivedData-macos*`
- Host `cargo build` + `llvm-objcopy` merge of `libwawona_terminal.a` as the
  ship path (lab overlay only when a named tip script documents it; durable
  fix is flake input + Nix recipe)
- Treating `/tmp/wawona-terminal-*-target/release/*.a` as the product archive
- `WAWONA_ALLOW_STALE_TEST_APP=1` for proof claims
- Booting Vision Pro / visionOS when the bug is Terminal on macOS/iOS
- Skipping RAG / `compilation.md` and guessing `nix` attrs
- Ad-hoc Zig / host toolchain for libghostty-vt (use flake `ghostty` / Terminal
  `nix-ghostty-vt`)

## Agent checklist (every Terminal / host UI turn)

```text
[ ] wwn-mcp queried for build path
[ ] nix attr from compilation.md / flake
[ ] rebuild with nix (or WAWONA_TEST_REBUILD tip) after source change
[ ] WAWONA_APP_PATH is tip or nix result, not /Applications
[ ] No Vision Pro unless task is visionOS
```

Cursor: `wawona-nix-fresh-build` (alwaysApply). Skill: `wawona-nix-fresh-build`.
Related: `wawona-test-tip-app`, `wawona-local-before-ci`, `wawona-ghostty-host`,
`wawona-direnv-nix`.
