# Android — Engineering Status (2026-06)

Wawona on Android is a **native Jetpack Compose host** with a full JNI → Rust Wayland
compositor path, Vulkan rendering, and OpenSSH/waypipe SSH — not a WebView wrapper.

## Architecture

```
MainActivity (ComponentActivity, edge-to-edge)
  → WawonaTheme (MaterialExpressiveTheme + MotionScheme.expressive)
  → MachineWelcomeScreen / compositor SurfaceView
  → WawonaNative (JNI) → libwawona.a
       → renderer_android.c (Vulkan)
       → waypipe_main + libssh_bin.so (SSH sessions)
```

| Layer | Implementation |
|-------|----------------|
| UI | Kotlin Compose under `android/app/...` (parallel to SwiftUI on Apple) |
| Theme | Material 3 **Expressive** (`MaterialExpressiveTheme`, dynamic color on API 31+) |
| Compositor | Shared Rust core (Smithay), same protocol surface as macOS/iOS |
| Graphics | Vulkan swapchain (no Cocoa/Metal) |
| Remote | waypipe in-process + bundled OpenSSH portable (`fork`/`exec` `--ssh-bin`) |
| Input | Touch, touchpad mode, physical keyboard, text-input-v3, modifier accessory bar |

## Material 3 Expressive

| Feature | Status |
|---------|--------|
| `MaterialExpressiveTheme` | **Yes** — `WawonaTheme.kt` |
| `MotionScheme.expressive` | **Yes** — spring FAB / speed-dial |
| Expressive color schemes (API 36+) | **Yes** — fallback to static Wawona palette |
| Material You / dynamic color (API 31+) | **Yes** — when enabled |
| System light/dark | **Yes** — no longer forced dark |
| Expressive speed-dial FAB (API 36+) | **Yes** — Machines home + waypipe stop in session |
| XML shell `Theme.Material3.DayNight` | **Yes** — `res/values/themes.xml` |
| `material3.adaptive` (tablet split) | Not yet — phones/tablets use single-activity |

Apple uses **Liquid Glass (OS 26)**; Android uses **M3 Expressive (API 36+)** per `AGENTS.md`.

## Flake / build outputs

| Output | Purpose |
|--------|---------|
| `.#wawona-android` | Release/debug APK via Nix + Gradle |
| `.#wawona-android-backend` | `libwawona.a` for NDK |
| `.#weston-android` | Weston clients (optional link) |
| `.#weston-compositor-android` | Nested Weston compositor archive |
| `.#zsh-android` / `.#foot-android` / `.#fastfetch-android` / `.#neovim-android` | Bundled shell/tools |
| `.#iland-android` | iland userland (DRM path; optional) |
| `.#gradlegen` | Android Studio project with Nix backend |

After rebuilding Nix Android deps (weston, toolchain, etc.), run `nix run .#gradlegen` before building in Android Studio so native paths under `.nix-deps/` stay current.

Studio fallback: `WAWONA_STUDIO_FALLBACK=1` in CMake → stub renderer/core for IDE sync only.

## Parity vs Apple (high level)

| Capability | Android | Apple mobile |
|------------|---------|--------------|
| Wayland compositor core | Full | Full |
| weston-simple-shm | Real archive (not smoke stub) | Full |
| Nested Weston compositor | `weston-compositor-android` wired | Full |
| Local zsh + weston-terminal | zsh + assets + PTY spawn | In-process only |
| foot / fastfetch / neovim | jniLibs `.so` launchers | In-process / linked |
| waypipe SSH | OpenSSH `--ssh-bin` + `-i` | libssh2 in-process CLI + streamlocal |
| iland DRM nested compositor | Buildable; optional toggle pending | Full |
| Settings | Compose bottom sheet | SwiftUI navigation |
| Modifier accessory bar | M3-themed | iOS keyboard bar |

See `docs/2026-Wawona-Android-Audit.md` for compositor-depth parity.

## Manual smoke

1. Install Nix-built APK or `./gradlew :Wawona:assembleDebug` with Nix backend env.
2. Welcome → Machines grid (expressive FAB on API 36+).
3. Connect native machine → compositor fills display; keyboard accessory bar when IME open.
4. SSH machine → waypipe session; expressive **Stop Waypipe** FAB when running (API 36+).
5. Toggle system dark/light — theme follows (dynamic color on supported devices).

## Key paths

- `android/app/src/main/java/com/aspauldingcode/wawona/` — Compose UI
- `android/app/src/main/java/com/aspauldingcode/wawona/WawonaTheme.kt` — M3 Expressive theme
- `src/platform/android/android_jni.c` — JNI bridge
- `dependencies/wawona/android.nix` — APK pipeline
