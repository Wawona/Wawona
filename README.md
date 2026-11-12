# Wawona

[![Gate: packages (Linux/Android)](https://github.com/Wawona/Wawona/actions/workflows/nix.yml/badge.svg?branch=development&event=push&job=build-linux)](https://github.com/Wawona/Wawona/actions/workflows/nix.yml)
[![Gate: packages (macOS/iOS)](https://github.com/Wawona/Wawona/actions/workflows/nix.yml/badge.svg?branch=development&event=push&job=build-macos-x86_64)](https://github.com/Wawona/Wawona/actions/workflows/nix.yml)

**Wawona** is a native Wayland compositor for macOS, iOS, iPadOS, tvOS, watchOS, visionOS, Android, and Linux.
<div align="center">
  <img src="gallery/wawona_nested_plasma.png" alt="Wawona - Wayland Compositor Preview 1" width="800"/>
  <details>
    <summary>More previews</summary>
    <img src="gallery/wawona_nested_xfce.png" alt="Wawona - Wayland Compositor Preview 2" width="800"/>
    <img src="gallery/wawona_nested_cosmic.png" alt="Wawona - Wayland Compositor Preview 3" width="800"/>
  </details>
</div>

> **Mission:** [wawona-mission-and-architecture.md](docs/wawona-mission-and-architecture.md). Facts: [2026-SOURCE-OF-TRUTH.md](docs/2026-SOURCE-OF-TRUTH.md). Roadmap: [roadmap.md](docs/roadmap.md).

### What can you do with Wawona?

Wawona brings the Linux desktop world to devices that never had it. In plain terms:

- **Run Linux graphical apps on Mac, iPhone, iPad, Apple TV, Apple Watch, visionOS, Android, and Linux**. Wawona is a real Wayland compositor, so Wayland apps and desktops draw into a native window on the device.
- **Connect to a remote Linux machine and use its apps as if they were local**. Point Wawona at a Linux box over SSH and its windows appear on your screen, forwarded efficiently with Waypipe.
- **Nest full Linux desktops**. Run desktops and compositors like KDE Plasma, XFCE, COSMIC, sway, and niri inside Wawona (see the previews above).
- **Use a real terminal on iOS and iPadOS**. A genuine bundled `zsh` with common tools, running on-device and App Store-compliant (no jailbreak, no remote server required).
- **Manage many connections from one place**. Save machines and switch between them without digging through settings.

If you have used an SSH client or a remote desktop app before, think of Wawona as that, but for the whole Linux graphical stack, built natively for Apple and Android devices.

### Demo

A walkthrough video showcasing nested desktops, remote apps, and the on-device shell is planned ([#45](https://github.com/Wawona/Wawona/issues/45)). Until then, the previews above and the [Usage Guide](docs/usage.md) show what a running session looks like.

### App Store-compliant local zsh (iOS / iPadOS)

Wawona is engineering **the world's first App Store-compliant bundled native Z shell on iOS and iPadOS**. Real `zsh` + upstream Weston `terminal.c`, not a remote SSH passthrough or x86 Linux guest. Full architecture, compliance model, Nix plan, spawn policy, and TestFlight checklist:

**→ [docs/ios-local-shell/README.md](docs/ios-local-shell/README.md)**


### How do I build this?

With Xcode 27 on a Mac, or Android Studio for Android, see
[Building](#building) below. Nix is not required.

For device signing, copy the example and set your Apple Development Team ID;
`cargo xtask deps get` writes it into the Xcode project's signing settings:

```bash
cp .envrc.local.example .envrc.local   # then: source .envrc.local (or direnv allow)
```

> Build targets and the dependency pipeline: [Compilation Guide](docs/compilation.md) and [Nix Build System](docs/2026-nix-build-system.md). Cross-compiled libraries and toolchains live in upstream [`wwn-toolchain`](https://github.com/Wawona/wwn-toolchain) and sibling `wwn-*` repos.

### How do I install Wawona on macOS?

Download `Wawona-{calver}-macOS-arm64.dmg` from the [GitHub Releases](https://github.com/Wawona/Wawona/releases) and drag Wawona.app to Applications.

From a checkout, build the Release app and install it with its compositor and menubar LaunchAgents, the Desktop Replacement helper and the CLI wrappers (see [macOS CLI](docs/macos-cli.md)):

```sh
cargo xtask build macos --release
cargo xtask install
```

`cargo xtask uninstall` removes all of it. `nix run .#install` and `nix run .#uninstall` forward to the same commands. The flake overlay's `pkgs.wawona` is the Linux build.

### How do I run Weston or Waypipe?

- **Weston natively on macOS:** install it from [repo.wawona.io](https://repo.wawona.io) and start it from Machines (Native Shell)
- **Waypipe (remote apps):** Configure SSH in Settings > Waypipe, set Remote Command (e.g. `nix run ~/Wawona#weston-terminal`), tap Run Waypipe

See [Usage Guide](docs/usage.md) and [Settings Reference](docs/settings.md).

### Wawona on Linux (GTK4 + Libadwaita)

- **Native Linux UI:** `nix run .#wawona-linux`
  - Runs Wawona natively on Linux with a GTK4 / Libadwaita host shell (`src/bin/wawona-linux-ui.rs`).
  - Fluid session navigation with Tab Overview (`AdwTabOverview`), integrated Settings dialog (`AdwPreferencesWindow`), and machine management.
  - Wayland protocol conformance verified against WLCS (`wawona-wlcs`).

### VMs, Containers, and Wasm (Wawona Relay)

- **Engine:** [Wawona Relay](https://github.com/Wawona/Relay) (`wwn-relay`)
  - Linux virtual machines via host `cloud-hypervisor` (`/dev/kvm`), containers via OCI runtime, and Wasm packages for Store/WASI-P1/WASIX apps.
  - Zero QEMU dependency. Unified runtime across Linux, macOS, iOS, Android.

### Building

Apple and Android builds need Xcode 27 or Android Studio, Rust (rustup reads
`rust-toolchain.toml`) and nothing else:

```bash
cargo xtask deps get macosx iphonesimulator android   # prebuilt dependency slices
open Wawona.xcodeproj                                 # or open android/ in Android Studio
```

Press Run. The Xcode and Gradle projects build the Rust backend themselves,
so a Rust edit needs no extra step. `cargo xtask build <target>` does the same
from a shell (`macos`, `ios`, `ipados`, `ios-modeb`, `tvos`, `visionos`,
`watchos`, `android`); `cargo xtask --help` lists the rest: tests, archives,
the Mode B `.tipa` and Sileo debs, the macOS DMG. Details:
[Compilation Guide](docs/compilation.md).

**Nested Weston on iOS** presents in-process via Settings → Compositor clients. Two backends are available:

| Setting | Backend | Presentation |
|---------|---------|--------------|
| Wayland (Pixman). Default | `--backend=wayland --use-pixman` | xdg_toplevel in Wawona window |
| iland DRM (GL) | `--backend=drm` | Metal overlay (`WWNIlandPresenter`) |

Production `weston.ini`, bundled `terminal.png`, and Adwaita cursors ship in the app bundle. Startup target: panel visible within ~2s on the Pixman path.

### Why Nix?

Nix builds what an IDE cannot: the cross-compiled C libraries (`libwayland`,
`ffmpeg`, cairo, ANGLE, …) for every platform, pinned in `flake.lock`, and
the Linux product. CI publishes those libraries as prebuilt slices, so a
contributor never installs Nix to build the Apple or Android apps. With
Nix installed, `cargo xtask deps get <sdk> --nix` builds a slice locally,
which is how a C dependency change is tried, and `nix develop` enters the
same environment CI uses.

### Contributing & Supporting

Build setup: [Compilation Guide](docs/compilation.md).

Wawona is a massive undertaking to bring a native Wayland compositor to Apple platforms and Android, and **I cannot sustain this project alone**. Your support _whether through code, issues, ideas, or donations_ is essential to its progress and survival.

You can help by:

- Opening issues for bugs or feature requests
- Submitting pull requests for improvements
- Sharing ideas and suggestions
- Spreading the word to others
- Supporting ongoing development through donations if you find Wawona useful or believe in its goals

Thank you for being part of the journey!


**Donate here:**
Ko‑fi: https://ko-fi.com/aspauldingcode

Share Wawona with friends!

# Discord:
https://discord.gg/wHVSV52uw5

### License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

Third-party dependencies (Rust crates, native libs, Android) use MIT, Apache 2.0, BSD, MPL-2.0, LGPL, or GPL as applicable. For a full list and how to disclose them, see [Third-Party Licenses](docs/THIRD_PARTY_LICENSES.md). A NOTICE template is in [NOTICE.example](NOTICE.example).
