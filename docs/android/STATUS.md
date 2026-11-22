# Android. Engineering Status (2026-11 Exact cutover)

Wawona on Android ships through the **Exact Android host** (`cargo xtask build
android` / `archive android`). Product Compose under root `android/app` is
deleted. JNI → Rust Wayland compositor, Vulkan, and OpenSSH/waypipe remain.

## Architecture

```
Exact Android host (Canvas / Compose package)
  → JNI / UniFFI → libwawona
       → renderer_android.c (Vulkan)
       → waypipe_main + libssh_bin.so (SSH sessions)
```

| Layer | Implementation |
|-------|----------------|
| UI | Exact Contract chrome (product). Legacy Compose quarantined / removed from ship path |
| Compositor | Shared Rust core (Smithay), same protocol surface as Apple |
| Graphics | Vulkan swapchain |
| Remote | waypipe in-process + bundled OpenSSH portable |
| Input | Touch, touchpad mode, physical keyboard, text-input-v3 |

## Material 3 Expressive

Exact Android host follows Material 3 Expressive on API 36+. Theme ownership
lives with Exact / host packaging, not a root Gradle `WawonaTheme.kt`.

Apple uses **Liquid Glass (OS 26+)**; Android uses **M3 Expressive (API 36+)**.

## Build

| Command | Purpose |
|---------|---------|
| `cargo xtask deps get android` | Stages `.deps/android` |
| `cargo xtask backend android` | Builds `libwawona` for NDK |
| `cargo xtask build android` | Exact APK |
| `cargo xtask archive android` | Exact AAB for Play / Fastlane |

Exact owns Gradle under `exact/host/android`. NDK pin comes from that host
(or `ANDROID_NDK_VERSION` / `.#wwnSdkConfigPath`).

## Parity vs Apple (high level)

| Capability | Android | Apple mobile |
|------------|---------|--------------|
| Wayland compositor core | Full | Full |
| Product chrome | Exact | Exact |
| Present | Exact / JNI surface | Exact `wayland-present` |
| waypipe SSH | OpenSSH `--ssh-bin` | libssh2 in-process |
| Settings | Exact in-app | Exact in-app |

## Manual smoke

1. `cargo xtask build android` (or archive AAB).
2. Install APK. Machines → Start → Present.
3. Before tapping Wayland clients: Touchpad Mode **Off**.
4. SSH machine → waypipe session.

## Key paths

- Exact `apps/wawona` + `exact/host/android`
- `src/platform/android/android_jni.c`
- `dependencies/wawona/android-deps.nix`
