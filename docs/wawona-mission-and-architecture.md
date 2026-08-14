# Wawona: mission and architecture

> **Public subset** for wawona.io.

Canonical statement of what Wawona is for. When a design decision is ambiguous,
this document decides it. Per-target detail lives in the rules it links to; this
is the intent those rules serve.

## The goal

**Run any desktop software, on any platform, natively.**

Wawona is a Wayland compositor written in Rust that makes **no assumptions about
the host compositor**. Instead of porting a Linux display stack to each OS, it
exposes a portable API surface that each platform's native UI framework
integrates with on its own terms:

| Host | Native integration |
|---|---|
| macOS | AppKit / Cocoa + Metal |
| iOS, iPadOS | UIKit + Metal |
| visionOS | SwiftUI/RealityKit + Metal (macOS product parity) |
| tvOS | UIKit + Metal |
| watchOS | WatchKit |
| Android | Jetpack Compose / native surfaces |
| Linux | GTK front-end — runs **under X11 or under another Wayland compositor** |

The host-agnosticism is the point, not a side effect. Because bridging to native
GUI is Wawona's own job, nothing in the compositor core presumes a Wayland (or
even a desktop) host. A future browser/WASM or custom-environment front-end is a
new backend, not a rewrite.

## Three ways to run a client

Wawona is not a remote-desktop viewer. A Wayland client reaches the user through
whichever of these fits the platform:

1. **Native** — the client (or a nested compositor) is cross-compiled to the
   host ABI and runs on the machine itself. Apple mobile runs these in-process as
   static libraries; macOS uses its unrestricted native process model; Android
   uses native artifacts. The **on-device shell** (bundled zsh) is this path.
2. **Container** — planned Machine kind on macOS, iOS, iPadOS, Android, and
   Linux (`wwn-containers` / Containerization.framework on macOS). Forbidden on
   tvOS, watchOS, visionOS.
3. **VM or remote machine** — planned in-GUI VMs on the same platform set as
   containers (`wwn-vms`; UTM-SE on iOS/iPadOS; Virtualization.framework on
   macOS), plus remote guests over patched `waypipe-rs`.

Every Machines feature must be classified as native / remote / VM / container and
refused on targets that forbid that class. See `wawona-platform-targets` and
`docs/vms-containers.md`.

## Userland DRM/KMS/GBM (wwn-iland)

Linux graphics clients expect a kernel display stack. Apple and Android do not
provide one, and a store-shipped app may not add one. `wwn-iland` therefore
implements **DRM/KMS/GBM entirely in userspace**, emulating KMS objects
(connector, CRTC, plane, framebuffer) over IOSurface + Metal on Apple and
AHardwareBuffer on Android — no kernel interaction, no Linux required.

This is what makes nested compositors and unmodified GL/Vulkan clients possible
inside a sandboxed, store-distributed app.

- **Mode A** is the default and the App Store / Play compliance path: static
  `libiland_userland.a`, in-window presentation, no SIP, no privileged code.
- **Mode B** is the privileged macOS-only path (below).

Detail: `wawona-iland-mode-b-desktop`, `docs/iland-mode-a-b-desktop.md`.

## Desktop and lockscreen replacement

**Coming soon.** Desktop and LockScreen make Wawona the **host** desktop
environment and greeter (machine picker; **native-port** profiles only).

- **macOS:** partial SIP (system debugging) + `.dylib` (**iland Mode B**) in
  `wawona-macos-desktop-host` — still in development.
- **Android:** Default Home App + LockScreen APIs — **no root**, no fallback
  tier — still in development.
- **iOS / iPadOS:** only as a jailbreak tweak from **`repo.wawona.io`**
  (website docs). App Store builds keep this **forbidden** and must **never
  mention jailbreak**. iPhone and iPad share the same policy.
- **Not** Linux. **Not** App Store tvOS / watchOS / visionOS.

Detail: `wawona-iland-mode-b-desktop`, `docs/iland-mode-a-b-desktop.md`.

## anowaW (app bridge — separate from Desktop/LockScreen)

**Coming soon.** anowaW bridges **macOS / Android / iOS / iPadOS** host apps
onto Wayland surfaces (zero-copy surface bridge). It is **not** Desktop/LockScreen
and **not** MediaProjection-as-desktop. Mode A ships in store/Play-shaped builds;
Mode B is privileged (macOS partial SIP, Android root paths, iOS/iPadOS via
`repo.wawona.io`) and **forbidden** in App Store / Play artifacts.

Detail: `wawona-anowaw`, `docs/anowaw.md`.

Where Wawona is not replacing the desktop, it integrates with it: clients appear
as ordinary host windows under the proprietary host compositor.

## Decorations are negotiated, not assumed

Wawona is a Wayland compositor, so the client's right to ask for client-side or
server-side decorations must be honoured through the decoration protocols
(`xdg-decoration`).

- **macOS** supports both: CSD per client, or forced SSD using native macOS
  window chrome.
- **Android and the entire iOS family** have no meaningful CSD story, so SSD is
  forced there.

Host window-manager behaviour per target is fixed by
`PlatformCapabilities.hostWindowManagerPolicy`; see `wawona-platform-targets`.

## Bundled ported software

Wawona ships real Linux software compiled natively into the app — **Niri** and
**Weston** are mandatory on every target (see `AGENTS.md`), alongside a growing
set of Wayland clients. These are genuine ports using the target's native ABI,
never stubs, fake entry points, or wrong-platform archives.

### The fidelity standard: waypipe equivalence

A ported client must be **indistinguishable from the same upstream client, built
normally on Linux, running against Wawona over waypipe.** Because Wawona also
supports the remote path, that reference is runnable: stream the real Linux build
in from a VM or remote host and compare. If they differ, the port is wrong.

