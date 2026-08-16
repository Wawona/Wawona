# Resources and links

Curated links for driver setup, Vulkan, MoltenVK, KosmicKrisp, and Android. Use these when implementing or debugging Wawona’s graphics backends.

## Vulkan API and cross-platform

- [Vulkan Guide. Platforms (Khronos)](https://docs.vulkan.org/guide/latest/platforms.html)
- [Vulkan Portability Initiative / Porting layers](https://www.vulkan.org/porting)

## Vulkan SDK and tools

- [LunarG Vulkan SDK](https://www.lunarg.com/vulkan-sdk/)
- [LunarG Vulkan SDK 1.4.341.0 release](https://www.lunarg.com/lunarg-releases-vulkan-sdk-1-4-341-0/)
- [Vulkan SDK Getting Started (macOS)](https://vulkan.lunarg.com/doc/view/1.4.341.1/mac/getting_started.html)

## MoltenVK (Vulkan over Metal)

- [MoltenVK. GitHub](https://github.com/KhronosGroup/MoltenVK). Source, build, user guide, demos

## KosmicKrisp (Mesa Vulkan-on-Metal)

- [KosmicKrisp. Mesa 3D docs](https://docs.mesa3d.org/drivers/kosmickrisp.html)
- [LunarG SDK 1.4.335.0 (KosmicKrisp notes)](https://www.lunarg.com/lunarg-releases-vulkan-sdk-1-4-335-0/)

## Android Vulkan

- [Implement Vulkan. AOSP](https://source.android.com/docs/core/graphics/implement-vulkan)
- [Vulkan for game graphics. Android Developers](https://developer.android.com/games/develop/vulkan/overview)

## Examples and frameworks

- **Vulkan tutorials**. Khronos Vulkan Tutorial (search “Vulkan Tutorial Khronos”); also samples in the Vulkan SDK.
- **MoltenVK**. Demos in the MoltenVK GitHub repo (Xcode projects for macOS/iOS).
- **Cross-platform**. SDL2 (Vulkan surfaces), GLFW (Vulkan loader), bgfx / gfx-rs (multi-backend).

---

## Fetching these docs locally

The script **`scripts/fetch_driver_docs.sh`** downloads HTML snapshots of the URLs above so you can read them offline.

**Usage:**

```bash
./scripts/fetch_driver_docs.sh
```

**Output:** Files are saved under `docs/drivers-how-to/downloaded/` with sanitized names. GitHub and some sites may return HTML landing pages rather than raw content; for full docs, use the links above in a browser.

**Note:** The script is for convenience only; always refer to the official sites for the latest and most accurate documentation.
