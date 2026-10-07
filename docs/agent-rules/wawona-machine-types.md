# Machine types (three kinds only)

Authority for Machines Add/Edit and catalog labels. Schema:
`docs/machine-profiles.md`. Skill: `wawona-machine-types`.

## User-facing kinds

| Kind | Storage |
|---|---|
| **Native Shell** | Prefer `native` + session overrides |
| **Virtual Machine** | `virtual_machine` |
| **Container** | `container` |

Wasm packages, SSH terminal, SSH+waypipe, local Wayland clients, and Wawona
Terminal are **Native Shell sessions**, not separate machine kinds.

## Native Shell sessions

| Session | Client / transport |
|---|---|
| Terminal | Wawona Terminal (`wawona-shell`), local or SSH; optional Custom Command |
| Wayland | Bundled Wayland client on the local compositor (no Custom Command) |
| Wasm | Relay WASI (`wawona-wasm` / `/wasm/v1`) |
| Waypipe | waypipe, with or without SSH |

Session keys (WWN): `NativeShellKind`, `NativeShellUseSSH`, `NativeCustomCommand`
(Terminal). Connect resolves session via `WWNNativeShellConfiguration` /
`WWNMachineSessionBridge`, not legacy type alone.

## Wayland software picker order

Compositors (weston, niri) → client types (Terminals, Graphics, Demos) →
Other. Custom commands belong under Terminal. Shared kind helpers:
`BundledWaylandSoftwareKind` (Apple), `SoftwareKind` (Linux),
`BundledWaylandSoftwareKind` (Android).

## Hard rejects

- Type picker entries for `wasm`, `ssh_waypipe`, or `ssh_terminal`
- Documenting those three as first-class Machines kinds in UI copy
- Inferring SSH from a non-empty host when `NativeShellUseSSH` is false
- Putting `wawona-shell` or `wawona-wasm` in the Wayland bundled-client list
- Offering Custom Command as a Wayland client (use Terminal session)
- Calling the on-device shell a VM or a container
- Flat unsorted Wayland catalogs in the native machine editor

## Code pointers

- Swift: `MachineType.selectableCases`, `NativeShellSession`
- Rust: `MachineType::selectable_for_ui`, `user_facing_name`
- WWN: `MachineConstants.swift` (`kWWNSelectableMachineTypes`,
  `WWNNativeShellConfiguration`)

VM/container platform gates stay in `wawona-platform-targets` and
`docs/vms-containers.md`.