A port substitutes the *platform underneath* the client — libc gaps, EGL→ANGLE,
Vulkan→MoltenVK/KosmicKrisp, DRM/KMS/GBM→`wwn-iland`, static linking shape. It
never substitutes the client's own behaviour: the protocols it speaks, the
windowing path upstream itself uses, its renderer, or its feature set.

That last point decides which graphics path a client gets. `kmscube` is a DRM/KMS
program upstream, so its port uses iland's userspace KMS. `opengl-cube` and
`vkcube` are Wayland clients upstream, so their ports must use Wayland-EGL and
Wayland Vulkan WSI — re-hosting them onto our KMS emulation because that path
happened to be finished first produces something that would look nothing like
itself over waypipe. Full rule: `wawona-port-fidelity`.

## The GUI is the product

Users will not set environment variables, and must never have to. Wawona provides
the complete GUI to create and configure **per-machine profiles** — how software
launches, which drivers and backends it uses, how it connects — with full control
and **without ever touching a terminal**. A feature that only works by exporting a
variable or editing a config file by hand is unfinished.

### Where upstream offers a choice, so do we

If a bundled client supports more than one way to run, that choice belongs to the
user, not to a hardcoded constant. The clearest case is the display backend:
`niri` and `weston` each have a real DRM/KMS backend as well as a nested-Wayland
one. Pinning them to nested throws away the userspace DRM/KMS/GBM path that
`wwn-iland` exists to provide, and hides the bare-metal-shaped behaviour that
Mode B ultimately depends on.

So the backend is a setting — global (`CompositorBackend`: `auto` | `wayland` |
`drm`) with a per-machine override — resolved at launch by
`WWNResolveCompositorBackend`, which maps it onto each client's own switch
(`NIRI_BACKEND=nested|tty`, `weston --backend=wayland|drm`). `auto` keeps the
nested default because it needs no GPU stack; an explicit choice always wins
where the platform allows it, and falls back with a log line where it cannot
(e.g. `OpenGLDriver=none` leaves DRM nothing to present through).

Apply the same reasoning to any other upstream-configurable dimension before
hardcoding it.

## Store compliance is a requirement, not an aspiration

Wawona ships to the App Store and Play Store while running arbitrary software
from the Linux ecosystem. Mode A exists to make that true simultaneously.

The asymmetry is fixed and non-negotiable:

- **Apple mobile** (iOS, iPadOS, tvOS, watchOS, visionOS) is the strict baseline:
  App Store Review Guideline 2.5.2 — no executable code beyond the signed bundle,
  no JIT, no fork/exec, in-process only, libssh2 only.
- **Android (Play)** is more permissive and may take those freedoms in
  Android-only code.
- **macOS is exempt.** Never constrain macOS to mobile store limits; see
  `wawona-macos-no-appstore`.

When a question is platform-ambiguous, answer Apple-mobile-strict and flag the
relaxations separately.

## Gating: four states, never one boolean

"Unsupported" is the most dangerous word in this codebase, because it hides four
situations that demand opposite responses. Every capability gate must say which
one it is — in the rules, in `CapabilityGate`
(`Sources/WawonaModel/PlatformCapabilities.swift`), and in the Nix registry.

| State | Meaning | Correct response |
|---|---|---|
| **available** | Shipping on this target | Keep it green |
| **planned** | Platform allows it; our work is unfinished | Finish it. Never let it harden into a removal |
| **blocked** | We want it; no public platform API exists | Re-check on SDK bumps. Never route around with private API |
| **forbidden** | Product or store policy | Never enable; refuse features of that class |

The graphics stack is the worked example, and the two "small" Apple targets land
in different states despite usually being lumped together:

- **tvOS — planned.** The SDK ships `Metal.framework` *and* `OpenGLES.framework`,
  with `CAMetalLayer` available since tvOS 9. Wayland GL, Vulkan, and userspace
  DRM/KMS/GBM on tvOS are all legal public-API work; they are off only because
  they are unfinished (final phase, `WWN_TVOS_GPU=1`).
- **watchOS — blocked.** The SDK ships no `Metal.framework` and annotates
  `CAMetalLayer` `API_UNAVAILABLE(watchos)`. ANGLE and MoltenVK both bottom out
  in Metal, so there is no floor. We want it; Apple offers nothing to build it
  on. SHM/CPU is the current ceiling, not a preference.
- **VM/containers on tvOS, watchOS, and visionOS — forbidden.** Policy, not a
  gap. On macOS, iOS, iPadOS, Android, and Linux they are **planned** (UTM-SE /
  Virtualization / Containerization / `wwn-vms` — see `docs/vms-containers.md`).
  The on-device shell is separate.

Two obligations follow. Never downgrade a `planned` gate into a permanent
exclusion to make CI green. Never upgrade a `blocked` gate by reaching for
private API — that trades store compliance, which Mode A exists to protect, for a
demo.

## What this rules out

- Assuming a host compositor, a kernel DRM device, or a Linux userland.
- Dropping a platform to unblock another, or shipping a stub in place of a port.
- Re-hosting a client onto a different windowing path than upstream uses, or any
  other change that would make it diverge from its waypipe-streamed reference.
- Features that require the terminal, or that only work with hand-set env vars.
- Applying mobile store restrictions to macOS, or macOS freedoms to mobile.
- Kernel-level interaction anywhere: iland stays entirely runtime/userspace.

## See also

- `wawona-platform-targets` — per-target capability matrix
- `wawona-iland-mode-b-desktop` — Mode A / Mode B split
- `wawona-macos-no-appstore` — macOS is never store-constrained
- `wawona-repo-dag` — L0–L4 repository layering
- `wawona-native-compositors` — Weston/Niri bundling requirement
