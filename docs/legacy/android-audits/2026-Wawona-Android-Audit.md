> **Superseded.** Historical Android audit. Live facts: [`../../2026-SOURCE-OF-TRUTH.md`](../../2026-SOURCE-OF-TRUTH.md) and [`../../android/STATUS.md`](../../android/STATUS.md). Do not copy to wawona.io.

# Wawona Android Implementation Audit

**Date:** 2026-02-24  
**Goal:** Ensure Wawona Android has 1:1 usability with iOS/macOS Wawona, with full Wayland protocol support, all graphics drivers, and comprehensive input handling.

---

## Executive Summary

**Android Implementation Status: ~85% parity with iOS/macOS**

Wawona Android is **functionally complete** for core compositor features. The shared Rust backend ensures full Wayland protocol support. Gaps are primarily **platform-specific polish** (cursor rendering in touchpad mode, modifier accessory bar) and **configuration defaults** (multipleClients disabled). The visual flashing issue for nested waypipe clients can be mitigated by matching the clear color to the compositor background.

---

## 1. Platform Structure

| Aspect | Android | iOS | macOS |
|--------|---------|-----|-------|
| **Entry** | `MainActivity.onCreate` | `WWNAppDelegate` | `main()` |
| **Core init** | `WawonaNative.nativeInit()` | `WWNCompositorBridge.startWithSocketName:` | Same |
| **Surface** | `SurfaceView` + `nativeSetSurface` | `WWNCompositorView_ios` (UIView) | `WWNWindow` (NSWindow) |
| **FFI** | JNI → `WWNCore*` C API | Obj-C → same C API | Obj-C → same C API |

**Verdict:** ✅ All platforms use the same Rust core and C FFI. Structure is consistent.

---

## 2. Graphics / Rendering

| Feature | Android | iOS | macOS |
|---------|---------|-----|-------|
| **API** | Vulkan only | Metal (CALayer) | Metal + Cocoa fallback |
| **Swapchain** | `VK_PRESENT_MODE_FIFO_KHR` (vsync) | `CADisplayLink` | Metal/Cocoa |
| **Frame pacing** | `AChoreographer` | `CADisplayLink` | Metal present |
| **Buffer path** | SHM → Vulkan texture upload | IOSurface/CGImage → CALayer | IOSurface → Metal/Cocoa |
| **Nested compositors** | Vulkan quad renderer | Metal renderer | Metal + IOSurface zero-copy |
| **Cursor** | Rendered via `renderer_android_draw_cursor` | CALayer cursor | NSCursor / Metal |

**Gaps:**
- Android has no Metal/Cocoa fallback (Vulkan-only). Acceptable; Vulkan is standard on Android.
- Android uses `LOAD_OP_CLEAR` with black (0,0,0). Can cause visual flashing; should use CompositorBackground (0x0F1018).

**Verdict:** ✅ Core rendering complete. ⚠️ Clear color mismatch causes flashing.

---

## 3. Input Handling

| Input Type | Android | iOS | macOS |
|------------|---------|-----|-------|
| **Physical keyboard** | `onKeyDown/Up` → `android_keycode_to_linux` → `WWNCoreInjectKey` | HID usage → Linux keycode | NSEvent → Linux keycode |
| **Virtual keyboard** | `WawonaInputConnection.commitText` → `char_to_linux_keycode` + `WWNCoreInjectKey` | `insertText:` → same pattern | IME → text-input-v3 |
| **Keyboard focus** | `onFocusChanged` + auto-focus on window change (render loop) | First responder + window activation | Window focus |
| **Text-input-v3** | `nativeCommitText` / `nativePreeditText` / `nativeDeleteSurroundingText` | Full `UITextInput` | Full IME |
| **Touch (multi-touch)** | `nativeTouchDown/Up/Motion` → `wl_touch` | Same | N/A |
| **Touchpad mode** | Pointer simulation (1-finger=move, tap=click, 2-finger=scroll) | Same + **cursor rendering** | Mouse/trackpad |
| **Pointer axis** | `onGenericMotionEvent` + touchpad 2-finger | Two-finger drag | NSScrollWheel |
| **Modifiers** | Manual tracking (`g_modifiers_depressed`) | Same + **sticky modifier UI** | Same |

**Gaps:**
1. **Cursor in touchpad mode:** Android does not render the Wayland client cursor in touchpad mode. iOS draws it via `CALayer`. Android has `renderer_android_draw_cursor` and the render loop draws it when `scene->has_cursor`. So cursor *is* drawn. Need to verify touchpad mode triggers pointer enter so cursor position updates.
2. **Modifier accessory bar:** Android has no sticky modifier UI (Shift/Ctrl/Alt lock). iOS has a full accessory bar. Medium priority for power users.

**Verdict:** ✅ Core input complete. ⚠️ Modifier accessory bar missing.

---

## 4. Wayland Protocol Support

All platforms share the **same Rust core**, so protocol support is identical:

- **Core:** `wl_compositor`, `wl_surface`, `wl_seat`, `wl_output`, `wl_shm`, `wl_keyboard`, `wl_pointer`, `wl_touch`
- **XDG:** `xdg_shell`, `xdg_toplevel`, `xdg_popup`, `xdg_decoration`, `xdg_activation`, `xdg_output`
- **wlroots:** `zwlr_layer_shell_v1`, `zwlr_screencopy_manager_v1`, `zwlr_data_control_manager_v1`, `zwlr_foreign_toplevel_management_v1`, `zwlr_output_management_v1`
- **Text:** `text-input-v3`
- **Platform:** `zwp_linux_dmabuf_v1` (Android: Vulkan; iOS/macOS: IOSurface)

