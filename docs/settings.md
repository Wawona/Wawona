# Wawona Settings Reference

> Settings for macOS, iOS family, Android, and Linux. Public subset for
> wawona.io: this file. Do not scrape App Review notes onto the site.

---

## Canonical Settings Architecture

- Canonical machine profile store key: `wawona.machineProfiles.v1` (JSON data payload).
- Canonical active machine key: `wawona.activeMachineId.v1`.
- Canonical global preferences namespace: `wawona.pref.*`.
- Machine resolution precedence is **machine overrides > global defaults > hardcoded defaults**.
- Effective runtime settings must be derived from `resolvedSettings(for:)` semantics.
- Diagnostics are persisted as typed entries with category + mode (`configLint` or `runtimeProbe`).

## UI surfaces (Apple / Android)

| Layer | UI | Entry points |
|-------|-----|--------------|
| **Global Wawona Settings** | ObjC + AppKit (macOS) / UIKit (iOS, iPadOS, tvOS, visionOS) / WatchKit + SwiftUI catalog (watchOS); Kotlin on Android | App menu **Settings…**, Settings tab (`ObjCSettingsHostView`), Machines window gear icon, watch gear → `WatchGlobalSettingsView` (same `GlobalSettingsCatalog` as WatchKit `WWNWatchSettings`). **macOS System Settings:** Wawona pane (Wawona icon; under Other on macOS 13+). Installed by `nix run .#install` and the GitHub DMG `WawonaAgent.pkg`. **iOS Settings:** Settings → Apps → Wawona → Wawona Settings (`Settings.bundle`; toggles share `NSUserDefaults` with the app. Buttons such as Copy logs stay in-app.) |
| **Machine profiles + overrides** | SwiftUI (`MachineEditorView` via `MachineEditorValidation`, `MachineSettingsView`) | Add / swipe **Edit** = identity editor; **Machine Settings** = per-machine overrides |

