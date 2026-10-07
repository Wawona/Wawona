# Machine Profile Schema (v1)

> **Public subset** for wawona.io.

Wawona stores machine profiles in a JSON array under `wawona.machineProfiles.v1`
with the active profile tracked in `wawona.activeMachineId.v1`.

Each profile uses this normalized shape:

- `id`, `name`, `type`
- `sshEnabled`, `sshHost`, `sshUser`, `sshPassword`
- `sshBinary`, `sshAuthMethod`, `sshKeyPath`, `sshKeyPassphrase`
- `remoteCommand`, `customScript`
- `waypipeCompress`, `waypipeThreads`, `waypipeVideo`
- `waypipeDebug`, `waypipeOneshot`, `waypipeDisableGpu`, `waypipeLoginShell`
- `waypipeTitlePrefix`, `waypipeSecCtx`
- `favorite`, `createdAtMs`, `updatedAtMs`
- `launchers` (array of per-machine client launcher definitions)
- `runtimeOverrides` (typed per-machine overrides; see below)

### `runtimeOverrides` (typed)

Optional fields; nil/empty inherits global Settings:

- graphics: `renderer`, `vulkanDriver`, `openGLDriver`, `dmabufEnabled`, `colorOperations`
- input / display: `inputProfile`, `forceSSD`, `renderMacOSPointer`, `nestedCompositorCursor`, `autoScale`, `waylandDisplay`
- backend: `compositorBackend` (`auto` \| `wayland` \| `drm`)
- session: `bundledAppID`, `waypipeEnabled`, `waypipeSSHPassword`, `logLevel`, `shakeToCloseEnabled`, `swipeBackToCloseEnabled`
- **`environment`**: map of env overrides (`{ "TERM": { "action": "set", "value": "xterm" } }`). See [#157](https://github.com/Wawona/Wawona/issues/157) / [`issues/environment-variables-gui.md`](issues/environment-variables-gui.md). Never stash env in `settingsOverrides` (Swift Codable drops unknown keys).

### User-facing kinds (Add/Edit picker)

Only three kinds appear in Machines UI:

| Label | Usual storage `type` |
|-------|----------------------|
| **Native Shell** | `native` (plus session overrides) |
| **Virtual Machine** | `virtual_machine` |
| **Container** | `container` |

Native Shell **sessions** (not separate type picker rows):

| Session | Meaning |
|---------|---------|
| Terminal | Wawona Terminal (`wawona-shell`), local or SSH |
| Wayland | Bundled Wayland client on the local compositor |
| Wasm | Relay WASI / `wpm` / `/wasm/v1` |
| Waypipe | waypipe, with or without SSH |

WWN session keys: `NativeShellKind`, `NativeShellUseSSH` in `settingsOverrides`.
See agent rule `wawona-machine-types` and skill `wawona-machine-types`.

### Storage `type` values (wire / legacy)

- `native` (Native Shell; prefer this plus session overrides)
- `wasm` (legacy; folds to Native Shell / Wasm session)
- `ssh_waypipe` (legacy; folds to Native Shell / Waypipe + SSH)
- `ssh_terminal` (legacy; folds to Native Shell / Terminal + SSH)
- `virtual_machine`
- `container`

## VM / container status

`virtual_machine` and `container` are **planned** on macOS, iOS, iPadOS,
visionOS, Android, and Linux. They are **forbidden** on tvOS and watchOS.
See [`vms-containers.md`](vms-containers.md).

## Deprecated / removed fields

- `vmSubtype`, `containerSubtype`. **removed**. The VM engine and container
  runtime are selected automatically per build target by the `wwn-vms` and
  `wwn-containers` capability lanes and are never user-configurable. These keys
  are ignored on load (readers tolerate them for backward compatibility) and are
  no longer written on save.

Transient (non-persisted) UI/runtime status values used by machine grid cards:

- `disconnected`
- `connecting`
- `connected`
- `degraded`
- `error`

Notes:

- **Transport routing:** resolve Native Shell **session** via
  `WWNNativeShellConfiguration` / `WWNMachineSessionBridge` (not type alone).
  Wayland / local Terminal / Wasm use the local compositor path. Waypipe
  sessions (and Terminal + Use SSH) use waypipe / SSH transport. Legacy
  `ssh_waypipe` / `ssh_terminal` storage still connects.
- Apple and Android both migrate from legacy flat `waypipe*` preferences
  into one initial machine profile when no profile list exists.
- Runtime launch remains backward-compatible by applying the selected machine
  back into legacy runtime preference keys before connect/run.
- The previous global Weston toggle in Advanced Settings is deprecated.
  Launch behavior is now per-machine (or inherited from global defaults) via
  `ClientLauncher`.

## ClientLauncher schema

Each machine can define zero or more launchers:

- `id` (UUID)
- `name` (`weston-terminal`, `foot`, `weston-simple-shm`, custom)
- `displayName` (UI label)
- `executablePath` (bundled binary or absolute path)
- `arguments` (array of args)
- `autoLaunch` (launch immediately when machine connects)