**Platform-specific:**
- **Gamma control** (`zwlr_gamma_control_manager_v1`): macOS only. Android typically doesn't expose this.
- **Screencopy:** All platforms implement; Android uses different capture path.

**Verdict:** ✅ Full protocol parity via shared core.

---

## 5. Settings and Configuration

| Setting | Android | iOS | macOS |
|---------|---------|-----|-------|
| `forceServerSideDecorations` | ✅ | ✅ | ✅ |
| `autoRetinaScaling` | ✅ | ✅ | ✅ |
| `renderingBackend` | Vulkan only (1) | Metal | Metal/Cocoa |
| `respectSafeArea` | ✅ | ✅ | ✅ |
| `renderMacOSPointer` | Hardcoded false | N/A | ✅ |
| `swapCmdAsCtrl` | Hardcoded false | N/A | ✅ |
| `universalClipboard` | ✅ | ✅ | ✅ |
| `colorSyncSupport` | ✅ | ✅ | ✅ |
| `nestedCompositorsSupport` | ✅ | ✅ | ✅ |
| `useMetal4ForNested` | Hardcoded false | ✅ | ✅ |
| `multipleClients` | **Disabled by default** | Enabled | Enabled |
| `waypipeRSSupport` | Always true | ✅ | ✅ |
| `enableTCPListener` | Hardcoded false | ✅ | ✅ |
| `touchpadMode` | ✅ | ✅ | N/A |
| `vulkanDriver` | Android: swiftshader/system (runtime-only; no direct KGSL) | N/A | N/A |

**Gaps:**
- `multipleClients` disabled by default on Android. Consider enabling for parity.
- `enableTCPListener` hardcoded false. May be intentional for mobile.

**Verdict:** ✅ Most settings present. ⚠️ `multipleClients` default differs.

---

## 6. Waypipe and Remote Clients

| Aspect | Android | iOS | macOS |
|--------|---------|-----|-------|
| **Integration** | `android_jni.c`. Thread + `waypipe_main` | `WWNWaypipeRunner.m` (shared UI) | Same |
| **SSH** | Dropbear (patched streamlocal) | libssh2 | System ssh / libssh2 |
| **Socket** | `./waypipe` in XDG_RUNTIME_DIR | Same pattern | Same |
| **Remote socket** | `/tmp/waypipe` | Configurable | Configurable |
| **No-GPU** | Forced for Android (no DRM) | Configurable | Configurable |

**Verdict:** ✅ Android has full waypipe support with Dropbear. iOS/macOS use `WWNWaypipeRunner` (shared).

---

## 7. Safe Area and Display

| Feature | Android | iOS | macOS |
|---------|---------|-----|-------|
| **Safe area** | `WindowInsets` → `nativeUpdateSafeArea` | `UIScreen` safe area | NSWindow safe area |
| **Output size** | Swapchain extent → `WWNCoreSetOutputSize` | View bounds | Window size |
| **Rotation** | `surfaceChanged` (debounced) | `windowScene:didUpdateCoordinateSpace` | Window resize |

**Verdict:** ✅ All platforms handle safe area and output sizing.

---

## 8. Checklist for 100% Parity

### Must Have (Blocking 1:1 Usability)
- [x] Full Wayland protocol support (shared core)
- [x] Keyboard input (physical + virtual)
- [x] Touch and touchpad mode
- [x] Waypipe + SSH integration
- [x] Safe area and output sizing
- [x] Cursor rendering (in render loop when `scene->has_cursor`)
- [x] **Reduce visual flashing**. Match clear color to CompositorBackground (implemented)

### Should Have
- [ ] Modifier accessory bar (sticky Shift/Ctrl/Alt)
- [ ] Enable `multipleClients` by default (or document rationale)
- [ ] Verify cursor updates correctly in touchpad mode

### Nice to Have
- [ ] TCP listener option (if desired for debugging)
- [ ] Gamma control (if Android display APIs support it)

---

## 9. Visual Flashing Fix

**Cause:** The Vulkan render pass uses `LOAD_OP_CLEAR` with black `(0,0,0,1)`. The compositor background is `0xFF0F1018` (dark blue-gray). When frames are presented with no content (e.g. before waypipe sends a frame) or during transitions, the black clear is visible and causes flashing.

**Fix:** Use the CompositorBackground color for the clear value:
- `0x0F1018` → `(15/255, 16/255, 24/255)` ≈ `(0.059f, 0.063f, 0.094f, 1.0f)`

---

## 10. File Reference

| Component | Android | iOS | macOS |
|-----------|---------|-----|-------|
| Main activity | `MainActivity.kt` | `WWNSceneDelegate.m` | `main.m` |
| Surface/view | `WawonaSurfaceView.kt` | `WWNCompositorView_ios.m` | `WWNCompositorBridge.m` |
| Native bridge | `android_jni.c` | `WWNCompositorBridge.m` | Same |
| Input | `input_android.c/h`, `WawonaInputConnection.kt` | `WWNCompositorView_ios.m` | `input_handler.m` |
| Renderer | `renderer_android.c` | `renderer_ios.m` | `renderer_macos.m` |
| Waypipe | `android_jni.c` (inline) | `WWNWaypipeRunner.m` | Same |
| Settings | `WawonaSettings.kt` | `WWNPreferencesManager` | `WWNSettings.m` |
