# Android Vulkan

Implementing Vulkan for Wawona on Android: NDK, loader, and platform integration.

## Official resources

- **[Implement Vulkan | Android Open Source Project](https://source.android.com/docs/core/graphics/implement-vulkan)**. How to implement and integrate Vulkan in the Android platform and NDK.
- **[Vulkan for game graphics | Android Developers](https://developer.android.com/games/develop/vulkan/overview)**. Game-oriented Vulkan usage on Android.

## Integration outline

1. **NDK and headers**. Use the Vulkan headers and libraries provided by the Android NDK for your target ABI.
2. **Native activity / binder**. Drive Vulkan from native C/C++ (e.g. Android Native App Glue or your own activity/binder glue).
3. **Vulkan loader**. Use the system Vulkan loader; load `libvulkan.so` and get instance/device procedures as usual.
4. **Surface creation**. Create `VkSurfaceKHR` from the Android window (e.g. `ANativeWindow`) using `VK_KHR_android_surface`.
5. **Build**. Link against Vulkan in your NDK build (e.g. `-lvulkan` and correct include paths).

## Wawona on Android

For Wawona’s Android port:

- Implement the compositor’s Vulkan backend using the NDK Vulkan API.
- Follow AOSP’s “Implement Vulkan” doc for correct integration with the platform and any device-specific behavior.
- Reuse the same Vulkan rendering logic where possible; only the instance/surface creation and build glue are Android-specific.
