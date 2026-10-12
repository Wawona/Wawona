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

Terminal Start on Apple mobile must leave a **live zsh prompt** in Wawona
Terminal UI. A splash string is a bug.

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

## Hard rejects

- Splash-only Terminal Start
- `wawona-shell` no-op connect behind that splash
- Documenting or using fake `weston_terminal_main` as Native Shell
- Skipping `WAWONA_ZSH_IN_PROCESS`

Prove on tip: `nm` shows `wawona_zsh_main`, `wwn_pty_session_start`,
`wwn_term_new`. Start → prompt, not a banner.
