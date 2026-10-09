# macOS single Wawona.app UI instance

Authority: LaunchAgents in `LaunchAgentManager`, process entry in
`Darwin/Sources/Main.swift` (`WawonaProcessEntry`).

## Roles (one Mach-O, three locks)

| Role | Argv | Lock | Activation policy |
|---|---|---|---|
| Regular UI | (default) | `instance.lock` | `.regular` |
| Compositor host | `--compositor-host` | `compositor-host.lock` | `.accessory` |
| Menu bar | `--menubar` | `menubar.lock` | `.accessory` |

Locks live under `/tmp/wawona-$UID/`. A second Regular UI launch must
**activate the existing instance** (`WWNReopenUINotification` /
`createsNewApplicationInstance = false`) and exit. Never `open -n`, never
`NSTask`/`Process` of `Contents/MacOS/Wawona` for Settings.

Agents must not open Machines `WindowGroup`. Settings from the menubar
activates the existing Regular UI on the in-app Global Settings catalog
(`--show-settings` / `WWNReopenUINotification` panel `settings`).

## Hard rejects

- Ignoring `--compositor-host` / `--menubar` (full UI per LaunchAgent)
- Menubar spawning a second Regular UI with `open -n` / NSTask
- Unlinking `instance.lock` while a GUI may still be alive (new inode)
- Restoring ObjC `src/platform/macos/main.m` as a second `@main`
- Opening System Settings PrefPane for Global Settings
