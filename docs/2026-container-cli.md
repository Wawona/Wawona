# Native `container` CLI. Requirement + implementation status

> **Status: PARTIALLY IMPLEMENTED (2026-07-05, verified on macOS 26.5.1 arm64).**
> Image management is REAL on the host: `pull` / `images` / `rmi` / `inspect` /
> `resolve` / `search` / `tags` are wired to `wwn-oci` (digest-verified registry
> v2 pull, CAS store, per-image rootfs unpack, local catalog under `$WWN_OCI_ROOT` /
> `~/.local/share/wwn-oci`; Docker Hub discovery via the Hub JSON API). `run` is
> REAL on macOS: it boots a per-container VM via `wwn-containerd` (Apple
> Containerization framework; kernel discovered from `WAWONA_VM_KERNEL` or the
> installed containerization kernels; optional bundled initfs via
> `WAWONA_VM_INITFS`) — verified booting `alpine:3.20`. The GUI layer (Settings →
> Containers + per-machine `containerSettings`, resolution documented in
> `2026-container-settings.md`) is implemented on macOS. Still stubs:
> `exec`/`ps`/`start`/`stop`/`rm`/`logs` (need a persistent container session;
> `wwn-containerd` is one-shot run+wait), `run` on non-macOS targets
> (container-in-VM via `wwn-vms`), and per-target cross-built registry variants.

## Goal

Wawona's **native terminals** (backed by [`wwn-zsh`](../../wwn-zsh)) must expose a
first-class `container` command so a user can **manage and run OCI containers
from a shell, on every Wawona target**. The whole Apple ecosystem (macOS, iOS,
iPadOS, tvOS, visionOS, watchOS) and Android. And **boot containers from inside
native clients as if using a real computer**.

This is the shell/terminal front-end to the same substrate the GUI uses:
- **Wawona Settings → Containers** (global runtime/store config), and
- **Wawona Machine profile config → Containers** (per-profile container setup).

All three surfaces (CLI, Settings, Machine profiles) drive the **one** backend in
[`wwn-containers`](../../wwn-containers). The CLI is not a separate implementation -
it is a thin front-end over `wwn-oci` (image management) and the per-target
execution backend.

## Where it lives

- **Command + backends:** `wwn-containers`. The CLI scaffold is
  `wwn-containers/dependencies/containers/cli/container-cli.nix`, exposed as the
  `container-cli` flake package and the `container-cli` registry entry
  (per-target `withPlatformVariants`, cross-built later via `wwn-toolchain`).
- **Terminal availability:** `wwn-zsh` bundles/paths the `container` command into
  Wawona's native terminal environment on every target (in-process Mach-O inside
  `zsh.framework` on Apple, native binary on Android), so `container ...` works in
  any Wawona terminal without an external daemon on the user's `PATH`.
- **Host bridge:** the running compositor sets `WAWONA_CONTAINER_BACKEND` (already
  done for macOS by `WWNContainerRunner`, value `containerization`) so the CLI and
  the GUI agree on which lane is active.

## Command surface (planned)

Image management (universal. Pure userspace `wwn-oci`, compliant on **every**
target incl. iOS/watchOS):

- `container pull <ref>` — pull an OCI image into the local content-addressable store
- `container images` — list stored images
- `container inspect <ref>` — show manifest/config
- `container rmi <ref>` — remove an image
- `container resolve <ref>` — parse a reference and print its components
- `container search <query>` — search Docker Hub (metadata only, `--json` for
  machine output; Hub's JSON API is outside the OCI distribution spec)
- `container tags <repo>` — list a Docker Hub repository's tags (single-component
  names resolve to the official `library/` namespace)

Lifecycle (only where a Linux kernel is legally available. See the matrix):

- `container run <ref> [cmd...]`. Create + start a container and attach its
  Wayland session into Wawona (vsock + waypipe)
- `container exec <id> <cmd...>`. Exec a process in a running container
- `container ps`. List containers
- `container start|stop|rm <id>`. Lifecycle control
- `container logs <id>`. Stream logs

`run` parses the flags the macOS backend (`wwn-containerd`) can honor —
`-k/--kernel`, `--initfs`, `-m/--memory`, `-c/--cpus`, `--fs-size`,
`--read-only`, `--init`, `--id`, `--wayland-vsock-port`, plus `--rm` as an
accepted no-op (every run is one-shot) — and **rejects** flags it cannot honor
(e.g. `--mount`, `--publish`, `--shm-size`, `--platform`, `--env`) with exit 3,
never silently dropping them. See [`2026-container-settings.md`](2026-container-settings.md)
for the GUI ↔ CLI field mapping.

The scaffold prints this surface via `container --help` and exits non-zero (code
`3`) for any real subcommand, pointing back to this doc.

## Per-target backend mapping

The CLI selects the same backend the GUI uses; execution availability follows
`wwn-containers/COMPLIANCE.md` and the eval-time
`nix eval wwn-containers#lib.capabilities` matrix.

| Target | `pull`/`images` (image mgmt) | `run`/`exec` (execution) | Backend |
| --- | --- | --- | --- |
| macOS (direct/notarized) | Yes | Yes | Apple `containerization.framework` (`wwn-containerd`) |
| macOS (Mac App Store) | Yes | **No** | image management only (no VM spawning under MAS) |
| iOS / iPadOS / visionOS | Yes | Yes | container-in-VM via `wwn-vms` QEMU-TCTI (crun in-guest) |
| tvOS | Yes | Limited | container-in-VM (minimal guest) or image-mgmt only |
| watchOS | Yes | **No** | image management only |
| Android | Yes | Yes | container-in-VM (QEMU/AVF) or rootless proot |

Where execution is unavailable, the lifecycle subcommands must fail cleanly with
a capability message (never fake execution).

## Compliance requirements (must hold for every target)

Inherited from `wwn-containers/COMPLIANCE.md`. The CLI does not get to relax any
of these:

- **Image management is universal and always compliant** (no code execution).
- **No execution without a kernel**. Apple Containerization on macOS or a
  `wwn-vms` VM everywhere else; on watchOS / MAS the CLI offers image management
  only.
- **No JIT on Apple targets**. Mobile execution rides the jitless QEMU-TCTI VM.
- **No downloaded executables on Apple targets**. Kernels/rootfs/runtime are
  bundled resources; only OCI *image data* is fetched at runtime.
- **Rootless where possible**. The Android proot path needs no root and no JIT.

## Integration points to wire (later)

1. `wwn-oci` gains a stable local-store layout + a library/IPC surface the CLI
   calls for `pull`/`images`/`inspect`/`rmi` on every target.
2. `container run`/`exec` dispatch to the per-target execution backend
   (`wwn-containerd` on macOS; the container-in-VM guest elsewhere) and attach the
   guest Wayland session into Wawona over vsock + waypipe.
3. `wwn-zsh` places `container` on the terminal `PATH` (Apple: in-process inside
   `zsh.framework`; Android: bundled binary).
4. Settings → Containers and Machine profile → Containers write the same config
   keys the CLI reads (runtime, image store path, default vsock port), so GUI and
   CLI stay consistent. Backend selection continues to flow through
   `WWNContainerRunner` / `WAWONA_CONTAINER_BACKEND`.

## Non-goals / honest limits

- No execution on watchOS or under the Mac App Store sandbox. Image management
  only there.
- No Docker-daemon socket compatibility promised; this is a Wawona-native CLI
  over `wwn-oci` + per-target backends, not a `dockerd` drop-in.
