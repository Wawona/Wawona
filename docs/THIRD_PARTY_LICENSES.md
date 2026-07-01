# Third-Party Licenses (Wawona)

Wawona is licensed under the **MIT License**. This document lists third-party dependencies and their licenses so you can disclose them properly (e.g. in an About screen, NOTICE file, or distribution docs).

**Compatibility summary:** All dependencies listed below are compatible with using Wawona as an MIT project. For some (Apache 2.0, MPL 2.0, BSD, etc.) you **must** include their license text and/or copyright notices when you distribute Wawona (source or binary). GPL/LGPL components (sshpass, FFmpeg if built with GPL) have special disclosure and linking requirements.

---

## 1. Rust crates (Cargo)

Direct and transitive dependencies are in `Cargo.toml` and `Cargo.lock`. The Rust ecosystem is overwhelmingly **MIT** and/or **Apache-2.0**; both are permissive and compatible with MIT.

### Direct dependencies (from Cargo.toml)

| Crate | Typical license | Notes |
|-------|-----------------|--------|
| thiserror | MIT OR Apache-2.0 | |
| anyhow | MIT OR Apache-2.0 | |
| tracing, tracing-subscriber | MIT | |
| bitflags | MIT OR Apache-2.0 | |
| chrono | MIT OR Apache-2.0 | |
| libc | MIT OR Apache-2.0 | |
| ssh2 | MIT OR Apache-2.0 | Wraps libssh2 (BSD-3-Clause) |
| ash | MIT OR Apache-2.0 | Vulkan bindings |
| libloading | MIT OR Apache-2.0 | |
| getrandom | MIT OR Apache-2.0 | |
| nix | MIT | |
| memoffset | MIT OR Apache-2.0 | |
| clap | MIT OR Apache-2.0 | |
| uniffi | **MPL-2.0** | See [UniFFI / MPL-2.0](#uniffi-mpl-20) below |
| wayland-server, wayland-client, wayland-backend | MIT | wayland-rs (Smithay) |
| wayland-protocols*, wayland-wf-shell | MIT | |
| wayland-scanner | MIT | |
| xkbcommon (Rust bindings) | MIT | FFI to libxkbcommon |
| tempfile | MIT OR Apache-2.0 | |
| waypipe (path, optional) | MIT | Waypipe project |

### UniFFI (MPL-2.0)

**UniFFI** (Mozilla) is used for Rust ↔ Swift/Kotlin bindings and is licensed under **Mozilla Public License 2.0 (MPL-2.0)**. You may use it in an MIT project:

- **Compatible:** Yes. MPL-2.0 is file-level copyleft: only *modified* MPL files must remain under MPL; your own code stays MIT.
- **You must:** Include the MPL-2.0 license text and preserve copyright notices for UniFFI. You do not need to re-license Wawona under MPL.

### Full Rust dependency list (licenses)

To generate an up-to-date list of every crate and its license (including transitive deps), run from the repo root when Cargo is available (e.g. `nix develop`):

```bash
cargo install cargo-license
cargo license --json > docs/cargo-licenses.json
cargo license --tsv  # human-readable table
```

Many crates use dual **MIT OR Apache-2.0**; you can satisfy both by including the text of both licenses and the crate’s copyright notices.

---

## 2. Native / C libraries (Nix builds)

These are built via upstream `wwn-toolchain` / `wwn-*` flake inputs (`dependencies/toolchains`, `dependencies/libs`) and linked into Wawona or bundled (e.g. waypipe, foot).

| Component | License | Compatible with MIT? | What you must do |
|-----------|---------|----------------------|-------------------|
| **libwayland** | MIT | Yes | Include MIT notice & license text |
| **waypipe** | MIT | Yes | Include MIT notice & license text |
| **pixman** | MIT | Yes | Include MIT notice & license text |
| **xkbcommon** (libxkbcommon) | MIT | Yes | Include MIT notice & license text |
| **expat** | MIT | Yes | Include MIT notice & license text |
| **libffi** | MIT | Yes | Include MIT notice & license text |
| **libxml2** | MIT | Yes | Include MIT notice & license text |
| **zlib** | zlib License | Yes (permissive) | Include zlib license & notice |
| **zstd** | BSD-3-Clause or GPL-2.0 | Yes if BSD only | Use BSD build; include BSD notice |
| **lz4** (lib/) | BSD-2-Clause | Yes | Include BSD-2-Clause notice |
| **epoll-shim** | MIT | Yes | Include MIT notice & license text |
| **OpenSSL** (3.x) | Apache-2.0 | Yes | Include Apache-2.0 & NOTICE if any |
| **libssh2** | BSD-3-Clause | Yes | Include BSD-3-Clause notice |
| **mbedtls** | Apache-2.0 | Yes | Include Apache-2.0 & NOTICE if any |
| **OpenSSH** | BSD (SSH-OpenSSH) | Yes | Include BSD-style notice |
| **sshpass** | **GPL-2.0-or-later** | See [sshpass / GPL](#sshpass-gpl) | Disclose; see section below |
| **FFmpeg** | LGPL-2.1+ (and optionally GPL) | Yes (LGPL) | See [FFmpeg](#ffmpeg) below |
| **KosmicKrisp** (Mesa) | MIT | Yes | Include MIT notice & license text |
| **SPIRV-Tools** | Apache-2.0 | Yes | Include Apache-2.0 & NOTICE if any |
| **SPIRV-LLVM-Translator** | Apache-2.0 / LLVM | Yes | Include license & notices |
| **SwiftShader** (Android) | Apache-2.0 | Yes | Include Apache-2.0 & NOTICE if any |
| **freetype** | FTL (FreeType License) | Yes (permissive) | Include FTL text |
| **fontconfig** | MIT-style (custom) | Yes | Include fontconfig license text |
| **fcft** | MIT | Yes | Include MIT notice & license text |
| **tllist** | MIT | Yes | Include MIT notice & license text |
| **utf8proc** | MIT | Yes | Include MIT notice & license text |
| **foot** (terminal) | MIT | Yes | Include MIT notice & license text |

### sshpass (GPL)

**sshpass** is **GPL-2.0-or-later**. It is bundled as a separate executable (e.g. on macOS) to automate SSH password for waypipe.

- **Compatible with MIT project:** GPL applies to sshpass itself, not to the rest of Wawona, *provided* Wawona and sshpass are separate programs (e.g. you exec sshpass as a subprocess, not link it into the same binary). Distributing both in the same app is fine; you must comply with GPL for sshpass.
- **You must:** (1) Disclose that sshpass is used and is under GPL-2.0-or-later; (2) provide the GPL-2.0 license text and source (or offer) for sshpass; (3) preserve sshpass copyright notices. Your own Wawona code remains MIT.

### FFmpeg

**FFmpeg** is typically **LGPL-2.1+**. Some builds enable GPL components; your Nix build should use an LGPL-only configuration if you want to avoid GPL.

- **LGPL:** You may dynamically link; provide license text and attribution. No need to open-source Wawona.
- **You must:** Include LGPL-2.1 license text and FFmpeg copyright/attribution. If your build uses GPL parts, you must comply with GPL for those.

---

## 3. Vulkan / GPU (optional or system)

| Component | License | Compatible with MIT? | What you must do |
|-----------|---------|----------------------|-------------------|
| **MoltenVK** | Apache-2.0 | Yes | Include Apache-2.0 & NOTICE; preserve copyrights. No need to re-license Wawona. |
| **KosmicKrisp** (Mesa) | MIT | Yes | Include MIT notice & license text |
| **SwiftShader** (Android) | Apache-2.0 | Yes | Include Apache-2.0 & NOTICE |

*On Apple platforms you must also comply with Apple’s Developer Program License and App Store guidelines; that is separate from open-source licensing.*

---

## 4. Android (Gradle / JVM)

From `build.gradle.kts`:

| Component | License | Compatible with MIT? | What you must do |
|-----------|---------|----------------------|-------------------|
| Android Gradle Plugin | Apache-2.0 | Yes | Include Apache-2.0 & notices |
| Kotlin, Kotlin Compose | Apache-2.0 | Yes | Include Apache-2.0 & notices |
| AndroidX (core, lifecycle, activity, appcompat, fragment) | Apache-2.0 | Yes | Include Apache-2.0 & notices |
| Compose BOM, UI, Material3, Material Icons | Apache-2.0 | Yes | Include Apache-2.0 & notices |

All are Apache-2.0; compatible with MIT. Include the Apache-2.0 license and any NOTICE files when distributing.

---

## 5. Build / tooling (Nix, generators)

| Component | License | Notes |
|-----------|---------|--------|
| nixpkgs | MIT | |
| rust-overlay | MIT | |
| crate2nix | LGPL-3.0 | Build tool only; no runtime in Wawona |
| HIAHKernel (input) | (check repo) | |
| Xcodegen, Gradle generators | (check each) | |

These generally don’t ship inside Wawona binaries; if you redistribute Nix expressions or scripts that include them, follow their license terms.

---

## 6. Checklist for distribution

When you distribute Wawona (source or binary):

1. **Keep Wawona’s MIT LICENSE** in the repo and in source distributions.
2. **Add a NOTICE or THIRD_PARTY file** that:
   - Lists the main libraries above and their licenses.
   - Includes or links to the full license texts (MIT, Apache-2.0, BSD-2/3, zlib, FTL, MPL-2.0, GPL-2.0 for sshpass, LGPL-2.1 for FFmpeg as applicable).
3. **Apache-2.0 components:** Include the Apache-2.0 license text and any NOTICE file they provide (e.g. MoltenVK, SwiftShader, mbedtls, AndroidX).
4. **MPL-2.0 (UniFFI):** Include MPL-2.0 text and UniFFI copyright notices.
5. **GPL (sshpass):** Include GPL-2.0 text, sshpass copyright, and offer or provide source for sshpass.
6. **LGPL (FFmpeg):** Include LGPL-2.1 text and FFmpeg attribution; if you link dynamically, that suffices.

You do **not** need to change Wawona’s project license from MIT; these obligations are attribution and disclosure for the third-party code.

---

## 7. Regenerating this list

- **Rust:** Run `cargo license --tsv` or `cargo license --json` (after `cargo install cargo-license`) to get the current crate list and licenses.
- **Nix libs:** The set of libs is defined in `wwn-toolchain` (`dependencies/toolchains/default.nix`, `dependencies/libs/*`) and wired into Wawona via `dependencies/wawona/default.nix` + flake inputs; when you add or remove a lib upstream, update this doc and the NOTICE/attribution accordingly.

If you add a new dependency (Rust or native), check its license and add it here with the same “Compatible?” and “What you must do” pattern.
