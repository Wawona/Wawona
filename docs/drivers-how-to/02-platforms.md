# Platform strategy

Summary of how to approach graphics drivers and Vulkan for Wawona on each platform.

## Summary table

| Platform   | Native Vulkan? | Strategy for Wawona |
|-----------|----------------|----------------------|
| **Android** | Yes | Use Vulkan native drivers + Android NDK/SDK. |
| **macOS**  | No  | Use **MoltenVK** or **KosmicKrisp** (Vulkan → Metal). |
| **iOS**    | No  | Use **MoltenVK** (Vulkan → Metal); SwiftShader is Simulator/CI-only. |
| **Windows**| Yes | Use native Vulkan drivers from GPU vendor. |
| **Linux**  | Yes | Use native Vulkan (Mesa or proprietary drivers). |

## Android

- Vulkan is the preferred modern API.
- Use NDK Vulkan headers and the platform’s Vulkan loader.
- See [Android Vulkan](04-android-vulkan.md) for implementation details and AOSP links.

## macOS and iOS

- No native Vulkan; use Metal or a Vulkan-over-Metal layer.
- **MoltenVK**: the on-device iOS/iPadOS/visionOS Vulkan provider.
- **SwiftShader**: CPU fallback for Apple GPU-target Simulators and CI only;
  never ship it in an Apple-mobile device bundle.
- **KosmicKrisp**: experimental macOS-only provider in Wawona today.
- Request **VK_KHR_portability_enumeration** when using MoltenVK (see [Integration workflow](05-integration-workflow.md)).

## Linux

- Use system Vulkan (Mesa radv/amdvlk, Intel ANV, or proprietary NVIDIA).
- EGL/OpenGL also available; compositors often support both Vulkan and GL.

## Windows

- Use vendor Vulkan drivers (e.g. NVIDIA, AMD, Intel).
- Vulkan SDK and loader from LunarG or Khronos.
