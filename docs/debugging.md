# Debugging

Launching Wawona, starting a machine, and capturing UI evidence is
**agent-device** on every platform, including macOS. Do not use `osascript`,
`screencapture`, or `open -n …/Wawona.app` as the test path. See
`.cursor/rules/wawona-test-control.mdc` and `wawona-agent-device.mdc`.

LLDB is opt-in for crashes and freezes. Builds launch without a debugger.

## Apple platforms

Run the scheme from Xcode 27 (`Wawona-macOS`, `Wawona-iOS`, …): Xcode's
debugger attaches from process start, and Debug ▸ Pause interrupts a hang.
The Rust backend is built with debug info in Debug, so frames in `libwawona`
symbolicate.

From a shell, build the tip and run it under LLDB, or attach to a live one:

```bash
eval "$(cargo xtask tip macos --no-launch)"   # exports WAWONA_APP_PATH
lldb -- "$WAWONA_APP_PATH/Contents/MacOS/Wawona"
lldb -n Wawona                                # attach to a running or frozen process
```

At the `(lldb)` prompt, `process interrupt` then `thread backtrace all` is the
same as Xcode's Pause. On a simulator, launch with
`xcrun simctl launch --wait-for-debugger booted com.aspauldingcode.Wawona`
and attach with `lldb -n Wawona`. Agents use the `lldb` MCP for the same.

Never attach to `watchdogd`, WindowServer or anything holding
`IOWatchdogUserClient` (`wawona-mode-b-watchdog-safety`).

## Android

Run from Android Studio with Debug (Run ▸ Debug 'app', debugger type Dual),
which attaches Java and native LLDB. `cargo xtask build android` makes the
same debug APK.

## Linux

```bash
nix run .#wawona-linux -- --debug
```

The runner wraps the UI binary with LLDB (`process interrupt` for freezes).
