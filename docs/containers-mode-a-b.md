# wwn-containers — Mode A / Mode B implementation plan

Canonical product split: [Wawona `docs/mode-a-b.md`](https://github.com/Wawona/Wawona/blob/development/docs/mode-a-b.md).
Mirror: keep this file in sync with `Wawona/docs/containers-mode-a-b.md`.

## Goal

One Machines kind `container`, shared OCI management, two iOS-family **run**
backends:

| Mode | Run backend | Distribution |
|------|-------------|--------------|
| **A** (App Store) | container-in-VM on **jitless** UTM-SE / QEMU-TCTI (`wwn-vms` A) | Store IPA |
| **B** (jailbreak) | container-in-VM on **JIT** UTM (`wwn-vms` B) | Sileo Mode B IPA |

macOS Mode A/B: Apple Containerization on direct/notarized macOS; image mgmt
only under MAS. Android: container-in-VM and/or rootless proot (Play-safe);
root Mode B optional later.

## Shared substrate (both modes)

- `wwn-oci`: pull / verify / CAS / unpack (Docker Hub, etc.) — **Mode A safe**
- `container` CLI surface (image mgmt everywhere execution is gated)
- Machine profile `container` + Settings
- In-guest runtime concept (crun/podman) living **inside** the VM engine of the
  active mode

## Mode A implementation

1. Image pull works on all targets including watchOS (mgmt only).
2. iOS/iPadOS **run** = start jitless VM from `wwn-vms` Mode A → mount/unpack
   rootfs → crun in-guest → waypipe/vsock to Wawona.
3. CI: store artifact links only Mode A VM engine; no JIT container path.
4. Review Notes: “OCI image data + in-app interpreter VM; no JIT.”

## Mode B implementation

1. Same OCI pull; **run** uses JIT VM engine from Mode B IPA.
2. Faster containers; may integrate with host jailbreak tooling where useful.
3. Packaged only in Sileo Mode B IPA via `repo.wawona.io` automation.
4. Must not appear in App Store binary (link/strip/flavor).

## Relation to Wasm packages

`wpm` / `repo.wawona.io/wasm` installs **WASI modules for Wawona Runtime**.
That is **not** `container pull`. Both exist under Mode A; Mode B adds jailbreak
APT for native tweaks. Do not merge indexes.

## Never

- `wpm install` meaning Docker Hub Linux images.
- Shipping JIT container-in-VM in the App Store IPA.
- Faking execution on watchOS / MAS.

## Phases

| Phase | Work |
|-------|------|
| 1 | OCI pull solid on iOS Mode A; run stub clear errors |
| 2 | Mode A container-in-VM e2e (jitless) |
| 3 | Mode B JIT run path + Sileo IPA wiring |
| 4 | Docker Hub demo image documented for both modes |

## Success

- Mode A: `container pull` + run alpine-class image via jitless VM.
- Mode B IPA: same UX with JIT engine; published from `repo.wawona.io`.
- Store binary contains zero Mode B container engine.
