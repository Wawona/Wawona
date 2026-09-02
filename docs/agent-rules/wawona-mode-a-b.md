# Mode A / Mode B. Product-wide (Cursor rule)

Authority: `Wawona/docs/mode-a-b.md`. Prefer that doc when Mode B is framed as
only macOS iland Desktop.

**iOS install channels (TrollStore vs Sileo):** see
[`wawona-ios-mode-b-channels.md`](./wawona-ios-mode-b-channels.md).

## Definitions

- **Mode A**: App Store / TestFlight / Play / store-shaped builds. Compliance
  first. **No JIT** on Apple mobile. **Never** ship Mode B engines or jailbreak
  copy in these artifacts.
- **Mode B**: Privileged builds. On iOS/iPadOS that means either **TrollStore
  sideload** (JIT + IOMobileFramebuffer + Desktop/LockScreen) or **Sileo from
  `repo.wawona.io`** (full Mode B: JIT plus Desktop, LockScreen, Swinging
  Bridge). macOS Desktop needs SIP fully disabled (`csrutil disable`). Android
  Mode B is root/privileged outside Play. **not** ASC/Play.

## iOS / iPadOS (design both always)

| | Mode A (store IPA) | TrollStore (`ldid`) | Sileo Mode B (jailbreak) |
|---|---|---|---|
| VMs | QEMU-TCTI **jitless** | QEMU/UTM **+ JIT** | QEMU/UTM **+ JIT** |
| Containers | container-in-VM jitless | container-in-VM **+ JIT** | container-in-VM **+ JIT** |
| Wasm | Runtime, no JIT | Wasm **+ JIT** allowed | Wasm **+ JIT** allowed |
| Shell | `wwn-zsh` hatch | Sideload / sandbox as designed | Unsandboxed + host APT |
| Desktop / LockScreen | Forbidden | **Yes** (IOMFB own-display) | **Yes** (default; + ElleKit tweaks) |
| Swinging Bridge | Forbidden | No | **Yes** (Mode B, default) |

`repo.wawona.io` **auto-packages** Mode B IPA / `.deb` for Sileo. Store CI must fail
if Mode B/JIT/jailbreak engage is linked into Mode A. Website may document
TrollStore; store binaries must not.

## Hard rules

1. Design `wwn-vms`, `wwn-containers`, Wasm Runtime backends, and Wawona Machines
   with **A and B** in mind from day one (shared OCI/profiles; divergent engines
   behind flavor / `WWN_MODE_B`).
2. **Never** ship Mode B to App Store / Play (no “hidden toggle”).
3. Do not conflate: iland macOS Desktop dylib ≠ iOS Mode B IPA ≠ Wawona Swinging Bridge Mode B.
4. Wasm **packages** stay bytecode (`/wasm/`). Mode B may JIT-execute them; Mode A must not.
5. Jailbreak `.deb` is Sileo-only. Store binaries never touch `/jailbreak/`.
6. tvOS / watchOS: no VM/container machine kinds. visionOS Mode A = same
   jitless UTM-SE class as iOS; Mode B IPA policy follows product gates.
7. Never link ElleKit into store IPA or TrollStore `.tipa`.

See also: `wawona-ios-mode-b-channels`, `wawona-iland-mode-b-desktop`,
`wawona-swinging-bridge`, `wawona-platform-targets`,
`docs/vms-mode-a-b.md`, `docs/containers-mode-a-b.md`,
`docs/wasm-package-manager.md`, `docs/linux-dmabuf-zero-copy.md`.
