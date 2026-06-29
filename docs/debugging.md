# Attaching a Debugger

`nix run .#wawona-macos` launches Wawona **under LLDB automatically** (Xcode Run). LLDB is skipped only if the build artifact fails sanity checks, or you opt out with `--no-debug`.

## Quick Reference

```bash
# macOS — default: under LLDB (Xcode Run)
nix run .#wawona-macos

# macOS — skip LLDB
nix run .#wawona-macos -- --no-debug

# macOS — attach to already-running Wawona
nix run .#wawona-macos -- --debug-attach

# iOS Simulator — opt-in via --debug
nix run .#wawona-ios -- --debug
```

---

## macOS (default)

```bash
nix run .#wawona-macos
```

1. Nix build must succeed
2. Wrapper verifies `Wawona.app` + Mach-O binary exist
3. **LLDB spawns the app** — backtraces on crash/halt, `process interrupt` on hang

If the bundle or binary is missing/broken, the wrapper exits with an error and never starts LLDB.

### Skip LLDB

```bash
nix run .#wawona-macos -- --no-debug
WAWONA_NO_LLDB=1 nix run .#wawona-macos
```

### Attach to a running instance

```bash
nix run .#wawona-macos -- --debug-attach
```

---

## iOS / Android

Use `--debug` on `wawona-ios`, `wawona-android`, etc.
