# Machine Profile Schema (v1)

Wawona stores machine profiles in a JSON array under `wawona.machineProfiles.v1`
with the active profile tracked in `wawona.activeMachineId.v1`.

Each profile uses this normalized shape:

- `id`, `name`, `type`
- `sshEnabled`, `sshHost`, `sshUser`, `sshPassword`
- `sshBinary`, `sshAuthMethod`, `sshKeyPath`, `sshKeyPassphrase`
- `remoteCommand`, `customScript`
- `vmSubtype`, `containerSubtype`
- `waypipeCompress`, `waypipeThreads`, `waypipeVideo`
- `waypipeDebug`, `waypipeOneshot`, `waypipeDisableGpu`, `waypipeLoginShell`
- `waypipeTitlePrefix`, `waypipeSecCtx`
- `favorite`, `createdAtMs`, `updatedAtMs`
- `launchers` (array of per-machine client launcher definitions)

Machine `type` values:

- `native` (local host compositor)
- `ssh_waypipe`
- `ssh_terminal`
- `virtual_machine`
- `container`

Transient (non-persisted) UI/runtime status values used by machine grid cards:

- `disconnected`
- `connecting`
- `connected`
- `degraded`
- `error`

Notes:

- **Transport routing:** `native` profiles launch bundled/in-process Wayland clients on the **local compositor** (iOS: `launchBundledClientWithId`, Android: `launchNativeMachine`, Linux: direct `sh -c`). **Waypipe is only used for `ssh_waypipe` and `ssh_terminal`** (remote/networked machines). Native profiles must never start waypipe; enforced in `WWNMachineSessionBridge` and `WWNWaypipeRunner`.
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
