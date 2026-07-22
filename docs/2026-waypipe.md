# Waypipe Integration

> Waypipe enables remote Wayland application display over SSH. This document covers all platforms: macOS, iOS, and Android.

---

## Platform Overview

| Platform | Transport | Buffer Path | Status |
|----------|-----------|-------------|--------|
| **macOS** | OpenSSH process spawn | IOSurface → Metal | Working |
| **iOS** | libssh2 in-process | IOSurface → Metal | Built, integrated |
| **Android** | OpenSSH portable (fork/exec `--ssh-bin`) | SHM → Vulkan | Working |

---

## Quick Start: Remote Apps

### 1. Prepare the Mac

```bash
bash scripts/prepare_mac_remote.sh
```

Ensure Remote Login (SSH) is enabled, Python 3 is installed, and Waypipe is in your PATH.

### 2. Configure the App (iOS/Android)

1. Open **Wawona**
2. Go to **Settings > Waypipe**
3. **SSH Host**: Your Mac's IP address
4. **SSH User**: Your Mac username
5. **SSH Password**: Your Mac login password
6. **Remote Command**: `nix run ~/Wawona#weston-terminal`
7. Tap **Start Waypipe**

---

## macOS: VideoToolbox (Future)

After dmabuf support for macOS waypipe and `zwp_linux_dmabuf_v1`:

- Add **VideoToolbox** for H.264/H.265 decode → `CVPixelBuffer` → Metal texture
- Optional: software fallback from FFmpeg
- Remove GBM code from macOS Waypipe
- Map `video` feature to VideoToolbox decoding

---

## iOS Architecture

### Build

Waypipe is built as a static library for `aarch64-apple-ios` (and simulator):

```bash
nix build .#waypipe-ios
```

Produces `libwaypipe.a` with libssh2, lz4, zstd, dmabuf. Waypipe symbols are linked into `libwawona.a` via `extern crate waypipe` in `src/lib.rs`.

### Dependency Matrix

| Library | Purpose | Nix path (upstream repo) | iOS Status |
|---------|---------|--------------------------|------------|
| zstd | Compression | `wwn-toolchain/dependencies/libs/zstd/` | Cross-compiled |
| lz4 | Compression | `wwn-toolchain/dependencies/libs/lz4/` | Cross-compiled |
| libssh2 | SSH tunnels (replaces openssh) | `wwn-toolchain/dependencies/libs/libssh2/` | Cross-compiled |
| mbedtls | TLS for libssh2 | `wwn-toolchain/dependencies/libs/mbedtls/` | Cross-compiled |
| libwayland | Wayland client protocol | `wwn-toolchain/dependencies/libs/libwayland/` | Cross-compiled |
| libffi | Required by libwayland | `wwn-toolchain/dependencies/libs/libffi/` | Cross-compiled |
| xkbcommon | Keyboard handling | `wwn-toolchain/dependencies/libs/xkbcommon/` | Cross-compiled |
| pixman | Pixel manipulation | `wwn-toolchain/dependencies/libs/pixman/` | Cross-compiled |

### Feature Selection

| Feature | Enabled | Reason |
|---------|---------|--------|
| lz4 | Yes | Compression for Wayland protocol data |
| zstd | Yes | Compression for Wayland protocol data |
| dmabuf | Yes | GPU buffer sharing via Vulkan/ash |
| video | Yes | Static FFmpeg integration |
| gbmfallback | No | GBM not available on iOS |
| with_libssh2 | Yes | In-process SSH (no process spawn) |

### iOS Source Patches

Waypipe was written for Linux. Patches in `wwn-waypipe/dependencies/libs/waypipe/`:

- **Socket flags**: Replace `SOCK_CLOEXEC`/`SOCK_NONBLOCK` with `fcntl()` (iOS lacks them)
- **unlinkat → unlink**: iOS lacks `unlinkat()`
- **memfd / F_ADD_SEALS**: Stub or skip (iOS lacks memfd_create)
- **User::from_uid**: Hardcoded user info (no /etc/passwd in sandbox)
- **isatty()**: Use `.unwrap_or(false)`
- **Entry point**: `waypipe_main(argc, argv)` C-callable for FFI
- **wrap-gbm**: Stub (GBM not on iOS)
- **wrap-ffmpeg**: Static linkage for App Store

---

## iOS Transport: streamlocal-forward

The iOS waypipe build uses **libssh2** (patched for `streamlocal-forward@openssh.com`) and the **ssh2 crate**. No process spawning; all in-process.

### Data Flow

```
iOS App                        SSH                          Remote
─────────────────────────────────────────────────────────────────────
1. connect_ssh2()
   ├── TCP connect + handshake + auth
   ├── streamlocal-forward@openssh.com ──────► sshd creates
   │   (path=/tmp/wp-XXX.sock)                 /tmp/wp-XXX.sock
   │
   ├── exec channel: ──────────────────────► sh -c '[env setup]
   │   waypipe --socket /tmp/wp-XXX.sock        waypipe --socket
   │   server -- <app>                          /tmp/wp-XXX.sock
   │                                            server -- <app>'
   │
   │                                         waypipe connects to
   │                                         /tmp/wp-XXX.sock
   │
   │   forwarded-streamlocal@openssh.com ◄── sshd tunnels connection
   ├── accept forwarded channel                back through SSH
   │
   └── bridge thread: pumps data between
       forwarded channel ↔ UnixStream::pair()
```

**Remote requirements:** Stock waypipe + OpenSSH ≥ 6.7. No socat, nc, python3, or patched waypipe.

### Key Files

- `wwn-toolchain/dependencies/libs/libssh2/patch-streamlocal.sh` — adds streamlocal support to libssh2
- `wwn-waypipe/dependencies/libs/waypipe/patch-waypipe-source.sh` — creates `transport_ssh2.rs`
- `wwn-waypipe/dependencies/libs/waypipe/ios.nix` — iOS waypipe build

### libssh2 Streamlocal Patch

Adds:

- `libssh2_channel_forward_listen_streamlocal(session, socket_path, queue_maxsize)`
- `forwarded-streamlocal@openssh.com` channel dispatch
- Cancel support via `cancel-streamlocal-forward@openssh.com`

### Troubleshooting

| Issue | Fix |
|-------|-----|
| "streamlocal-forward@openssh.com failed" | Check `AllowStreamLocalForwarding` in sshd_config (default: yes) |
| "Timed out waiting for forwarded-streamlocal channel" | Verify waypipe is installed and in PATH on remote |
| "missing Wayland socket" | Start a Wayland compositor on the remote first |

---

## Android Implementation

- **OpenSSH portable** client bundled as `libssh_bin.so` / `libssh_keygen_bin.so` / `libscp_bin.so` (wwn-ssh; replaces Dropbear)
- SSH binaries (`libssh_bin.so`, `libsshpass_bin.so`) in `jniLibs/arm64-v8a/`
- `extractNativeLibs=true` in AndroidManifest.xml
- `resolve_ssh_binary_paths()` uses `dladdr()` to find native lib dir
- Waypipe Rust backend exposes `waypipe_main()` for JNI
- SSH bridge thread: `fork()` → `exec(dbclient)` with `SSHPASS` env

**Key difference from iOS:** Android uses fork/exec OpenSSH (`--ssh-bin`); Apple mobile uses libssh2 in-process (CLI + streamlocal).

---

## Current Status (2026-02)

- **macOS**: OpenSSH spawn, IOSurface zero-copy
- **iOS**: `nix build .#waypipe-ios` succeeds; libssh2 streamlocal transport; static FFmpeg/video
- **Android**: OpenSSH `--ssh-bin` + waypipe_main from JNI; working
