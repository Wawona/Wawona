# Machine types (three kinds only)

Authority for Machines Add/Edit and catalog labels. Schema:
`docs/machine-profiles.md`. Skill: `wawona-machine-types`.

## User-facing kinds

| Kind | Storage |
|---|---|
| **Native Shell** | Prefer `native` + session overrides |
| **Virtual Machine** | `virtual_machine` |
| **Container** | `container` |

Wasm packages, SSH terminal, SSH+waypipe, and Wawona Terminal are **Native
Shell sessions**, not separate machine kinds. There is **no** bundled Wayland
client session.

## Native Shell sessions

| Session | Client / transport |
|---|---|
| Terminal | Wawona Terminal (`wawona-shell`), local or SSH; optional Custom Command. Install/run wasm and CLI via `wpm` from the shell. |
| Wasm | Relay WASI (`wawona-wasm` / `/wasm/v1`) |
| Waypipe | waypipe, with or without SSH |

Session keys (WWN): `NativeShellKind`, `NativeShellUseSSH`, `NativeCustomCommand`
(Terminal). Connect resolves session via `WWNNativeShellConfiguration` /
`WWNMachineSessionBridge`, not legacy type alone.

Legacy `NativeShellKind=wayland` and client ids such as `weston-terminal`,
`niri`, `foot`, cubes migrate to Terminal / `wawona-shell` on load. Optional
software installs later via `wpm` / apt and runs from the Terminal.

## Start UI

Every Start opens **Wawona Terminal** with the machine `$ argv` banner and
CLI logs. Compositor mounts behind until Focus / Done. Android:
`MachineStartCommand`. Forbidden: StartupLog preview ("Starting …",
auto-dismiss on first frame).

## Hard rejects

- Type picker entries for `wasm`, `ssh_waypipe`, or `ssh_terminal`
- Documenting those three as first-class Machines kinds in UI copy
- Inferring SSH from a non-empty host when `NativeShellUseSSH` is false
- Re-adding a Machines **Wayland** session or bundled-client picker
- Default launcher `weston-terminal` or Settings auto-start of weston demos
- StartupLog / preview-log overlay as the machine Start surface
- Offering Custom Command as a Wayland client (use Terminal session)
- Calling the on-device shell a VM or a container
- Apple-mobile Terminal Start that is only a "Native Shell starting" splash
  (rule `wawona-ios-native-shell`)

## Code pointers

- Swift: `MachineType.selectableCases`, `NativeShellSession`,
  `NativeShellKind.selectableCases`
- Rust: `MachineType::selectable_for_ui`, `user_facing_name`
- WWN: `MachineConstants.swift` (`kWWNSelectableMachineTypes`,
  `WWNNativeShellConfiguration.migrateClientId`)
- Android: `NativeShellKind.selectableEntries`,
  `NativeShellSession.migrateClientId`

VM/container platform gates stay in `wawona-platform-targets` and
`docs/vms-containers.md`.
