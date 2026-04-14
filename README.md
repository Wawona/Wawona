# Wawona

[![Nix CI (Linux/Android)](https://github.com/aspauldingcode/Wawona/actions/workflows/nix.yml/badge.svg?branch=main&event=push&job=build-linux)](https://github.com/aspauldingcode/Wawona/actions/workflows/nix.yml)
[![Nix CI (macOS/iOS)](https://github.com/aspauldingcode/Wawona/actions/workflows/nix.yml/badge.svg?branch=main&event=push&job=build-macos-x86_64)](https://github.com/aspauldingcode/Wawona/actions/workflows/nix.yml)

**Wawona** is a native Wayland Compositor for macOS, iOS, and Android.
<div align="center">
  <img src="gallery/wawona_nested_plasma.png" alt="Wawona - Wayland Compositor Preview 1" width="800"/>
  <details>
    <summary>More previews</summary>
    <img src="gallery/wawona_nested_xfce.png" alt="Wawona - Wayland Compositor Preview 2" width="800"/>
    <img src="gallery/wawona_nested_cosmic.png" alt="Wawona - Wayland Compositor Preview 3" width="800"/>
  </details>
</div>

> **Project Vision:** Read about long-term objectives in [Project Goals](docs/goals.md).

## FAQ

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

> For build targets and Nix pipeline details, see [Compilation Guide](docs/compilation.md) and [Nix Build System](docs/2026-nix-build-system.md).

### How do I run Weston or Waypipe?

- **Weston natively on macOS:** `nix run .#weston` (full compositor) or `nix run .#weston-terminal` (terminal client)
- **Waypipe (remote apps):** Configure SSH in Settings > Waypipe, set Remote Command (e.g. `nix run ~/Wawona#weston-terminal`), tap Run Waypipe

See [Usage Guide](docs/usage.md) and [Settings Reference](docs/settings.md).

### WearOS + Linux VM automation

- **WearOS build/test automation:** `nix run .#wawona-wearos`
  - Builds Android artifacts with Nix and validates Wear shell wiring.
  - If a WearOS emulator/device is connected over `adb`, it performs install/launch smoke checks.
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

The Apple integration is centralized in `dependencies/apple/` and is modeled after [`nix-xcodeenvtests`](https://github.com/svanderburg/nix-xcodeenvtests). This keeps iOS and macOS Xcode discovery, SDK checks, and simulator helpers in one place.

The Apple integration layer now does four distinct jobs:
1.  **Expose host Xcode into Nix** through a thin `xcodeenv`-style wrapper.
2.  **Build Rust/static dependencies** such as `libwawona.a` and the iOS support libraries with Nix.
3.  **Generate the Xcode project** with store-path references to those prebuilt artifacts.
4.  **Package or launch the app** through first-class flake outputs.

This keeps the wrapper minimal and lets the same flow work on local machines and on GitHub macOS runners.

##### Common iOS outputs

- `nix build .#wawona-ios-app-sim`
- `nix build .#wawona-ios-app-device`
- `nix build .#wawona-ios-ipa --impure`
- `nix build .#wawona-ios-xcarchive --impure`
- `nix run .#wawona-ios`
- `nix run .#wawona-ios-project`
- `nix run .#wawona-ios-provision`

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
