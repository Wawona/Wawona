# Container Settings — GUI ↔ CLI contract (macOS)

> Design doc for the Settings → Containers + per-machine container support.
> The GUI is a **thin wrapper over the `container` CLI** (wwn-containers), exactly
> like the Waypipe GUI wraps waypipe: every field maps onto a CLI argument or
> environment variable, and the runner builds one `container run …` command from
> resolved settings. Backend selection is **never** user-configurable — macOS is
> always Apple `Containerization.framework` (Residual E).

## Layering (who owns what)

| Surface | Repo | Role |
| --- | --- | --- |
| OCI core (`wwn-oci`) | wwn-containers | pull/images/rmi/inspect/resolve + `search`/`tags` (Docker Hub metadata) |
| Execution backend (`wwn-containerd-run`) | wwn-containers | per-container VM via Apple Containerization; one-shot run+wait |
| `container` CLI wrapper | wwn-containers | one command surface for GUI + terminals; parses run flags, rejects unsupported ones (exit 3) |
| Settings → Containers (global defaults) | Wawona (ObjC `WWNPreferences` + `WWNPreferencesManager`) | image store, default image/command, memory, kernel/initfs, vsock port |
| Machine profile → Containers (per-machine) | Wawona (`MachineProfile.containerSettings`, SwiftUI + ObjC) | overrides the globals; empty fields inherit |
| Runner | Wawona (`WWNContainerRunner`) | resolves per-machine > global → builds the CLI command |

## Resolution rule

**Per-machine always overrides global; a new machine inherits global defaults.**
`containerSettings` is an all-optional struct on `MachineProfile`
(`containerSettings == nil` ⇒ inherit everything). Resolution lives in
`WawonaPreferences.resolvedSettings(for:)` (SwiftUI preview) and
`WWNContainerRunner.bootCommandForProfile:` (actual launch). A profile
`customScript` (advanced escape hatch) always wins over generated commands.

## JSON schema (`containerSettings` on `wawona.machineProfiles.v1`)

Keys match the Android `ContainerSettings` object (`runtime`, `containerRef`,
`entryCommand`, `notes`) and extend it with the macOS fields. All optional;
absent keys are ignored by every platform.

| Key | Type | Meaning |
| --- | --- | --- |
| `runtime` | string? | Backend label (display only; fixed per target) |
| `containerRef` | string? | OCI image reference (Docker Hub shorthand accepted) |
| `entryCommand` | string? | Command (and args) run in the container |
| `notes` | string? | Free-form notes |
| `memory` | string? | `--memory`, MiB |
| `shmSize` | string? | `--shm-size` (reserved; backend does not honor it yet) |
| `mounts` | [string]? | `--mount` specs (reserved; backend does not honor it yet) |
| `ports` | [string]? | `--publish` specs (reserved; backend does not honor it yet) |
| `platform` | string? | `--platform` (reserved) |
| `readOnly` | bool? | `--read-only` |
| `initProcess` | bool? | `--init` |
| `remove` | bool? | `--rm` (the macOS backend is one-shot, so the container is always removed; kept for CLI parity) |
| `kernelPath` | string? | `--kernel` / `WAWONA_VM_KERNEL` |
| `initfsPath` | string? | `--initfs` / `WAWONA_VM_INITFS` |
| `vsockPort` | int? | guest waypipe server port (`--wayland-vsock-port`; default 1024) |
| `desktopSession` | bool? | attach the container's Wayland session to Wawona (windows via the waypipe vsock bridge) |
| `imageArchivePath` | string? | local OCI layout dir to boot from (`--image-archive`); set by the editor's "Import image archive…" — no registry pull at run time |

## Apple `container` CLI ↔ GUI field mapping (1:1 where honored)

Captured from the pinned Apple `container` CLI 1.2.2 (`container run --help`).

| Apple `container` flag | GUI (global) | GUI (per-machine) | CLI arg the runner emits | Status |
| --- | --- | --- | --- | --- |
| image (positional) | Default Image (`ContainerDefaultImage`) | Image | `'<ref>'` | ✅ |
| `[cmd...]` | Default Command (`ContainerDefaultCommand`) | Command | `'<cmd>'` | ✅ |
| `--memory` | Memory Limit (`ContainerMemory`) | Memory (MiB) | `--memory <MiB>` | ✅ |
| `--read-only` | — | Read-Only Rootfs | `--read-only` | ✅ |
| `--init` | — | Init Process | `--init` | ✅ |
| `--kernel` | Kernel Path (`ContainerKernelPath`) | Kernel Path | `--kernel <path>` (per-machine) / `WAWONA_VM_KERNEL` (global) | ✅ |
| `--initfs` (ours) | Initfs Path (`ContainerInitfsPath`) | Initfs Path | `--initfs <path>` / `WAWONA_VM_INITFS` | ✅ |
| `--rm` | — | (implicit) | `--rm` (accepted no-op: one-shot backend) | ✅ |
| `--wayland-vsock-port` (ours) | VSock Port (`ContainerVsockPort`) | vsockPort (schema) | `--wayland-vsock-port <n>` (desktop-session machines) | ✅ |
| `--waypipe-guest-bin` (ours) | — | — | `--waypipe-guest-bin '<path>'` (bundled waypipe-guest; env `WAWONA_WAYPIPE_GUEST` fallback) | ✅ runner-emitted |
| `--image-archive` (ours) | — | imageArchivePath (schema) | `--image-archive '<path>'` (local OCI layout dir from `container import`) | ✅ runner-emitted |
| `--shm-size` | — | shmSize (schema) | — | ⏳ reserved (backend rejects) |
| `--volume`, `--mount` | — | mounts (schema) | — | ⏳ reserved (backend rejects) |
| `--publish`, `--publish-socket` | — | ports (schema) | — | ⏳ reserved (backend rejects) |
| `--platform`/`--os`/`--arch` | — | platform (schema) | — | ⏳ reserved |
| `--env` | — | (not yet) | — | ⏳ reserved |
| `--cpus`, `--fs-size` | — | (not yet) | CLI accepts; not surfaced in GUI | ✅ CLI-only |
| `--id` | — | (implicit) | `--id wawona-<machineId>` (unique per machine) | ✅ runner-emitted |
| `--cap-add/drop`, `--dns*`, `--label`, `--network`, `--tmpfs`, `--entrypoint`, `--rosetta`, `--virtualization`, `--ssh`, `--init-image`, `--masked-path`, `--read-only-path`, `--cidfile`, `-d` | — | — | via profile `customScript` escape hatch | ⏳ advanced |