Global Settings sections are declared in `WawonaUIContracts.GlobalSettingsCatalog`.
iOS includes **Apple Watch** (companion document transfer via WatchConnectivity;
send-side only. Not a watchOS Settings twin). Catalog sections include Display
(Enable HDR), Machines (shake / swipe / tvOS Menu), iCloud Sync (Apple; omit on
tvOS, iCloud Drive is unavailable), Local Shell (three buttons), Dependencies
(this product's linked packages only), plus the existing Input / Graphics /
Env Vars / Advanced / Waypipe / SSH / About pages. watchOS omits Desktop
(forbidden), Local Shell, and Apple Watch. SwiftUI
on watch is the in-process host (WatchKit present from `@main` is unreliable);
both hosts must render that catalog and the same `wawona.pref.*` keys.

### Settings row layout

A Settings row is two columns. Never put a paragraph in both.

- **Switch:** one-line title (truncate if needed) | On/Off. No helper copy in the row.
- **Multi-option (iOS family):** one-line title | current value and a
  disclosure chevron. Tap pushes a full list page (checkmark on the
  selected row). iPhone, iPad, Apple TV, and Vision Pro.
- **Multi-option (macOS):** one-line title | `NSPopUpButton` switcher in
  the trailing column. Native Cocoa menu. No chevron and no second page.
- **Info:** one-line title plus the current value. Short values sit on the
  trailing edge. Longer copy wraps in the row. Never a placeholder
  ellipsis. Tap opens a sheet with the full value and description.
- Short text values (1024, Set) may sit in the trailing column on one line.

---

| Setting | Key | Type | Default | Platforms | Description |
|---------|-----|------|---------|------------|-------------|
| **Enable HDR** | `colorOperations` / `ColorOperations` | Switch | On | All | Color profiles and HDR (EDR) present path |
| **Force Server-Side Decorations** | `forceServerSideDecorations` / `ForceServerSideDecorations` | Switch | Off | macOS only | When off, weston-family clients draw CSD. Other hosts always use SSD (no Settings row) |
| **Respect Safe Area** | `respectSafeArea` / `RespectSafeArea` | Switch | On | iPhone / iPad | Avoid notches, Dynamic Island, display cutouts |
| **Show macOS Cursor** | `RenderMacOSPointer` | Switch | Off | macOS only | Toggle visibility of the macOS system cursor |

Auto Scale (`AutoScale`) and DMABUF (`DmabufEnabled`) stay on internally. They have no Settings row. Nested Weston Backend (`NestedWestonBackend`) is not a Settings picker; Display Backend (`CompositorBackend`) is the launch path.

---

## Apple Watch (iOS send-side)

Companion documents for the paired Watch ([#151](https://github.com/Wawona/Wawona/issues/151)).
Transport is **WatchConnectivity** (`WCSession.transferFile`). Not SFTP on the
Watch; not iCloud Drive ubiquity on watchOS. AX id: `wwn.settings.appleWatch`.

| Setting | Key / control | Type | Platforms | Description |
|---------|---------------|------|-----------|-------------|
| **Companion Status** | (info) | Info | iOS | Paired / Watch app installed / reachable |
| **Last Transfer** | `wawona.pref.watchCompanionLast*` | Info | iOS | Last queued/failed send |
| **Send Document to Watch** | document picker → `transferFile` | Button | iOS | Queue a file (including `.wasm`) into Watch `Documents/Wawona/inbox` |

CloudKit catalog mirror is tracked as a follow-up ([#155](https://github.com/Wawona/Wawona/issues/155)).
watchOS WASM runtime remains size-gated off ([#156](https://github.com/Wawona/Wawona/issues/156) / [#143](https://github.com/Wawona/Wawona/issues/143)).

---

## Graphics

| Setting | Key | Type | Default | Platforms | Description |
|---------|-----|------|---------|------------|-------------|
| **Vulkan Driver** | `vulkanDriver` / `VulkanDriver` | Dropdown | KosmicKrisp on Apple Silicon + macOS 26+; else MoltenVK on Apple; `system` on Android | GPU targets | Android: None, System, or SwiftShader. No Turnip, no `/dev/kgsl`. Apple: None, MoltenVK, KosmicKrisp. watchOS GL/VK is blocked (no Metal). Watch present is SpriteKit. |
| **OpenGL Driver** | `openglDriver` / `OpenGLDriver` | Dropdown | `system` (Android), `angle` (macOS/iOS/tvOS GPU) | GPU targets | Android: None, ANGLE, System. Apple GPU targets: None, ANGLE. No MoltenGL. tvOS GPU defaults to ANGLE (Phase 1 leftover `none` migrates once). watchOS: None. |

---

## Input

| Setting | Key | Type | Default | Platforms | Description |
|---------|-----|------|---------|------------|-------------|
| **Touch Input Type** | `TouchInputType` / runtime `inputProfile` | Dropdown | Multi-Touch | iOS, iPadOS, visionOS, Android (global + per-machine); watchOS Multi-Touch only | Multi-Touch (`wl_touch`) or Touchpad (virtual pointer). watchOS is direct finger only. No virtual/trackpad cursor. Per-machine override lives in Machine Settings → Input only (not Add/Edit). Prefer Multi-Touch for Weston panel / terminals / nested clients. |
| **Show Virtual Cursor** | `RenderMacOSPointer` | Switch | Off | All except watchOS | Host overlay or real macOS pointer. **Non-compositor clients only.** Nested niri/weston and iland DRM compositors hide and grab the host pointer (including iOS Touchpad `_cursorLayer`) and draw `wl_pointer` themselves. The switch does not unhide that overlay. |
| **Nested Compositor Cursor** | `NestedCompositorCursor` | Dropdown | virtual | Leftover | Must not put a Wawona pointer on a compositor. Ignore for niri/weston. See `wawona-nested-compositor-cursor`. |
| **Touchpad Mode** | `touchpadMode` | Switch | Off | Android | Same as Touchpad on iOS |
| **Swap CMD with ALT** | `SwapCmdWithAlt` | Switch | On (macOS/iOS) | macOS, iOS | Swap Command and Alt keys |
| **Universal Clipboard** | `universalClipboard` / `UniversalClipboard` | Switch | On | All | Sync clipboard with host platform |

---

## Connection (macOS / iOS)

Networking only. Wayland socket / shell environment variables live under
**Environment Variables** (not duplicated here).

| Setting | Key | Type | Description |
|---------|-----|------|-------------|
| **TCP Port** | `TCPListenerPort` | Number | Port for TCP listener (default 6000) |

---

## Environment Variables

Windows-style environment variable manager ([#157](https://github.com/Wawona/Wawona/issues/157)). **Single Settings section** inventories every var Wawona injects, with Edit / New / per-row Reset / Reset Wawona-managed / Reset all. Per-machine overrides are under **Edit Machine → Environment Variables**. First-class Settings (Vulkan, Display Backend, SSH) stay; the table is the override surface.

| Setting | Key | Type | Platforms | Description |
|---------|-----|------|-----------|-------------|
| **Environment Variables** | `wawona.pref.environment.v1` (global); `runtimeOverrides.environment` (per-machine) | Table | All | Name / value / source / Reset. Actions: New, Edit, Unset, Reset this, Reset Wawona-managed, Reset all |
| **Display Backend (per-machine)** | `runtimeOverrides.compositorBackend` | Popup | All | `auto` \| `wayland` \| `drm`; inherits global `CompositorBackend` when unset |

Precedence: **machine overrides > global overrides > first-class setting mapping > catalog default**. Catalog: `contracts/environment-catalog.yaml`. Secrets (`SSHPASS`, `WAYPIPE_SSH_PASSWORD`) are never shown. Apple-mobile spawn strips `DYLD_*` / `LD_*` even if user extras set them.

a11y: `wwn.settings.environment.*`

Local issue doc: [`docs/issues/environment-variables-gui.md`](issues/environment-variables-gui.md).

---

## Machines (global Settings, not the Machines window)

AX id: `wwn.settings.machines`.

| Setting | Key | Type | Default | Platforms | Description |
|---------|-----|------|---------|------------|-------------|
| **Shake to Exit Machine** | `wawona.pref.shakeToCloseEnabled` | Switch | On | iOS, Android, watchOS, visionOS | Shake confirms closing the active machine session |
| **Menu / Shake to Exit Machine** | `wawona.pref.shakeToCloseEnabled` (same key) | Switch | On | tvOS | Menu/Back confirms session exit. Shake on the 1st-gen Siri Remote only (`GCMotion`). Play/Pause toggles keyboard. Clickpad moves the pointer |
| **Swipe Back to Exit Machine** | `wawona.pref.swipeBackToCloseEnabled` | Switch | On | iOS, Android, watchOS, visionOS | Edge swipe back asks before closing |
| **Session Thumbnails** | `MachineSessionThumbnailsEnabled` | Switch | On | All | Last session frame on machine cards |
| **Virtual Machine Engine** | (read-only) | Info | platform | macOS, iOS, Android, Linux | Selected by `wwn-vms`. Hidden on tvOS / watchOS / visionOS |
| **Virtual Machine VSock Port** | `MachineVMVsockPort` | Number | 1024 | macOS, iOS, Android, Linux | Guest waypipe vsock port |
| **Container Runtime** | (read-only) | Info | platform | macOS, iOS, Android, Linux | Selected by `wwn-containers`. Hidden on tvOS / watchOS / visionOS |
| **Container Image Store** | `MachineContainerImageStore` | Text | `~/.local/share/wawona/oci` | macOS, iOS, Android, Linux | OCI store for pulled images |

One Settings section. Session gestures and VM/container prefs share `wwn.settings.machines`. Not a second sidebar row.

---

## iCloud Sync (Apple)

AX id: `wwn.settings.icloudSync`. Omit on Android, Linux, and tvOS. Key:
`wawona.pref.localShellICloudSyncEnabled` (`WWNRootfsICloudSync`). Toggle on
macOS, iOS, iPadOS, visionOS. Apple [QA1935](https://developer.apple.com/library/archive/qa/qa1935/_index.html):
iCloud Drive is unavailable on tvOS and watchOS (`ubiquityIdentityToken` is
always nil). Wawona iCloud Sync is Drive ubiquity for shell HOME, not CloudKit
or iCloud KVS, so the section is omitted on tvOS rather than shown as
unsupported. watchOS may keep a status page that says Drive is unavailable.

---

## Local Shell

Three actions only: **Reset Shell Dotfiles**, **Reset System Tree**, **Import
File to Home**. Platform / HOME / template info rows and Finder help are not
Settings fields. Hidden on tvOS / watchOS when those capabilities are absent.

---

## Advanced

| Setting | Key | Type | Default | Platforms | Description |
|---------|-----|------|---------|------------|-------------|
| **Display Backend** | `CompositorBackend` | Popup | `auto` | All | Nested compositor backend: `auto`, `wayland`, or `drm`. Resolved by `WWNResolveCompositorBackend` onto `NIRI_BACKEND` / `weston --backend=`. Do not pin nested-only. |
| **Text Assist** | `enableTextAssist` | Switch | Off | iOS, Android | Host text assist / autocorrect via the compositor text-input path. iOS still reads this key. |
| **Dictation** | `enableDictation` | Switch | Off | Android | Android dictation toggle (paired with Text Assist). |
| **Nested Compositors** | `nestedCompositorsSupport` / `NestedCompositorsSupport` | Switch | On | All | Nested Weston and Niri. Both ship on every product target. |
| **Multiple Clients** | `multipleClients` / `MultipleClients` | Switch | On | All | Allow multiple Wayland clients simultaneously |
| **Log Level** | `wawona.pref.logLevel` | Popup | info | All | Minimum log severity for the in-app log ring |

---

## Waypipe

| Setting | Key | Type | Default | Description |
|---------|-----|------|---------|-------------|
| **Display Number** | `WaylandDisplayNumber` / `waypipeDisplay` | Number/Text | 0 | Display number (0 = wayland-0) |
| **Socket Path** | `waypipeSocket` | Text | (platform) | Unix socket path (Android: cache dir) |
| **Compression** | `WaypipeCompress` / `waypipeCompress` | Dropdown | lz4 | none, lz4, zstd |
| **Compression Level** | `WaypipeCompressLevel` / `waypipeCompressLevel` | Number | 7 | Zstd level (1-22) |
| **Threads** | `WaypipeThreads` / `waypipeThreads` | Number | 0 | 0 = auto |
| **Video Compression** | `WaypipeVideo` / `waypipeVideo` | Dropdown | none | none, h264, vp9, av1 |
| **Video Encoding** | `WaypipeVideoEncoding` / `waypipeVideoEncoding` | Dropdown | hw | hw, sw, hwenc, swenc |
| **Video Decoding** | `WaypipeVideoDecoding` / `waypipeVideoDecoding` | Dropdown | hw | hw, sw, hwdec, swdec |
| **Bits Per Frame** | `WaypipeVideoBpf` / `waypipeVideoBpf` | Number | (empty) | Target bit rate for video |
| **Use SSH Config** | `WaypipeUseSSHConfig` | Switch | On | Use SSH section for connection |
| **Remote Command** | `WaypipeRemoteCommand` / `waypipeRemoteCommand` | Text | (empty) | Command to run remotely (e.g. weston-terminal) |
| **Custom Script** | `waypipeCustomScript` | Multiline | (empty) | Full command line (overrides Remote Command) |
| **Debug Mode** | `WaypipeDebug` / `waypipeDebug` | Switch | Off | Verbose logging |
| **Disable GPU** | `WaypipeNoGpu` / `waypipeDisableGpu` | Switch | Off | Force software rendering |
| **One-shot** | `WaypipeOneshot` / `waypipeOneshot` | Switch | Off | Exit when client disconnects |
| **Unlink Socket** | `WaypipeUnlinkSocket` / `waypipeUnlinkOnExit` | Switch | Off (macOS/iOS), On (Android) | Remove socket on exit |
| **Login Shell** | `WaypipeLoginShell` / `waypipeLoginShell` | Switch | Off | Run in login shell on remote |
| **Title Prefix** | `WaypipeTitlePrefix` / `waypipeTitlePrefix` | Text | (empty) | Prefix for window titles (e.g. "Remote:") |
| **Security Context** | `WaypipeSecCtx` / `waypipeSecCtx` | Text | (empty) | SELinux context (Linux only) |

---

## SSH

| Setting | Key | Type | Default | Description |
|---------|-----|------|---------|-------------|
| **SSH Host** | `SSHHost` / `waypipeSSHHost` | Text | (empty) | Remote host IP or hostname |
| **SSH User** | `SSHUser` / `waypipeSSHUser` | Text | (empty) | SSH username |
| **SSH Port** | `SSHPort` / `waypipeSSHPort` | Text | 22 | SSH port (Test SSH + waypipe honor this) |
| **Auth Method** | `SSHAuthMethod` / `WaypipeSSHAuthMethod` / `sshAuthMethod` | Dropdown | password | Password or Public Key (namespaces stay synced) |
| **Password** | `SSHPassword` / `waypipeSSHPassword` | Password | (empty) | SSH password (when Auth = Password) |
| **Key Type** | `SSHKeyType` / `sshKeyType` | Dropdown | ed25519 | Algorithm for Generate Key (`ed25519` / `ecdsa` / `rsa`) |
| **Generate Key** | (action) | Button | - | Invokes platform `ssh-keygen`; writes Documents/ssh (Apple) or filesDir/ssh (Android); sets `SSHKeyPath` **and** `WaypipeSSHKeyPath`; dual-syncs Machine apply |
| **Import GPG SSH Key** | (action) | Button | - | Pair a GPG Authentication key exported as OpenSSH via `gpg --export-ssh-key` (or any OpenSSH/PEM private key). macOS may also use gpg-agent as `ssh-agent`. |
| **Key Path** | `SSHKeyPath` / `WaypipeSSHKeyPath` / `sshKeyPath` | Text | ~/.ssh/id_ed25519 (macOS) | Path to private key (dual-namespace sync) |
| **Key Passphrase** | `SSHKeyPassphrase` / `WaypipeSSHKeyPassphrase` / `sshKeyPassphrase` | Password | (empty) | Passphrase for encrypted key (used by Generate Key `-N` and auth) |
| **Enable SSH** | `waypipeSSHEnabled` | Switch | On | Use SSH transport for Waypipe |

**Hard requirement:** every Apple target (incl. watchOS/tvOS/visionOS) and Android can generate **ed25519 / ecdsa / rsa** from Settings GUI **and** from the in-app PTY (`ssh-keygen` via wwn-zsh → `ssh_keygen_main` / OpenSSH). Empty passphrase → OpenSSH `openssh-key-v1` (GPG-export compatible). Non-empty → encrypted private key (Apple: PKCS#8; Android/macOS OpenSSH: native). Public key auth syncs across Machines via `applyMachineToRuntimePrefs` (`SSH*` ↔ `WaypipeSSH*`).

Apple mobile terminal/Settings keygen uses **libssh2 CLI** (`libwwn-ssh-cli.a`). Android uses **OpenSSH portable** jniLibs. Never OpenSSH-inprocess on Apple mobile. GnuPG itself is not bundled on mobile. Pair with `gpg --export-ssh-key` on a host that has GPG.

---

## Desktop Replacement (macOS + Android planned; App Store iOS forbidden)

**Coming soon.** Never ship Desktop/LockScreen UI on App Store Apple-mobile
targets, and never mention jailbreak in those binaries. Canonical behavior:
[`iland-mode-a-b-desktop.md`](./iland-mode-a-b-desktop.md). Wawona Swinging Bridge is separate:
[`swinging-bridge.md`](./swinging-bridge.md).

### macOS (`NSUserDefaults`)

| Setting | Key | Type | Default | Description |
|---------|-----|------|---------|-------------|
| SIP status (info) | (runtime `WWNSipStatus`) | Info | - | Value is **Fully Disabled** only when `csrutil disable` took. Partial (`enable --without debug`) shows Partially Disabled and Mode B is refused |
| Enable Desktop Replacement | `DesktopReplacementEnabled` | Switch | Off | Mode B intent when SIP allows; refused/cleared if SIP blocks or Mode B dylib missing. Enable checks watchdog coverage, heals if stale, and installs sudoers NOPASSWD plus Path B. Does not take over the screen. **Replace now** disables IOWatchdog, then unloads watchdogd and WindowServer. Login and `--compositor-host` do not unload WindowServer. Restart keeps this switch on. |
| Desktop Machine | `DesktopReplacementMachineId` | Popup | - | Nested compositor native profiles only (weston, niri, custom compositor) |
| Enable Lockscreen Replacement | `LockscreenReplacementEnabled` | Switch | Off | Greeter / machine picker before Desktop |
| Lockscreen Machine | `LockscreenReplacementMachineId` | Popup | - | Native-port greeter machine |
| Wawona Swinging Bridge | `AnowaWEnabled` | Switch | Off | **Not** Desktop. See [`swinging-bridge.md`](./swinging-bridge.md) |

Mode B loads bundled `libwayland-mac.dylib` only from
`wawona-macos-desktop-host` builds. Store-safe `wawona-macos` stays Mode A.

### Android (`SharedPreferences`)

| Setting | Key | Description |
|---------|-----|-------------|
| Desktop enabled | `wawona.desktop.enabled` | Default Home App role (no root) |
| Desktop machine | `wawona.desktop.machineId` | Native-port profiles only |
| Lockscreen | `wawona.lockscreen.*` | Platform LockScreen APIs (no root) |
| App Bridge | `wawona.swingingBridge.enabled` | Wawona Swinging Bridge. Separate from Desktop/LockScreen |
| Wawona Swinging Bridge Mode B | `wawona.swingingBridge.powerMode` | Privileged paths outside Play requirements |

---

## Dependencies

AX id: `wwn.settings.dependencies`. Built from
[`dependencies/wawona/settings-deps.nix`](../dependencies/wawona/settings-deps.nix)
and shipped as `SettingsDependencies.json` for **this** product only. Never copy
another platform's list. Rule: [`agent-rules/wawona-settings-dependencies.md`](agent-rules/wawona-settings-dependencies.md).

---

## About (diagnostics)

| Control | Type | Platforms | Description |
|---------|------|-----------|-------------|
| Version / Platform / Install | Info | Apple Settings | CalVer, host OS + version + uname machine, install channel (TestFlight, Sideload, App Store, Simulator, macOS) |
| Copy Recent Logs | Button | Apple, Android, Linux | Copies a GitHub-ready report (version, host, install, active machine without secrets, last ~2000 log lines) |
| Copy Active Machine Logs | Button | Apple Settings | Same header plus only lines tagged with the active machine id |
| Report a Bug on GitHub | Button | Apple, Android, Linux, watchOS | Opens `Wawona/Wawona` issue form `bug.yml` with platform, install channel, version, host OS, and recent logs filled. Also copies the full report to the clipboard (except tvOS/watchOS) |
| Wawona.io | Link | All About hosts | Subtext is documentation and downloads. Button: Visit. Opens `https://wawona.io` |
| Author | Link | All About hosts | Subtext is Alex Spaulding. Button: Visit Portfolio. Opens `https://aspauldingcode.com`. There is no separate Portfolio row |
| GitHub | Link | All About hosts | Subtext `github.com/aspauldingcode`. Button: View Profile |
| X | Link | All About hosts | Subtext `@aspauldingcode`. Button: Follow. Icon is a 24px rounded square like the other About logos |
| LinkedIn | Link | All About hosts | Subtext `linkedin.com/in/aspauldingcode`. Button: Connect |
| Ko-fi | Link | All About hosts | Subtext Buy me a coffee. Button: Support |
| GitHub Sponsors | Link | All About hosts | Button: Sponsor |
| Source Code | Link | All About hosts | Subtext `github.com/Wawona/Wawona`. Button: View on GitHub |

Sideloaded iOS IPAs have no TestFlight crash pipeline. TestFlight testers should send **Beta Feedback** from the TestFlight app *and* paste copied logs on GitHub. Full steps: [`reporting-bugs.md`](reporting-bugs.md).

---

## About (diagnostics)

| Control | Type | Platforms | Description |
|---------|------|-----------|-------------|
| Version / Platform / Install | Info | Apple Settings | CalVer, host OS + version + uname machine, install channel (TestFlight, Sideload, App Store, Simulator, macOS) |
| Copy Recent Logs | Button | Apple Settings | Copies a GitHub-ready report (version, host, install, active machine without secrets, last ~2000 log lines) |
| Copy Active Machine Logs | Button | Apple Settings | Same header plus only lines tagged with the active machine id |
| Report a Bug on GitHub | Button | Apple Settings | Opens `Wawona/Wawona` issue form `bug.yml`. Paste the copied report into Copied diagnostics |

Sideloaded iOS IPAs have no TestFlight crash pipeline. TestFlight testers should send **Beta Feedback** from the TestFlight app *and* paste copied logs on GitHub. Full steps: [`reporting-bugs.md`](reporting-bugs.md).

---

## Platform-Specific Defaults

| Setting | macOS | iOS | tvOS | Android |
|---------|-------|-----|------|---------|
| Force SSD | Off (toggle) | Always SSD (no row) | Always SSD (no row) | Always SSD (no row) |
| Multiple Clients | On | On | On | On |
| Enable HDR | On | On | On | On |
| Vulkan Driver | KosmicKrisp (Apple Silicon + macOS 26+), else moltenvk | moltenvk | moltenvk (GPU bundle) | system |
| OpenGL Driver | angle | angle | angle (GPU bundle) | system |

---

## Storage

- **macOS / iOS**: `NSUserDefaults` (UserDefaults)
- **Android**: `SharedPreferences`

Keys use camelCase (e.g. `autoScale`, `waypipeSSHHost`). Some keys differ by platform (e.g. `ForceServerSideDecorations` vs `forceServerSideDecorations`).
