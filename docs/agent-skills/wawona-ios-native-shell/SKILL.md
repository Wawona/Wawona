---
name: wawona-ios-native-shell
description: >-
  Wire Apple-mobile Native Shell / Wawona Terminal Start (in-process zsh +
  wwn_term UI). Use when editing GuestConsole, wawona-shell, Rootfs, pty, or
  when users report "Native Shell starting" / weston terminal stuck on iOS.
---

# iOS Native Shell (Wawona Terminal)

Rule: `wawona-ios-native-shell`. Backends: `wawona-apple-mobile-mode-a-backends`.
Kinds: `wawona-machine-types`. RAG: `wwn-mcp/knowledge/wawona/ios-native-shell-terminal.md`.

## One-line truth

**Why:** Apple Native Shell needs **host-native text selection** (press-hold,
magnifier, Copy). Wayland terminals cannot; that is why Wawona Terminal is
host UI, not foot / weston-terminal.

Every machine Start presents **Wawona Terminal** first (not a StartupLog
preview card). Native Shell Terminal Start must leave a **live zsh prompt**.
Waypipe / wasm / client Start shows `$ argv` plus streamed CLI logs.

**Terminal may start Wayland clients.** Client attach → Present opens
automatically; Terminal parks (PTY stays). Never require Done / Close.
Done parks the same way. No auto-dismiss on an empty first frame.

A splash-only string or "Starting … / auto-dismisses on first frame" card
is a bug.

## Start checklist

```text
ensureRootfsInstalled
applyShellEnvironment + WAWONA_ZSH_IN_PROCESS=1
wwn_pty_session_start(/usr/bin/zsh)   # forces -zsh -i
pump master → wwn_term_feed → export → WawonaTerminalView
keyboard → wwn_ios_terminal_inject
Stop → wwn_pty_ios_stop_shell_session
```

## Where to edit

| Piece | Path |
|---|---|
| PTY + term session | `Sources/WawonaApple/Shell/GuestConsoleView.swift` (`IosShellSession`) |
| Guest console sheet | `Sources/WawonaUI/Machines/Catalog/WWNIosGuestConsole.swift` |
| Rootfs / env | `RootfsManager.swift`, `RootfsProvider.applyShellEnvironment` |
| Connect id | `WWNMachineSessionBridge` (`wawona-shell`) |
| Present trigger | `WWNMachinesViewModel.presentGuestConsoleIfNeeded` (`source=shell`) |

Prefer extending those files. Brand-new Swift under `Sources/` must still land
on the xcodegen `Sources/WawonaApple` / `Sources/WawonaUI` tree and compile in
the app target (`wawona-ios-link-contract`).

## Gotchas (2026-10-11)

| Wrong | Right |
|---|---|
| "Native Shell starting" forever | Wire pty + term; delete splash-only UX |
| User said "weston terminal" | Check for Native Shell / Wawona Terminal title first |
| `weston_terminal_main` in binary | Fake SHM chrome (`mobile-weston-terminal.c`). Not a shell |
| `write` to PTY master for keys | `wwn_ios_terminal_inject` |
| `Font.TextStyle.caption2` | `.caption` (iOS 13 floor) |
| Install OK, launch Locked | Unlock device; install already done |

## Stop and second session (2026-10-17)

zsh runs in-process and ends by EOF inside `zleread()` (soft-exit, no
unwinding). Every global it touched survives into the next `zsh_main`.

| Wrong | Right |
|---|---|
| Shell owned by the SwiftUI view, stopped in `onDisappear` | Process registry owns it. Views attach/detach. Stop only on Close / Stop |
| `pthread_join` before closing the input pipe write end (0x8BADF00D) | `wwn_pty_ios_stop_shell_session` closes every `input_write` first |
| Master pump spins at EOF | Cancel the pump on `read` == 0 |
| Trust zsh statics on re-entry | `wwn-zsh` resets: `zleactive`, `errflag`, signal queue (stop SIGINT stays queued), feature `ADDED` marks, special params (`patch-zsh-reentry.py`) |
| `tcgetattr` on SHTTY (pipe dup above fd 10) | `patch-zsh-fake-tty.py`. libwwn-pty interpose does not apply inside the static app |

Symptom of stale state: second Start shows `mba%` with no banner (rc files
abort), or builtins are "command not found", or HOME is `/`.
Prove: Close then Start shows the banner and `~ %`, `cd; pwd` prints HOME.

## Hard rejects

- Splash-only Terminal Start
- `StartupLogOverlay` / `WWNStartupLogViewController` preview as Start UI
- Requiring Done / Close to see a Wayland client from Terminal
- Killing the shell when parking Terminal for Present
- Auto-dismiss Terminal on empty first compositor frame (no client)
- `wawona-shell` no-op connect behind that splash
- Documenting or using fake `weston_terminal_main` as Native Shell
- Skipping `WAWONA_ZSH_IN_PROCESS`

Prove on tip: `nm` shows `wawona_zsh_main`, `wwn_pty_session_start`,
`wwn_term_new`. Start → prompt, not a banner.

## Zero-AI regression (no model)

| Layer | Command |
|---|---|
| JVM argv banners | `cd android && ./gradlew :Wawona:testDebugUnitTest --tests '*MachineStartCommandTest'` |
| Compose Start UI | `./gradlew :Wawona:connectedDebugAndroidTest --tests '*TerminalStartUiTest'` |
| iOS/Android replay | `scripts/agent-device-smoke.sh terminal` (or `terminal-ios` / `terminal-android`) |

Assert `id="wwn.terminal.root"` + `id="wwn.terminal.done"` after Start.
Do not dogfood multi-sim with an AI agent for this gate.

## Window size on the pty pipe (2026-10-17)

`TIOCGWINSZ` on SHTTY fails (pipe, and `__interpose` does not apply inside the
static app). zsh then uses 80x24. On a 36-column watch grid PROMPT_SP pads to
80 and every prompt (after ^C too) wraps to an extra blank line.
`patch-zsh-fake-tty.py` makes `adjustwinsize` fall back to
`wwn_pty_tty_shim_get_winsize` (host calls `wwn_pty_tty_shim_set_winsize`
before start). Check: `print $COLUMNS` matches the host grid. The throwaway
`make zsh` link needs the stub in `wawona-dispatch-link-stubs.c`.

watchOS text entry: a hidden `TextField` with `@FocusState` does **not** open
system input. Use a sheet `TextField` the user taps.
