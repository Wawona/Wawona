# Wawona Mode A vs Mode B (product-wide)

Canonical split for **every** privileged feature: graphics Desktop, Wawona Swinging Bridge,
shell, VMs, containers, and package management. Prefer this over older prose
that treated “Mode B” as macOS-iland-only.

| | **Mode A** | **Mode B** |
|---|---|---|
| **Who** | App Store / TestFlight / Play / store-shaped macOS | Jailbreak (iOS/iPadOS), TrollStore sideload, SIP fully disabled for macOS Desktop/LockScreen (`csrutil disable`), rooted/privileged Android |
| **Distribution** | Apple / Google store binaries; notarized `.#wawona-macos` | **TrollStore** `.tipa` (`ldid`: JIT + IOMobileFramebuffer + Desktop/LockScreen), `repo.wawona.io` Sileo (rootless/rootful `.deb` + Mode B IPA + tweaks), desktop-host macOS flavor. Website only for sideload/jailbreak docs |
| **In store IPA/AAB** | Only Mode A | **Never**. No Mode B engines, no jailbreak strings, no JIT, no framebuffer SPI |

Related: [`iland-mode-a-b-desktop.md`](./iland-mode-a-b-desktop.md) (macOS iland
Desktop dylib), [`swinging-bridge.md`](./swinging-bridge.md), [`vms-containers.md`](./vms-containers.md),
[`wasm-package-manager.md`](./wasm-package-manager.md),
[`linux-dmabuf-zero-copy.md`](./linux-dmabuf-zero-copy.md),
[`agent-rules/wawona-ios-mode-b-channels.md`](./agent-rules/wawona-ios-mode-b-channels.md),
[`repo.wawona.io`](https://github.com/Wawona/repo.wawona.io).

Tracking: [#162](https://github.com/Wawona/Wawona/issues/162).

---

## iOS / iPadOS install channels (critical)

Do **not** treat “Mode B” as a single binary. Three user-facing channels:

| Channel | JIT | IOMobileFramebuffer / own-display | Desktop + LockScreen | Swinging Bridge |
|---|---|---|---|---|
| **App Store / TestFlight** | No | No | No | No |
| **TrollStore (`ldid`)** | Yes | Yes | Yes (in-app own-display) | No |
| **Sileo (`repo.wawona.io`)** | Yes | Yes | Yes (+ SpringBoard tweaks) | Yes + host APT |

| Channel | How | VMs / containers / Wasm |
|---|---|---|
| **App Store / TestFlight** | ASC | **Jitless** QEMU-TCTI; Wasm **without** JIT |
| **TrollStore sideload** | Website `.tipa` + TrollStore | **JIT** for VMs, containers, and Wasm |
| **Sileo (`repo.wawona.io`)** | Jailbreak + Mode B IPA / `.deb` | **JIT** for VMs, containers, and Wasm |

- Store IPA: never mention TrollStore, Sileo, jailbreak, JIT, or framebuffer SPI.
- Website + `repo.wawona.io` document TrollStore and Sileo.
- TrollStore Desktop is **IOMobileFramebuffer own-display** inside the Mode B
  app (no ElleKit). Sileo adds SpringBoard injection (ElleKit on rootless),
  host APT, and Swinging Bridge.
- Never ship one ASC binary with a runtime “enable JIT / framebuffer” toggle.

QEMU implementation:

```text
Mode A (store)           →  -accel tcg / TCTI (UTM SE). Interpreter ceiling.
TrollStore or Sileo IPA  →  QEMU/UTM + JIT (Mode B scheme / WWN_MODE_B only).
```

---

## Mode A. App Store / Play compliance

Design every iOS-family and Play path as Mode A first.

### Always true on Mode A

- In-process ports where Apple mobile forbids `fork`/`exec` of arbitrary code
  (`wwn-zsh`, dispatch, libssh2).
- **No JIT** on Apple mobile (no `MAP_JIT`, no Hypervisor for guests).
- **VMs / containers (iOS family):** UTM-SE-class **jitless interpreter**
  (`wwn-vms` QEMU-TCTI / `-accel tcg`). Containers = OCI image pull (`wwn-oci`) +
  **container-in-VM** on that jitless engine (`wwn-containers`).
- **Wasm packages:** `repo.wawona.io/wasm/` + Files drop + `wpm`. Bytecode as
  **data** for Wawona Runtime (`wwn-wasm`). **No Wasm JIT** in Mode A. Not Mach-O,
  not `.deb`.
- **iland:** `libiland_userland.a` present callback only (no Desktop `.dylib`).
- Present: public Metal / `CAMetalLayer` only.
- tvOS / watchOS: **no** VM/container machine kinds (policy). visionOS Mode A
  uses the same jitless VM class as iOS when gated planned→available.

### Never in Mode A binaries

- JIT-enabled UTM / QEMU TCG JIT on iOS family.
- IOMobileFramebuffer SPI, ElleKit, Substrate, jailbreak Desktop/LockScreen engage.
- Sileo / Procursus APT client UI, “install Mode B IPA” prompts.
- References to `repo.wawona.io/jailbreak/` or `.deb` tweak install from the app.
- Unsigned native code download/`dlopen`.

---

## Mode B. Jailbreak / TrollStore / SIP / root

Mode B is **privileged host** access. On iOS/iPadOS there are **two** privileged
install paths (see [install channels](#ios--ipados-install-channels-critical)):

| Host | Mode B trigger |
|------|----------------|
| **iOS / iPadOS (TrollStore)** | Sideloaded `.tipa` with `ldid` entitlements. JIT + IOMobileFramebuffer + Desktop/LockScreen (in-app). **No** Swinging Bridge / host APT / ElleKit |
| **iOS / iPadOS (Sileo)** | Jailbreak + `repo.wawona.io` Mode B IPA / `.deb` + tweaks. Full Mode B including Swinging Bridge |
| **macOS** | Desktop/LockScreen (iland Mode B): SIP fully disabled (`csrutil disable`) + `wawona-macos-desktop-host`. Other privileged Mode B paths (Swinging Bridge) are separate |
| **Android** | Root / privileged paths outside Play requirements |

### iOS / iPadOS Mode B (TrollStore)

| Capability | TrollStore Mode B |
|------------|-------------------|
| Desktop + LockScreen | Yes (IOMobileFramebuffer own-display greeter) |
| Shell | Sideload / sandbox as designed for the Mode B IPA |
| **VMs** | **JIT-enabled** UTM / QEMU |
| **Containers** | **JIT-enabled** container-in-VM |
| Wasm Runtime | Packages still from `/wasm/`; Mode B may **JIT-execute** Wasm |
| Wawona Swinging Bridge | **No** (Sileo only) |
| ElleKit / SpringBoard inject | **No** |

Ship: `Wawona-{calver}-iOS-arm64.tipa` on GitHub Releases. Never Ship: beta / TestFlight.

### iOS / iPadOS Mode B (full Sileo)

On jailbreak, Wawona may use the host like NewTerm + UTM JIT + tweak stack:

| Capability | Sileo Mode B (default) |
|------------|--------|
| Desktop + LockScreen replacement | Yes (IOMFB and/or SpringBoard tweak + Mode B IPA) |
| Shell | Real jailbreak shell / unsandboxed zsh. **not** limited to `wwn-zsh` hatch |
| Host CLI | Jailbreak APT packages, NewTerm-class tools |
| **VMs** | **JIT-enabled** UTM / QEMU |
| **Containers** | **JIT-enabled** container-in-VM |
| Wasm Runtime | Packages still from `/wasm/`; Mode B may **JIT-execute** Wasm |
| Wawona Swinging Bridge Mode B | UIKit→Wayland bridge. **Enabled out of the box** |

Rootless (`.deb` `Architecture: iphoneos-arm64`, prefix `/var/jb`) and rootful
(`Architecture: iphoneos-arm`, prefix `/`) are **separate builds**. Rootless
SpringBoard tweaks depend on **ElleKit**. Never link ElleKit into store or
TrollStore artifacts.

### Mode B packages on `repo.wawona.io` (critical)

`repo.wawona.io` publishes under `/jailbreak/` (never `/wasm/`):

- Mode B IPA / app `.deb` (rootless and rootful)
- ElleKit SpringBoard tweaks (Desktop / LockScreen / Swinging Bridge inject)
- Test packages for the vphone `jb` guest lab

App Store / TestFlight builds remain Mode A only and **must never** embed or
switch into these backends.

### macOS Mode B (summary)

- iland Desktop/LockScreen: `libwayland-mac.dylib` in `.#wawona-macos-desktop-host`
  only. See [`iland-mode-a-b-desktop.md`](./iland-mode-a-b-desktop.md).
- VMs: QEMU + HVF on macOS (`Hypervisor.framework`). See `wwn-vms`.
- Containers: Apple Containerization (macOS-only engine).
- macOS is **never** App Store feature-gated (`wawona-macos-no-appstore`).

### Android Mode B (summary)

- Play = Mode A (no root required for Home/Desktop Mode A story).
- Mode B = root/privileged bridges (Wawona Swinging Bridge Mode B, optional faster VM paths).
- Never ship Mode B-only code in Play AAB.

---

## VMs + containers. Design both modes always

`wwn-vms`, `wwn-containers`, and Wawona Machines UI **must** compile and reason
about Mode A and Mode B on iOS family at all times. Feature flags / product
flavors select the engine; Mode B code is **absent** from store artifacts
(compile-time `#if`, separate scheme / `WWN_MODE_B`, or stripped link), not merely hidden.

```text
                 Machines: virtual_machine | container
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
     Mode A (store IPA)         Mode B IPA (TrollStore and/or Sileo)
     QEMU-TCTI / TCG            QEMU / UTM + JIT
     jitless interpreter        JIT (+ Wasm JIT) + IOMFB Desktop
              │                               │
              └──────────┬────────────────────┘
                         ▼
              shared: OCI pull (wwn-oci), profiles, waypipe/vsock GUI

     Sileo jailbreak only (not TrollStore):
              Swinging Bridge Mode B + host APT + ElleKit SpringBoard tweaks
```

| Concern | Shared | Mode A only | Mode B (TrollStore / Sileo) | Sileo-only |
|---------|--------|-------------|------------------------------|------------|
| OCI pull / CAS | Yes | - | - | - |
| Machine profiles UI | Yes (no jailbreak copy in A) | Store strings | JIT + Desktop settings OK in B IPA | SB UI |
| Guest boot engine | Interface | TCTI / UTM-SE | JIT UTM/QEMU | - |
| Container run | Interface | container-in-VM (jitless) | container-in-VM (JIT) | - |
| Desktop present | - | Metal in-window | IOMobileFramebuffer | + ElleKit tweak |
| Wasm execute | `/wasm/` packages | No JIT | Wasm JIT allowed | + host APT |
| Verification | - | `verify-*-mode-a` / no Mode B symbols | Mode B `.tipa` CI | Sileo `.deb` + tweaks |

Implementation plans: [`vms-mode-a-b.md`](./vms-mode-a-b.md),
[`containers-mode-a-b.md`](./containers-mode-a-b.md) (also mirrored in
`wwn-vms` / `wwn-containers`).

---

## Package manager inside Mode A + Mode B

From [`wasm-package-manager.md`](./wasm-package-manager.md):

**Wasm is not platform-native** (tradeoff vs a Mach-O port). The payoff is a
**portable Wawona Runtime** plus dedicated **`wpm`**, with **full App Store /
Play compliance** via WASI P1/P2. Store (Mode A) Runtime never requires
jailbreak. Mode B IPAs may still ship a **JIT-capable Wasm backend** when the
JIT entitlement is present (TrollStore or Sileo). Packages remain `.wasm`
bytecode on `/wasm/`; they are not `.deb`.

| Channel | Mode A | Mode B (TrollStore / Sileo) |
|---------|--------|------------------------------|
| `repo.wawona.io/wasm/` | Default registry for `wpm` / Packages GUI | Same Wasm registry; **JIT execute** allowed in B IPA |
| `repo.wawona.io/jailbreak/` APT | **Forbidden** in app | Sileo only; native `.deb` tweaks + host APT |
| Files.app `.wasm` | Yes (no JIT) | Yes (JIT allowed in B) |
| Debian `.deb` as Runtime packages | Never | Never (`.deb` ≠ Wasm) |

Store builds: Wasm-only package client. Mode B Sileo: Wasm client **plus** jailbreak
APT ecosystem.

---

## Documentation firewall

| Surface | Mode A detail | Mode B / jailbreak / JIT / IOMFB |
|---------|---------------|----------------------------------|
| App Store IPA, TestFlight, Play | Full | **Zero** |
| `wawona.io` user docs | Full | Allowed on dedicated pages (Download picker, Mode A/B) |
| `repo.wawona.io` | `/wasm/` | `/jailbreak/` + Mode B IPA / `.deb` / tweaks |
| Cursor / AGENTS rules | Both, labeled | Both, labeled |

---

## Hard rules (review checklist)

1. **Never ship Mode B to the App Store / Play.** Separate artifact + CI gate.
2. **Design A and B together** in `wwn-vms` / `wwn-containers` / Wawona. Shared
   OCI and Machines model; divergent engines behind a capability gate / `WWN_MODE_B`.
3. **iOS Mode A VMs/containers = interpreter (QEMU-TCTI / UTM-SE) only.**
4. **iOS Mode B VMs/containers/Wasm JIT** via TrollStore and/or Sileo Mode B IPA.
5. **TrollStore** also enables IOMobileFramebuffer Desktop / LockScreen (in-app).
   It does **not** enable Swinging Bridge or host APT.
6. **Sileo full Mode B** also enables Swinging Bridge, host APT, and ElleKit
   SpringBoard tweaks by default.
7. **Wasm packages stay Mode A-safe data** (`/wasm/`); Mode B may JIT-execute.
   They do not replace jailbreak APT.
8. **Do not conflate** iland Mode B (macOS dylib), Wawona Swinging Bridge Mode B,
   and iOS Mode B IPA / `.tipa` / `.deb`. Related privilege class, different artifacts.
9. **Never link ElleKit** into store IPA or TrollStore `.tipa`.
