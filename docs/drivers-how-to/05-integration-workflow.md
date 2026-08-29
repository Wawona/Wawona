# Integration workflow

General steps to integrate Vulkan (and optional OpenGL) into Wawona across platforms, including Apple and Android.

## macOS / iOS

1. **Install Vulkan SDK** that includes MoltenVK (and optionally KosmicKrisp) for your OS.
2. **Build setup**. Configure CMake or Xcode to link the Vulkan loader and MoltenVK (or KosmicKrisp) for Apple targets.
3. **Instance creation**. Enable the portability extension when using MoltenVK:

   ```c
   VkApplicationInfo appInfo = { ... };
   VkInstanceCreateInfo createInfo = { ... };
   // Enable VK_KHR_portability_enumeration for MoltenVK
   createInfo.flags |= VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
   vkCreateInstance(&createInfo, NULL, &instance);
   ```

4. **Surfaces and swapchain**. Create window surfaces (e.g. from CAMetalLayer or equivalent), then create swapchain and command buffers as in any Vulkan app.
5. **Testing**. Check shader translation, unsupported extensions, and resize/fullscreen behavior.

## Android

- Use the **Android NDK** Vulkan headers and link against the platform’s Vulkan loader.
- Create surfaces from `ANativeWindow` via `VK_KHR_android_surface`.
- See [Android Vulkan](04-android-vulkan.md) for AOSP and developer docs.

## Linux / Windows

- Use system or SDK Vulkan loader and drivers; no portability bit needed for standard drivers.
- Optional: support both Vulkan and EGL/OpenGL backends and choose at runtime or build time.

## Cross-platform tips

- **Single code path**. Use one Vulkan render path; only instance/surface creation and build config differ per platform.
- **Extensions**. Query and enable only the extensions available on the current platform (e.g. portability on Apple, Android surface on Android).
- **Validation**. Use Vulkan validation layers from the SDK during development; disable or strip in release builds.
