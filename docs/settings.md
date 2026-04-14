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

---

## Display

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
| **Vulkan Driver** | `vulkanDriver` / `VulkanDriver` | Dropdown | `system` (Android), `moltenvk` (macOS/iOS) | All | Vulkan implementation. Android: None, SwiftShader, Turnip, System. macOS/iOS: None, MoltenVK, KosmicKrisp |
| **OpenGL Driver** | `openglDriver` / `OpenGLDriver` | Dropdown | `system` (Android), `angle` (macOS/iOS) | All | OpenGL/GLES implementation. Android: None, ANGLE, System. macOS: None, ANGLE, MoltenGL. iOS: None, ANGLE |
| **DmaBuf Support** | `dmabufEnabled` / `DmabufEnabled` | Switch | On | All | Zero-copy texture sharing between clients |

---

## Input

| Setting | Key | Type | Default | Platforms | Description |
|---------|-----|------|---------|------------|-------------|
| **Touch Input Type** | `TouchInputType` | Dropdown | Multi-Touch | iOS | Multi-Touch (direct) or Touchpad (1-finger=pointer, tap=click, 2-finger=scroll) |
| **Touchpad Mode** | `touchpadMode` | Switch | Off | Android | Same as Touchpad on iOS |
| **Swap CMD with ALT** | `SwapCmdWithAlt` | Switch | On (macOS/iOS) | macOS, iOS | Swap Command and Alt keys |
| **Universal Clipboard** | `universalClipboard` / `UniversalClipboard` | Switch | On | All | Sync clipboard with host platform |
| **Enable Text Assist** | `enableTextAssist` / `EnableTextAssist` | Switch | Off | All | Autocorrect, suggestions, smart punctuation, swipe-to-type |
| **Enable Dictation** | `enableDictation` / `EnableDictation` | Switch | Off | All | Voice dictation; spoken text sent to focused Wayland client |

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
| **Enable Launcher** | `enableLauncher` / `EnableLauncher` | Switch | Off | All | Start built-in Wayland Shell |
| **Enable Weston Simple SHM** | `westonSimpleSHMEnabled` / `WestonSimpleSHMEnabled` | Switch | Off | All | Start weston-simple-shm on launch |
| **Enable Native Weston** | `westonEnabled` / `WestonEnabled` | Switch | Off | All | Start full Weston compositor on launch |
| **Enable Weston Terminal** | `westonTerminalEnabled` / `WestonTerminalEnabled` | Switch | Off | All | Start weston-terminal on launch |

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
| **Auth Method** | `SSHAuthMethod` / `sshAuthMethod` | Dropdown | password | Password or Public Key |
| **Password** | `SSHPassword` / `waypipeSSHPassword` | Password | (empty) | SSH password (when Auth = Password) |
| **Key Path** | `SSHKeyPath` / `sshKeyPath` | Text | ~/.ssh/id_ed25519 (macOS) | Path to private key |
| **Key Passphrase** | `SSHKeyPassphrase` / `sshKeyPassphrase` | Password | (empty) | Passphrase for encrypted key |
| **Enable SSH** | `waypipeSSHEnabled` | Switch | On | Use SSH transport for Waypipe |

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
