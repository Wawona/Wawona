# Mode A / Mode B — product-wide (Cursor rule)

Authority: `Wawona/docs/mode-a-b.md`. Prefer that doc when Mode B is framed as
only macOS iland Desktop.

## Definitions

- **Mode A** — App Store / TestFlight / Play / store-shaped builds. Compliance
  first. **No JIT** on Apple mobile. **Never** ship Mode B engines or jailbreak
  copy in these artifacts.
- **Mode B** — Jailbreak (iOS/iPadOS), SIP-disabled/partial macOS, rooted /
  privileged Android. Distributed via `repo.wawona.io` (Sileo `.deb` + **Mode B
  IPA**), `.#wawona-macos-desktop-host`, website-documented sideload — **not**
  ASC/Play.

## iOS / iPadOS (design both always)

| | Mode A (store IPA) | Mode B (Sileo Mode B IPA) |
|---|---|---|
| VMs | UTM-SE–class **jitless** (`wwn-vms`) | UTM/QEMU **+ JIT** |
| Containers | container-in-VM on jitless engine | container-in-VM **+ JIT** |
| Shell | `wwn-zsh` hatch | Unsandboxed / jailbreak shell + host APT |
| Desktop / LockScreen | Forbidden in-app | Yes via repo |
| Packages | `repo.wawona.io/wasm` + Files `.wasm` | Wasm **plus** jailbreak APT |

`repo.wawona.io` **auto-packages** the Mode B IPA for Sileo. Store CI must fail
if Mode B/JIT/jailbreak engage is linked into Mode A.

## Hard rules

1. Design `wwn-vms`, `wwn-containers`, and Wawona Machines with **A and B** in
   mind from day one (shared OCI/profiles; divergent engines behind flavor).
2. **Never** ship Mode B to App Store / Play (no “hidden toggle”).
3. Do not conflate: iland macOS Desktop dylib ≠ iOS Mode B IPA ≠ Wawona Swinging Bridge Mode B.
4. Wasm package manager is Mode A–safe; jailbreak `.deb` is Mode B–only channel.
5. tvOS / watchOS / visionOS: no VM/container machine kinds.

See also: `wawona-iland-mode-b-desktop`, `wawona-swinging-bridge`, `wawona-platform-targets`,
`docs/vms-mode-a-b.md`, `docs/containers-mode-a-b.md`,
`docs/wasm-package-manager.md`.
