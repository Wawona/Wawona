# Driver setup for Wawona Wayland compositor

This folder is a **practical, research-oriented guide** for setting up graphics drivers and APIs (Vulkan, OpenGL, Metal) when building or porting the **Wawona** Wayland compositor on **iOS, Android, and macOS**.

## Quick reference

| Platform | Native Vulkan? | Recommended approach |
|----------|----------------|------------------------|
| **Android** | Yes | Use Vulkan native drivers + NDK/SDK |
| **macOS**  | No  | MoltenVK or KosmicKrisp (Vulkan → Metal) |
| **iOS**    | No  | MoltenVK (Vulkan → Metal); KosmicKrisp in future |
| **Linux**  | Yes | Native Vulkan (Mesa or proprietary) |
| **Windows**| Yes | Native Vulkan from GPU vendor |

## Documentation index

1. **[Architecture overview](01-architecture.md)**. Vulkan, OpenGL, Metal, and translation layers (MoltenVK, KosmicKrisp).
2. **[Platform strategy](02-platforms.md)**. Per-platform driver strategy and links.
3. **[MoltenVK & KosmicKrisp](03-moltenvk-kosmickrisp.md)**. Setup and usage on Apple platforms.
4. **[Android Vulkan](04-android-vulkan.md)**. Implementing Vulkan on Android for Wawona.
5. **[Integration workflow](05-integration-workflow.md)**. Build setup, code snippets, and testing.
6. **[Resources & links](06-resources.md)**. Official docs, SDKs, tutorials, and the fetch script.

## Why this matters for Wawona

A Wayland compositor typically renders via **EGL/OpenGL** or **Vulkan**. On platforms without native Vulkan (macOS, iOS), you need a Vulkan backend that uses:

- **MoltenVK** or **KosmicKrisp** on macOS/iOS (Vulkan over Metal), or  
- **Native Vulkan** on Linux and Android.

Wawona’s driver setup should follow the integration steps in this guide so that rendering works consistently across all target platforms.

## Fetching external docs

To download HTML snapshots of the official documentation linked in this guide, run:

```bash
./scripts/fetch_driver_docs.sh
```

Files are saved under `docs/drivers-how-to/downloaded/`. See [Resources & links](06-resources.md) for details.
