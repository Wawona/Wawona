# MoltenVK and KosmicKrisp (Apple platforms)

Setup and usage of Vulkan-over-Metal for Wawona on macOS and iOS.

## MoltenVK

- **What it is:** Vulkan Portability implementation that translates Vulkan to Apple’s Metal.
- **Platforms used by Wawona:** macOS, iOS, iPadOS, visionOS. Wawona
  intentionally excludes Vulkan from tvOS/watchOS.
- **Source and docs:** [MoltenVK on GitHub](https://github.com/KhronosGroup/MoltenVK) (runtime, build instructions, user guide).

### Using MoltenVK in Wawona

1. Install **Vulkan SDK** (includes MoltenVK) from [LunarG](https://www.lunarg.com/vulkan-sdk/) or use the SDK that ships MoltenVK for your target OS.
2. In your build (CMake/Xcode), link the Vulkan loader and ensure MoltenVK is used as the implementation on Apple platforms.
3. In code, enable **VK_KHR_portability_enumeration** when creating the VkInstance (required for MoltenVK). See [Integration workflow](05-integration-workflow.md).
4. Create instance, surfaces, swapchain, and command buffers as usual; MoltenVK handles translation to Metal.

### Demos and samples

The MoltenVK repo includes a **Demos** folder with Xcode projects showing Vulkan on macOS/iOS — useful for reference when integrating Wawona.

---

## KosmicKrisp

- **What it is:** Mesa-based Vulkan driver that implements Vulkan on top of Metal (alternative to MoltenVK).
- **Status:** Upstream Mesa supports macOS on Apple Silicon (Metal 4). Its
  current driver documentation says iOS is not supported yet, though the
  implementation was designed with A14+ iOS GPUs in mind.
- **Docs:** [KosmicKrisp — Mesa 3D](https://docs.mesa3d.org/drivers/kosmickrisp.html) (build, dependencies, limitations).
- **LunarG:** [Vulkan SDK 1.4.335.0](https://www.lunarg.com/lunarg-releases-vulkan-sdk-1-4-335-0/) and related posts mention KosmicKrisp in the SDK context.

### When to use which

- **MoltenVK:** Default for production Vulkan-on-Apple today; widely used and well supported.
- **KosmicKrisp:** Consider for experiments or when you need Mesa-specific behavior; follow Mesa docs for build and compatibility.
