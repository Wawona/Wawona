# High-level architecture: Vulkan, OpenGL, Metal

## Graphics APIs

- **Vulkan**. Modern, low-level graphics and compute API from Khronos. Better multi-threading and lower driver overhead than OpenGL. Used by many games and compositors.
- **OpenGL / OpenGL ES**. Older, higher-level API; still used on mobile and legacy code. Android is moving toward Vulkan.
- **Metal**. Apple’s proprietary GPU API. **Required** on iOS/macOS; Apple does not ship native Vulkan.

## Translation and portability layers

On platforms without native Vulkan (iOS, macOS), **porting layers** implement Vulkan by translating to the native API (Metal):

| Layer | Description | Use for Wawona |
|-------|-------------|----------------|
| **MoltenVK** | Vulkan Portability implementation over Apple’s Metal. Khronos-supported, widely used in games and apps. | Primary choice for Vulkan-on-Apple today. |
| **KosmicKrisp** | Mesa-based Vulkan-on-Metal driver. Newer; aims for more complete Vulkan support on macOS. | Alternative or future option as it matures. |

References:

- [MoltenVK (GitHub)](https://github.com/KhronosGroup/MoltenVK)
- [KosmicKrisp (Mesa docs)](https://docs.mesa3d.org/drivers/kosmickrisp.html)

## How this fits Wawona

Wawona can use:

- **Vulkan** for the compositor’s own rendering (recommended where available).
- **EGL/OpenGL** as an alternative or fallback.

On macOS/iOS, the Vulkan path is implemented by building against **MoltenVK** (or later KosmicKrisp), so the same Vulkan code can run on Apple platforms without a separate Metal backend.
