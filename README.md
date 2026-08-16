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

1. Use a macOS machine with Xcode installed.
2. Install Nix.
3. Configure your environment (see below).
4. Build with the Nix flake.

### Environment Configuration

This project uses a simple `.envrc` file to manage your Apple Development Team ID.

1.  **Create or edit `.envrc`**:
    ```bash
    echo 'export TEAM_ID="your_apple_team_id_here"' > .envrc
    ```
    
    Replace `your_apple_team_id_here` with your actual Apple Development Team ID.

2.  **The environment is automatically loaded** when you use `nix develop` - no additional tools required!

> For build targets and Nix pipeline details, see [Compilation Guide](docs/compilation.md) and [Nix Build System](docs/2026-nix-build-system.md). Cross-compiled libraries and toolchains live in upstream [`wwn-toolchain`](https://github.com/Wawona/wwn-toolchain) and sibling `wwn-*` repos; Wawona's flake wires them in as inputs.

### How do I install Wawona from my macOS flake?

Use Wawona as a flake input, add its overlay so `pkgs.wawona` behaves like a normal nixpkgs package, and run Wawona's installer during activation. The installer step is important: `pkgs.wawona` puts the app wrapper in your profile, while the installer performs the same extra setup as `nix run .#install`, including the compositor and menubar LaunchAgents.

Example `flake.nix` with `nix-darwin`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    wawona.url = "github:Wawona/Wawona/development";
    wawona.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ nix-darwin, wawona, ... }: {
    darwinConfigurations.my-mac = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [
        ({ pkgs, ... }: {
          nixpkgs.overlays = [ wawona.overlays.default ];

          environment.systemPackages = [
            pkgs.wawona
          ];

          system.activationScripts.postActivation.text = ''
            ${wawona.packages.${pkgs.stdenv.hostPlatform.system}.install}/bin/install
          '';
        })
      ];
    };
  };
}
```

After applying your flake, Wawona is available as `pkgs.wawona`, and the activation hook writes and loads the Wawona LaunchAgents for the current macOS user. To remove those LaunchAgents later, run `nix run github:Wawona/Wawona/development#wawona-uninstall`.

### How do I run Weston or Waypipe?

- **Weston natively on macOS:** `nix run .#weston` (full compositor) or `nix run .#weston-terminal` (terminal client)
- **Waypipe (remote apps):** Configure SSH in Settings > Waypipe, set Remote Command (e.g. `nix run ~/Wawona#weston-terminal`), tap Run Waypipe

See [Usage Guide](docs/usage.md) and [Settings Reference](docs/settings.md).

### Linux VM automation

- **Linux KDE Plasma VM automation:** `nix run .#wawona-linux-vm`
  - Launches a NixOS VM (Plasma 6 Wayland) in QEMU for Linux UI testing.
  - Uses `kvm` on Linux when available; on macOS uses `hvf` and falls back to `tcg` if unavailable.

### "I don't have nix"

[hm. Fresh out of luck, I guess! `¯\_(ツ)_/¯`](https://www.youtube.com/watch?v=dQw4w9WgXcQ)

### Why Nix?

I use Nix to maintain a clean repository free of vendored dependency source code while ensuring hermetic, reproducible builds across all platforms. Nix allows us to define precise build environments for iOS, macOS, and Android without polluting your system.

#### Reproducibility & Usability

- **Hermetic Builds**: Every dependency, from the Rust toolchain to system libraries like `libwayland` or `ffmpeg`, is pinned to exact versions in `flake.lock`. This guarantees that if it builds on CI, it will build on your machine.
- **Zero-Config Environments**: Running `nix develop` (or using `direnv`) automatically enters a shell with all required compilers, headers, and auxiliary tools (like `xcodegen` or `android-sdk`) ready to go.
- **Composable Modules**: The `flake.nix` exports clean, reusable packages and development shells. You can easily integrate Wawona into other NixOS configurations or use its individual modules as building blocks for your own Wayland projects.

> _B`*`tch, I worked hard to make nix your ONLY dependency, use it!_

#### Xcode And iOS Builds

Cross-compiling for iOS still depends on Apple's proprietary SDKs and toolchains, so Wawona now follows the same high-level pattern as Nixpkgs `xcodeenv`: expose the host Xcode installation as an impure Nix package, build the Rust and native dependencies with Nix, then let `xcodebuild` package the app.

The Apple integration is centralized in [`wwn-toolchain`](https://github.com/Wawona/wwn-toolchain) (`dependencies/apple/`, `dependencies/toolchains/ios-xcodeenv.nix`) and is modeled after [`nix-xcodeenvtests`](https://github.com/svanderburg/nix-xcodeenvtests). Wawona consumes it as a flake input; this keeps iOS and macOS Xcode discovery, SDK checks, and simulator helpers in one upstream place.

The Apple integration layer now does four distinct jobs:
1.  **Expose host Xcode into Nix** through a thin `xcodeenv`-style wrapper.
2.  **Build Rust/static dependencies** such as `libwawona.a` and the iOS support libraries with Nix.
3.  **Generate the Xcode project** with store-path references to those prebuilt artifacts.
4.  **Package or launch the app** through first-class flake outputs.

This keeps the wrapper minimal and lets the same flow work on local machines and on GitHub macOS runners.

##### Common iOS outputs

- `nix build .#wawona-ios-app-sim`
- `nix build .#wawona-ios-app-device`
- `nix build .#weston-compositor-ios`. Nested Weston (Wayland/Pixman)
- `nix build .#weston-compositor-ios-drm`. Nested Weston DRM+GL archive (CI)
- `nix build .#wawona-ios-ipa --impure`
- `nix build .#wawona-ios-xcarchive --impure`
- `nix run .#wawona-ios`
- `nix run .#wawona-ios-project`
- `nix run .#wawona-ios-provision`

**Nested Weston on iOS** presents in-process via Settings → Compositor clients. Two backends are available:

| Setting | Backend | Presentation |
|---------|---------|--------------|
| Wayland (Pixman). Default | `--backend=wayland --use-pixman` | xdg_toplevel in Wawona window |
| iland DRM (GL) | `--backend=drm` | Metal overlay (`WWNIlandPresenter`) |

Production `weston.ini`, bundled `terminal.png`, and Adwaita cursors ship in the app bundle. Startup target: panel visible within ~2s on the Pixman path.

##### Requirements

1.  **Install Xcode**.
2.  **Select the Xcode you want to use** with `xcode-select`, unless the default selected Xcode is already correct. CI selects the highest `Xcode*.app` version and exports `XCODE_APP` before running Nix builds.
3.  **For local release signing**, export `TEAM_ID` and build with `--impure` so the automatic-signing path can see it.

Example:
```bash
export TEAM_ID="YOURTEAMID"
nix build .#wawona-ios-ipa --impure
```

### Contributing & Supporting

For fast Xcode iteration after a warm Nix store, see [Compilation Guide. Xcode Iteration](docs/compilation.md#xcode-iteration).

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
