# Debugging

Launching Wawona, starting a machine, and capturing UI evidence is
**agent-device** on every platform, including macOS. Do not use `osascript`,
`screencapture`, or `open -n …/Wawona.app` as the test path. See
`.cursor/rules/wawona-test-control.mdc` and `wawona-agent-device.mdc`.

LLDB is opt-in for crashes and freezes.

All flake apps launch **without** a debugger by default. Pass `--debug` to
run under LLDB (or attach).

## Quick Reference

```bash
# Default. No debugger
nix run .#wawona-macos
nix run .#wawona-ios
nix run .#wawona-android
nix run .#wawona-linux

# Opt-in LLDB (launch under debugger; freeze → process interrupt)
nix run .#wawona-macos -- --debug
nix run .#wawona-ios -- --debug
nix run .#wawona-android -- --debug

# Attach to an already-running / frozen macOS process
nix run .#wawona-macos -- --debug-attach

# Env opt-in / force-off (macOS)
WAWONA_LLDB=1 nix run .#wawona-macos
WAWONA_NO_LLDB=1 nix run .#wawona-macos -- --debug   # still plain run
```

---

## macOS

```bash
nix run .#wawona-macos                # plain run
nix run .#wawona-macos -- --debug     # LLDB from process start
nix run .#wawona-macos -- --debug-attach
```

With `--debug`:

1. Nix build must succeed
2. Wrapper verifies `Wawona.app` + Mach-O binary exist
3. **LLDB spawns the app**. Backtraces on crash/halt
4. On hang/freeze: at the `(lldb)` prompt run `process interrupt`
   (same as Xcode Pause); stop-hooks print `thread backtrace all`

`--debug-attach` attaches to a live `Wawona` PID (useful when it already froze
outside the debugger). Then `process interrupt` if it is still running.

`--no-debug` / `--release` remain accepted as no-ops for old scripts.

---

## iOS / iPadOS / tvOS / watchOS / visionOS

```bash
nix run .#wawona-ios -- --debug
```

App launches with `--wait-for-debugger`; LLDB attaches to the simulator PID.

---

## Android

```bash
nix run .#wawona-android -- --debug
```

Deploys `lldb-server`, starts the app wait-for-debugger, attaches via
gdb-remote. See the runner tip when launching without `--debug`.

---

## Linux

```bash
nix run .#wawona-linux -- --debug
```

When `--debug` is set, the runner wraps the built binary with LLDB the same
way as macOS (`process interrupt` for freezes).
