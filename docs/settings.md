# Wawona Settings Reference

> All settings available in Wawona for macOS, iOS, and Android.

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
| **Global Wawona Settings** | ObjC + AppKit (macOS) / UIKit (iOS, iPadOS, tvOS, visionOS) / **WatchKit** (watchOS); Kotlin on Android | App menu **Settings…**, Settings tab (`ObjCSettingsHostView`), Machines window gear icon, watch gear → `WWNWatchSettings` storyboard |
| **Machine profiles + overrides** | SwiftUI (`WWNMachineEditorView`, `MachineSettingsView`, watch `WatchMachineOverridesSheet`) | Machines window editor; swipe **Edit** on watch opens SwiftUI override sheet only |

SwiftUI does **not** implement global settings on macOS, iOS, or watchOS. On watchOS, global prefs use WatchKit interface controllers backed by `WWNWatchSettingsBridge` (`wawona.pref.*`). Per-machine overrides remain SwiftUI (`MachineSettingsView` / `WatchMachineOverridesSheet`).

---

| Setting | Key | Type | Default | Platforms | Description |
|---------|-----|------|---------|------------|-------------|
| **Force Server-Side Decorations** | `forceServerSideDecorations` / `ForceServerSideDecorations` | Switch | On (Android), Off (macOS/iOS) | All | Compositor-drawn window borders; clients do not draw their own titlebar |
| **Auto Scale** | `autoScale` / `AutoScale` / `autoRetinaScaling` | Switch | On | All | Match platform UI scaling (Retina, Android density) |
| **Respect Safe Area** | `respectSafeArea` / `RespectSafeArea` | Switch | On | All | Avoid notches, Dynamic Island, display cutouts |
| **Show macOS Cursor** | `RenderMacOSPointer` | Switch | Off | macOS only | Toggle visibility of the macOS system cursor |

---

## Graphics

| Setting | Key | Type | Default | Platforms | Description |
|---------|-----|------|---------|------------|-------------|
| **Vulkan Driver** | `vulkanDriver` / `VulkanDriver` | Dropdown | `system` (Android), `moltenvk` (macOS/iOS) | All | Vulkan implementation. Android runtime-only policy: None, System, or SwiftShader for offscreen iland clients; host ANativeWindow WSI remains on the system loader. macOS/iOS: None, MoltenVK; macOS also offers KosmicKrisp |
| **OpenGL Driver** | `openglDriver` / `OpenGLDriver` | Dropdown | `system` (Android), `angle` (macOS/iOS) | All | OpenGL/GLES implementation. Android: None, ANGLE, System. Apple GPU targets: None, ANGLE |
| **DmaBuf Support** | `dmabufEnabled` / `DmabufEnabled` | Switch | On | All | Zero-copy texture sharing between clients |

---

## Input

| Setting | Key | Type | Default | Platforms | Description |
|---------|-----|------|---------|------------|-------------|
| **Touch Input Type** | `TouchInputType` | Dropdown | Multi-Touch | iOS | Multi-Touch (direct) or Touchpad (1-finger=pointer, tap=click, 2-finger=scroll) |
| **Touchpad Mode** | `touchpadMode` | Switch | Off | Android | Same as Touchpad on iOS |
| **Swap CMD with ALT** | `SwapCmdWithAlt` | Switch | On (macOS/iOS) | macOS, iOS | Swap Command and Alt keys |
| **Universal Clipboard** | `universalClipboard` / `UniversalClipboard` | Switch | On | All | Sync clipboard with host platform |

---

## Connection (macOS / iOS)

| Setting | Key | Type | Description |
|---------|-----|------|-------------|
| **XDG_RUNTIME_DIR** | (read-only) | Info | Runtime directory for Wayland socket |
| **WAYLAND_DISPLAY** | `WaylandDisplay` | Info | Socket name (e.g. wayland-0) |
| **Socket Path** | (read-only) | Info | Full path to Wayland socket |
| **Shell Setup** | (read-only) | Info | Copy-paste `export` commands for terminal |
| **TCP Port** | `TCPListenerPort` | Number | Port for TCP listener (default 6000) |

---

## Advanced

| Setting | Key | Type | Default | Platforms | Description |
|---------|-----|------|---------|------------|-------------|
| **Color Operations** | `colorOperations` / `ColorOperations` | Switch | On (Android), Off (macOS/iOS) | All | Color profiles, HDR requests |
| **Nested Compositors** | `nestedCompositorsSupport` / `NestedCompositorsSupport` | Switch | On | All | Support nested Wayland compositors |
| **Multiple Clients** | `multipleClients` / `MultipleClients` | Switch | On (macOS), Off (iOS/Android) | All | Allow multiple Wayland clients simultaneously |
| **Shake to Exit Machine** | `wawona.pref.shakeToCloseEnabled` | Switch | On | iOS, Android, watchOS | When enabled, shake shows a confirmation before closing the active machine session |
| **Long-press Menu to Exit Machine** | `wawona.pref.shakeToCloseEnabled` (same key) | Switch | On | tvOS | Siri Remote has no shake API; hold Menu/Back (~1s) confirms session exit. Short Menu sends Escape to the Wayland client |
| **Swipe Back to Exit Machine** | `wawona.pref.swipeBackToCloseEnabled` | Switch | On | iOS, Android, watchOS | When enabled, edge swipe back asks before closing the active session (not used on tvOS) |
| **Per-machine shake override** | `runtimeOverrides.shakeToCloseEnabled` | Optional bool | inherit global | All | Machine editor / override sheet |
| **Per-machine swipe-back override** | `runtimeOverrides.swipeBackToCloseEnabled` | Optional bool | inherit global | All | Machine editor / override sheet |

