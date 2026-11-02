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
**activate the existing instance** (`WWNReopenUINotification` only) and
exit. Do not call `NSWorkspace.openApplication` when `instance.lock` is
held: the compositor host is already this bundle, and Launch Services
delivers that open to the host. Opening the GUI while the host is running
and the lock is free uses `createsNewApplicationInstance = true` once.
Never `open -n`, never `NSTask`/`Process` of `Contents/MacOS/Wawona` for Settings.

Agents must not open Machines `WindowGroup`. Settings from the menubar
activates the existing Regular UI on the in-app Global Settings catalog
(`--show-settings` / `WWNReopenUINotification` panel `settings`).

## Hard rejects

- Ignoring `--compositor-host` / `--menubar` (full UI per LaunchAgent)
- Compositor-host `applicationShouldHandleReopen` (or any other host path)
  calling `openApplication` / `openOrActivateUI` on Wawona.app. That reopen
  is delivered back to this bundle and the Machines window opens again
  (#223). `KeepAlive` stays true for the host so the Wayland socket survives
  a crash and survives quitting the GUI. The login `open` agent stays
  `KeepAlive` false (`/usr/bin/open` exits immediately).
- Quitting the Machines window bootouting the compositor host
- Menubar spawning a second Regular UI with `open -n` / NSTask
- Unlinking `instance.lock` while a GUI may still be alive (new inode)
- Restoring ObjC `src/platform/macos/main.m` as a second `@main`
- Opening System Settings PrefPane for Global Settings