> **Honesty rule**: a reserved field never silently becomes a no-op. The CLI
> wrapper rejects flags the macOS backend cannot honor (exit 3,
> "not supported by the macOS backend yet") and the GUI does not surface them
> until the backend does. `--rosetta` is intentionally dropped from the Wawona
> roadmap (lower priority).

## Global defaults (Settings → Containers)

| Pref key | Default | CLI effect |
| --- | --- | --- |
| `ContainerDefaultImage` | `alpine:3.20` | image ref when a machine has none |
| `ContainerDefaultCommand` | `/bin/sh` | command when a machine has none |
| `ContainerMemory` | `""` | `--memory` (empty = backend default 1024 MiB) |
| `ContainerKernelPath` | `""` | `WAWONA_VM_KERNEL` (empty = newest kernel under `~/Library/Application Support/com.apple.container/kernels`) |
| `ContainerInitfsPath` | `""` | `WAWONA_VM_INITFS` (empty = `vminit:latest` from the containerization image store) |
| `ContainerVsockPort` | `1024` | `--wayland-vsock-port` for desktop-session machines |
| `MachineContainerImageStore` | `~/.local/share/wawona/oci` | `WWN_OCI_ROOT` for the image-management CLI |

## Generated command shape

```
container run --rm --id wawona-<machineId> [--memory <MiB>] [--kernel '<path>'] [--initfs '<path>']
        [--read-only] [--init]
        [--wayland-vsock-port <n> --waypipe-guest-bin '<path>']  # desktop session
        '<ref>' '<command>'
```

The command runs inside Wawona's bundled terminal, not as a bare host
subprocess: `WWNContainerRunner` launches `weston-terminal` with `SHELL`
pointed at the bundled `wawona-container-shell` wrapper, which `exec`s the
command above via `/bin/sh -lc` (`WAWONA_CONTAINER_CMD`). The container's
stdin/stdout/ANSI flow through the terminal's PTY into the Wawona window, so
both one-shot runs and interactive shells (`container run alpine /bin/sh`)
work. Env: `WAWONA_CONTAINER_BACKEND=containerization`, `WWN_OCI_ROOT`,
`WAWONA_VM_KERNEL`, `WAWONA_VM_INITFS` as configured.

The backend reports progress to the runner via marker files in `/tmp`
(`wawona-container-ready-<machineId>` when the VM is booted,
`wawona-container-done-<machineId>` when the container process exits), which
drive the card's Compiling backend → Connected → Disconnected transitions.

## Docker Hub discovery (GUI search)

- The machine editor's Container section has a Search Docker Hub button
  (macOS) that opens a search sheet. Results come from the bundled
  `container` CLI (`Contents/Resources/bin/container`), falling back to the
  user's PATH when the CLI is not bundled.
- Level 1: `container search <query> --json`. Repos render `repo_name` +
  `pullableRef`, stars, pulls, and the official badge. Single-component
  names resolve to the official `library/` namespace (`python` →
  `docker.io/library/python`).
- Level 2: picking a repo runs `container tags <pullableRef> --json` and
  lists tags (newest first) with architecture badges and compressed sizes.
  Picking a tag fills the Image field with `<pullableRef>:<tag>`; a default
  tag row fills the bare `pullableRef`.
- The editor persists Image + Command to `containerSettings.containerRef` /
  `entryCommand`. Empty values inherit the global Settings > Containers
  defaults, same as the CLI.
- The GUI decodes the CLI JSON verbatim (`ContainerHubModels.swift`) and
  never re-implements registry or namespace rules.
- CLI verbs: `container search <query>` → `wwn-oci search` → Hub JSON API
  (`hub.docker.com/v2/search/repositories/`), anonymous, paginated.
  `container tags <repo>` → `wwn-oci tags` →
  `hub.docker.com/v2/repositories/<repo>/tags/`.

## Compliance notes

Inherits `wwn-containers/COMPLIANCE.md`: image management (incl. search/tags,
metadata-only HTTPS GET) is universal; execution is macOS
`Containerization.framework` only in this phase, direct/notarized channel
(`com.apple.security.virtualization`). Lifecycle verbs the backend lacks fail
cleanly (exit 3). Never fake execution.
