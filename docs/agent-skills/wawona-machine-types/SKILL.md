---
name: wawona-machine-types
description: >-
  Machines UI has three kinds only: Native Shell, Virtual Machine, Container.
  Native Shell sessions are Terminal, Wayland, Wasm, Waypipe (optional SSH).
  Use when editing machine editors, profile schema, connect/launch, or catalog
  labels.
---

# Machine types (three kinds)

Rule: `wawona-machine-types`. Prose: `docs/machine-profiles.md`.
RAG: `wwn-mcp/knowledge/wawona/machine-types-native-shell.md`.

## User-facing kinds

| Picker label | Storage `type` (usual) |
|---|---|
| Native Shell | `native` (session in overrides) |
| Virtual Machine | `virtual_machine` |
| Container | `container` |

Do **not** offer `wasm`, `ssh_waypipe`, or `ssh_terminal` as top-level types in
Add/Edit. Those are Native Shell **session modes** (legacy storage may still
use those raw values for connect).

## Native Shell sessions

| Session | Meaning | Use SSH |
|---|---|---|
| Terminal | Wawona Terminal (`wawona-shell`). Optional Custom Command. Not foot. Not weston-terminal. | Optional |
| Wayland | Bundled Wayland client (weston, niri, cubes, …). No Custom Command here. | No |
| Wasm | Relay WASI / `wpm` / `/wasm/v1` | No |
| Waypipe | waypipe stream (local or remote) | Optional |

Overrides (WWN path): `NativeShellKind`, `NativeShellUseSSH` in
`settingsOverrides`. Helpers: `WWNNativeShellConfiguration`,
`NativeShellSession` / `NativeShellKind` (Swift),
`MachineType.selectableCases` / `selectable_for_ui()` (Rust).

## Where to edit

| Surface | Path |
|---|---|
| Thick macOS/iOS editor | `WWNMachineEditorView`, `WWNMachineEditorDraft`, `WWNNativeShellSessionEditorSection` |
| Thin Apple editor | `MachineEditorView`, `MachineEditorDomain` |
| Linux GTK | `src/linux/ui/editor.rs` |
| Connect | `WWNMachineSessionBridge` (kind + Use SSH, not type alone) |
| Labels / cards | `WWNMachinesViewModel`, `WWNMachineCardView` |

## Terminal Custom Command

Under Native Shell → Terminal (beside Use SSH): optional command string.
Persists as `NativeCustomCommand`; with Use SSH on it is also the SSH
`remoteCommand`. Empty = interactive local shell / default `bash -l` over SSH.
Legacy Wayland client id `custom` migrates to Terminal on edit/save.

## Wayland software picker (Native Shell → Wayland)

Order: **Compositors** (weston, niri), then client types (**Terminals**,
**Graphics**, **Demos**), then **Other**. No Custom Command row. Shared kind:
`BundledWaylandSoftwareKind` (Swift) / `SoftwareKind` (Linux) /
`BundledWaylandSoftwareKind` (Android).

## Hard rejects

- Separate Machines kinds for SSH, Waypipe, or Wasm in the type picker
- Treating Wawona Terminal as foot / weston-terminal
- Inferring Use SSH from a leftover `sshHost` on Wayland/Terminal local
- Listing `wawona-shell` / `wawona-wasm` in the Wayland client picker
- Custom Command as a Wayland client option (belongs under Terminal)
- Equating Native Shell with VM/container engines
- Flat unsorted Wayland catalogs in the native editor (keep section order)

## Legacy load

`wasm` / `ssh_terminal` / `ssh_waypipe` profiles fold into Native Shell in the
editor. Save may keep those storage types for connect, or persist `native` plus
`NativeShellKind` (WWN path prefers `native` + overrides).