---

## Waypipe

| Setting | Key | Type | Default | Description |
|---------|-----|------|---------|-------------|
| **Display Number** | `WaylandDisplayNumber` / `waypipeDisplay` | Number/Text | 0 | Display number (0 = wayland-0) |
| **Socket Path** | `waypipeSocket` | Text | (platform) | Unix socket path (Android: cache dir) |
| **Compression** | `WaypipeCompress` / `waypipeCompress` | Dropdown | lz4 | none, lz4, zstd |
| **Compression Level** | `WaypipeCompressLevel` / `waypipeCompressLevel` | Number | 7 | Zstd level (1–22) |
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
| **Generate Key** | (action) | Button | — | Invokes platform `ssh-keygen`; writes Documents/ssh (Apple) or filesDir/ssh (Android); sets `SSHKeyPath` **and** `WaypipeSSHKeyPath`; dual-syncs Machine apply |
| **Import GPG SSH Key** | (action) | Button | — | Pair a GPG Authentication key exported as OpenSSH via `gpg --export-ssh-key` (or any OpenSSH/PEM private key). macOS may also use gpg-agent as `ssh-agent`. |
| **Key Path** | `SSHKeyPath` / `WaypipeSSHKeyPath` / `sshKeyPath` | Text | ~/.ssh/id_ed25519 (macOS) | Path to private key (dual-namespace sync) |
| **Key Passphrase** | `SSHKeyPassphrase` / `WaypipeSSHKeyPassphrase` / `sshKeyPassphrase` | Password | (empty) | Passphrase for encrypted key (used by Generate Key `-N` and auth) |
| **Enable SSH** | `waypipeSSHEnabled` | Switch | On | Use SSH transport for Waypipe |

**Hard requirement:** every Apple target (incl. watchOS/tvOS/visionOS) and Android can generate **ed25519 / ecdsa / rsa** from Settings GUI **and** from the in-app PTY (`ssh-keygen` via wwn-zsh → `ssh_keygen_main` / OpenSSH). Empty passphrase → OpenSSH `openssh-key-v1` (GPG-export compatible). Non-empty → encrypted private key (Apple: PKCS#8; Android/macOS OpenSSH: native). Public key auth syncs across Machines via `applyMachineToRuntimePrefs` (`SSH*` ↔ `WaypipeSSH*`).

Apple mobile terminal/Settings keygen uses **libssh2 CLI** (`libwwn-ssh-cli.a`). Android uses **OpenSSH portable** jniLibs. Never OpenSSH-inprocess on Apple mobile. GnuPG itself is not bundled on mobile — pair with `gpg --export-ssh-key` on a host that has GPG.

---

## Desktop Replacement (macOS + Android only)

Never shown on iOS / iPadOS / tvOS / watchOS / visionOS. Canonical behavior:
[`iland-mode-a-b-desktop.md`](./iland-mode-a-b-desktop.md).

### macOS (`NSUserDefaults`)

| Setting | Key | Type | Default | Description |
|---------|-----|------|---------|-------------|
| SIP status (info) | (runtime `WWNSipStatus`) | Info | — | `csrutil status` classify; Mode B needs Disabled or PartiallyDisabled |
| Enable Desktop Replacement | `DesktopReplacementEnabled` | Switch | Off | Mode B when SIP allows; refused/cleared if SIP blocks or Mode B dylib missing |
| Desktop Machine | `DesktopReplacementMachineId` | Popup | — | Nested Weston native machine only |
| App Bridge (anowaW) | `AnowaWEnabled` | Switch | Off | ScreenCaptureKit + Accessibility into nested Weston |
| Enable Lockscreen Replacement | `LockscreenReplacementEnabled` | Switch | Off | Greeter before Desktop |
| Lockscreen Machine | `LockscreenReplacementMachineId` | Popup | — | gtkgreet / gtklock / similar |

Mode B loads bundled `libwayland-mac.dylib` only from
`wawona-macos-desktop-host` builds. Store-safe `wawona-macos` stays Mode A.

### Android (`SharedPreferences`)

| Setting | Key | Description |
|---------|-----|-------------|
| Desktop enabled | `wawona.desktop.enabled` | HOME / launcher role |
| Desktop machine | `wawona.desktop.machineId` | Nested Weston native only |
| App Bridge | `wawona.anowaW.enabled` | Mirror apps into nested desktop |
| Power mode | `wawona.anowaW.powerMode` | Shizuku/root vs rootless baseline (no SIP) |
| Lockscreen | `wawona.lockscreen.*` | Greeter machine before desktop |

---

## Platform-Specific Defaults

| Setting | macOS | iOS | Android |
|---------|-------|-----|---------|
| Force SSD | Off | Off | On |
| Multiple Clients | On | Off | Off |
| Vulkan Driver | moltenvk | moltenvk | system |
| OpenGL Driver | angle | angle | system |

---

## Storage

- **macOS / iOS**: `NSUserDefaults` (UserDefaults)
- **Android**: `SharedPreferences`

Keys use camelCase (e.g. `autoScale`, `waypipeSSHHost`). Some keys differ by platform (e.g. `ForceServerSideDecorations` vs `forceServerSideDecorations`).
