---
name: wawona-carplay-lab
description: Set up Playport for physical-iPhone CarPlay development with private runtime credentials.
---

# CarPlay lab

Canonical workflow: `docs/carplay-lab.md`.

- `nix run .#carplay`: macOS developer lab, Rust helper. Runtime downloads/builds.
- `setup`, `doctor`, `scan`, `pair ADDRESS`, `run [FLAGS]` subcommands.
- Playport source pinned in `scripts/carplay/main.rs`. Never auto-reset changes.
- Credentials only `~/.playport/wawona-lab/`, never repository/Nix store/RAG.
- Identity imported privately from upstream-documented DiPlay release.
  Never commit, redistribute, print, or attach key/APK/runtime files.
- Wi-Fi password hidden prompt, owner-only Java argfile. Not process argv.
  Argfile unlinked before JVM start; inherited stdin descriptor. Never share it.
- Pairing confirmation + macOS Bluetooth permission remain manual.
- Receiver does not grant Wawona CarPlay entitlement. Signed app needs matching
  Apple-approved profile. Existing scene is dormant without entitlement.
- `doctor` is file readiness, not physical runtime proof.

- macOS inquiry completion can stall after device discovery. Rust launcher
  bounds scans to 15s, preserving printed results, then asks for address.
  Pairing bounded to 75s with failure. Never await scan callback indefinitely.

- Default command opens std-only Rust TUI (tui.rs). Arrow keys/Enter select;
  O opens viewer, S stops JVM, Q/Ctrl+C cleans up. Existing CLI subcommands stay.
- TUI scan is a selectable live list with countdown. Pairing code stays visible.
  Saves only chosen phone address privately, passes --bt-address explicitly.
- Viewer access token retained in memory, never rendered/logged by TUI.
  Wi-Fi input masked. Java stdout parsed in background; stderr not displayed.

Pairing regression: never swallow helper stderr or treat cancellation as success.
Capture final stdout/stderr after fast exit. Keep success/failure visible until
acknowledged; save phone only on success. Main menu: Pair iPhone, Start/Stop
CarPlay, Open viewer, Help, Quit. Manual address/rescan live inside Pair iPhone.
