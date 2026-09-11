# wwn-containers. Mode A / Mode B

Canonical product split: [Wawona `docs/mode-a-b.md`](mode-a-b.md).
Run backend is container-in-VM on Wawona Relay. Not QEMU. Not UTM. Not host
Docker.

## Goal

One Machines kind `container`. Shared OCI pull. Run is OCI inside the same
Linux VM Relay starts for `virtual_machine`.

| Mode | Run backend | Distribution |
|------|-------------|--------------|
| **A** (App Store) | container-in-VM on Relay jitless CPU. Planned. Fail closed | Store IPA |
| **B** (TrollStore now) | container-in-VM on Relay Mode B CPU. Planned. Fail closed | `Wawona-{calver}-iOS-arm64.tipa` |
| **B** (Sileo later) | same Relay container-in-VM | `repo.wawona.io` Sileo package |

macOS may use Apple Containerization on that host only
(`appleContainerizationGate`). Never evaluate that engine on iOS / Android /
Linux.

## Never

- `wpm install` meaning Docker Hub Linux images
- Shipping a JIT container engine in the App Store IPA
- QEMU / TCTI / `wwn-qemu-run` as the container-in-VM CPU
- Faking execution on watchOS / tvOS / visionOS
- Documenting container frames as done before Relay boots the guest

## Relation to Wasm packages

`wpm` / `repo.wawona.io/wasm` installs WASI modules for Wawona Runtime. That
is not `container pull`. Do not merge indexes.

## Success (not reached on iOS yet)

- Mode A: `container pull` plus run via Relay jitless VM
- TrollStore Mode B tipa: same UX through Relay Mode B CPU
- Official tipa after Relay frames, not before
