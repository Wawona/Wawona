# Wawona Mode A vs Mode B (product-wide)

Canonical split for **every** privileged feature: graphics Desktop, Wawona Swinging Bridge,
shell, VMs, containers, and package management. Prefer this over older prose
that treated “Mode B” as macOS-iland-only.

| | **Mode A** | **Mode B** |
|---|---|---|
| **Who** | App Store / TestFlight / Play / store-shaped macOS | Jailbreak (iOS/iPadOS), SIP-disabled/partial macOS, rooted/privileged Android |
| **Distribution** | Apple / Google store binaries; notarized `.#wawona-macos` | `repo.wawona.io` (Sileo `.deb` + **Mode B IPA**), desktop-host macOS flavor, sideload/TrollStore where documented on the **website only** |
| **In store IPA/AAB** | Only Mode A | **Never** — no Mode B engines, no jailbreak strings, no JIT |

Related: [`iland-mode-a-b-desktop.md`](./iland-mode-a-b-desktop.md) (macOS iland
Desktop dylib), [`swinging-bridge.md`](./swinging-bridge.md), [`vms-containers.md`](./vms-containers.md),
[`wasm-package-manager.md`](./wasm-package-manager.md),
[`repo.wawona.io`](https://github.com/Wawona/repo.wawona.io).

Tracking: [#162](https://github.com/Wawona/Wawona/issues/162).

---

## Mode A — App Store / Play compliance

Design every iOS-family and Play path as Mode A first.

### Always true on Mode A

- In-process ports where Apple mobile forbids `fork`/`exec` of arbitrary code
  (`wwn-zsh`, dispatch, libssh2).
- **No JIT** on Apple mobile (no `MAP_JIT`, no Hypervisor for guests).
- **VMs / containers (iOS family):** UTM-SE–class **jitless interpreter**
  (`wwn-vms` QEMU-TCTI). Containers = OCI image pull (`wwn-oci`) +
  **container-in-VM** on that jitless engine (`wwn-containers`). Same idea as
  Apple Container on macOS, without JIT.
- **Wasm packages:** `repo.wawona.io/wasm/` + Files drop + `wpm` — bytecode as
  **data** for Wawona Runtime (`wwn-wasm`). Not Mach-O, not `.deb`.
- **iland:** `libiland_userland.a` present callback only (no Desktop `.dylib`).
- tvOS / watchOS / visionOS: **no** VM/container machine kinds (policy).

### Never in Mode A binaries

- JIT-enabled UTM / QEMU TCG JIT on iOS family.
- Sileo / Procursus APT client UI, jailbreak Desktop/LockScreen engage, “install
  Mode B IPA” prompts.
- References to `repo.wawona.io/jailbreak/` or `.deb` tweak install from the app.
- Unsigned native code download/`dlopen`.

---

## Mode B — jailbreak / SIP / root

Mode B is **privileged host** access. Platforms:

| Host | Mode B trigger |
|------|----------------|
| **iOS / iPadOS** | Jailbreak + packages from `repo.wawona.io` (Sileo) |
| **macOS** | SIP Disabled or PartiallyDisabled (Debugging Restrictions) + desktop-host / privileged paths |
| **Android** | Root / privileged paths outside Play requirements |

### iOS / iPadOS Mode B (full)

On jailbreak, Wawona may use the host like NewTerm + UTM JIT + tweak stack:

| Capability | Mode B |
|------------|--------|
| Desktop + LockScreen replacement | Yes (`.deb` / tweak + Mode B IPA as designed) |
| Shell | Real jailbreak shell / unsandboxed zsh — **not** limited to `wwn-zsh` hatch |
| Host CLI | Jailbreak APT packages, NewTerm-class tools |
| **VMs** | **JIT-enabled** UTM / QEMU |
| **Containers** | **JIT-enabled** container-in-VM (same JIT engine) |
| Wasm Runtime packages | Still available (`/wasm/`); plus host APT for native tweaks |
| Wawona Swinging Bridge Mode B | UIKit→Wayland bridge tweak path |

### Mode B IPA on `repo.wawona.io` (critical)

`repo.wawona.io` must **automatically package and publish** a **Wawona iOS Mode B
IPA** (Sileo-installable), distinct from the App Store IPA.

When a user installs that Mode B build via Sileo they get:

1. Containers with **JIT** enablement  
2. Virtual machines with **JIT** enablement  
3. Access to **jailbroken iOS APT tooling** already on device (and repo `.deb`s)

App Store / TestFlight builds remain Mode A only and **must never** embed or
switch into this IPA’s JIT backends.

### macOS Mode B (summary)

- iland Desktop/LockScreen: `libwayland-mac.dylib` in `.#wawona-macos-desktop-host`
  only — see [`iland-mode-a-b-desktop.md`](./iland-mode-a-b-desktop.md).
- VMs: Virtualization.framework (already privileged vs MAS).
- Containers: Apple Containerization (macOS-only engine).

### Android Mode B (summary)

- Play = Mode A (no root required for Home/Desktop Mode A story).
- Mode B = root/privileged bridges (Wawona Swinging Bridge Mode B, optional faster VM paths).
- Never ship Mode B-only code in Play AAB.

---

## VMs + containers — design both modes always

`wwn-vms`, `wwn-containers`, and Wawona Machines UI **must** compile and reason
about Mode A and Mode B on iOS family at all times. Feature flags / product
flavors select the engine; Mode B code is **absent** from store artifacts
(compile-time `#if`, separate scheme, or stripped link), not merely hidden.

```text
                 Machines: virtual_machine | container
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
     Mode A (store IPA)              Mode B (Sileo IPA)
     UTM-SE / QEMU-TCTI              UTM / QEMU + JIT
     jitless interpreter             JIT enablement
              │                               │
              └──────────┬────────────────────┘
                         ▼
              shared: OCI pull (wwn-oci), profiles, waypipe/vsock GUI
```

| Concern | Shared | Mode A only | Mode B only |
|---------|--------|-------------|-------------|
| OCI pull / CAS | Yes | — | — |
| Machine profiles UI | Yes (no jailbreak copy in A) | Store strings | May mention JIT/Sileo on website; B IPA may expose JIT settings |
| Guest boot engine | Interface | TCTI / UTM-SE | JIT UTM |
| Container run | Interface | container-in-VM (jitless) | container-in-VM (JIT) |
| Verification | — | `verify-*-mode-a` / no JIT symbols | CI for Mode B IPA + Sileo package |

Implementation plans: [`vms-mode-a-b.md`](./vms-mode-a-b.md),
[`containers-mode-a-b.md`](./containers-mode-a-b.md) (also mirrored in
`wwn-vms` / `wwn-containers`).

---

## Package manager inside Mode A + Mode B

From [`wasm-package-manager.md`](./wasm-package-manager.md):

| Channel | Mode A | Mode B |
|---------|--------|--------|
| `repo.wawona.io/wasm/` | Default registry for `wpm` / Packages GUI | Same Wasm registry still works |
| `repo.wawona.io/jailbreak/` APT | **Forbidden** in app | Sileo + Mode B IPA; native `.deb` tweaks + host APT |
| Files.app `.wasm` | Yes | Yes |
| Debian `.deb` as Runtime packages | Never | Never (`.deb` ≠ Wasm) |

Store builds: Wasm-only package client. Mode B: Wasm client **plus** jailbreak
APT ecosystem.

---

## Documentation firewall

| Surface | Mode A detail | Mode B / jailbreak / JIT |
|---------|---------------|---------------------------|
| App Store IPA, TestFlight, Play | Full | **Zero** |
| `wawona.io` user docs | Full | Allowed on dedicated pages |
| `repo.wawona.io` | `/wasm/` | `/jailbreak/` + Mode B IPA packaging |
| Cursor / AGENTS rules | Both, labeled | Both, labeled |

---

## Hard rules (review checklist)

1. **Never ship Mode B to the App Store / Play.** Separate artifact + CI gate.
2. **Design A and B together** in `wwn-vms` / `wwn-containers` / Wawona — shared
   OCI and Machines model; divergent engines behind a capability gate.
3. **iOS Mode A VMs/containers = interpreter (UTM-SE-class) only.**
4. **iOS Mode B VMs/containers = JIT UTM-class**; packaged via Sileo Mode B IPA.
5. **Wasm packages are Mode A–safe** and remain available under Mode B; they do
   not replace jailbreak APT.
6. **Do not conflate** iland Mode B (macOS dylib), Wawona Swinging Bridge Mode B, and iOS Mode B
   IPA — related privilege class, different artifacts.
