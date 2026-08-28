# Graphics CI matrix. Mode A store vs Mode B privileged

Companion to epic [#122](https://github.com/Wawona/Wawona/issues/122) and
[`iland-graphics-progress.md`](../iland-graphics-progress.md). Bundle policy is
enforced by
[`.github/scripts/verify-iland-graphics-bundle.sh`](../../.github/scripts/verify-iland-graphics-bundle.sh)
from [`product-build.yml`](../../.github/workflows/product-build.yml).

## Bundle audit (every product-build)

| Artifact | Script platform | Mode B dylib / daemons | GPU drivers expected |
|----------|-----------------|------------------------|----------------------|
| iOS sim / device IPA shape | `ios` | **absent** (hard fail on Dobby / private frameworks / Mode B daemons) | ANGLE + MoltenVK (static markers) |
| iPadOS | `ipados` | absent | same |
| visionOS | `visionos` | absent | same |
| tvOS | `tvos` | absent | ANGLE + MoltenVK (`WWN_TVOS_GPU=1`; product-build exports this) |
| watchOS | `watchos` | absent | **CPU GLES/VK** when `WWN_WATCH_SWIFTSHADER_BUNDLED` (SwiftShader + ANGLE static; SpriteKit present; no Metal/MVK) |
| Android Play APK | `android` | **absent** (+ no Turnip/KGSL; requires ANGLE + SwiftShader `.so` + ICD JSON) | ANGLE + SwiftShader |
| macOS 3rd-party | `macos` | **absent** | MoltenVK + KosmicKrisp dylibs |
| macOS desktop-host | `macos-desktop` | **present** (`verify-iland-mode-b-bundle.sh --mode present`) | same + Mode B dylib |

## Runtime acceptance (Agent-Device / local)

| Capability | Mode A store proof | Mode B privileged proof |
|------------|--------------------|-------------------------|
| OpenGL / GLES | kmscube + opengl-cube / weston-simple-egl on macOS (PROPER); Apple-mobile + Android WIRED pending device runs | desktop-host engage path; never claimed on store artifacts |
| Vulkan | macOS MVK + KK (PROPER); iOS MVK WIRED; Android system WIRED / SwiftShader client ICD WIRED | same ICD under desktop-host |
| DRM open/resources | stock kmscube virtual card (macOS PROPER) | Dobby `open`/`ioctl` hooks on desktop-host |
| KMS flip/present | host `iland_drm_complete_page_flip` (macOS PROPER) | framebufferd ACK worker (WIRED; SIP fully disabled runtime owed) |

## Agent-Device usage

Prefer `agent-device` for UI proof on macOS / iOS sim (see
`wawona-agent-device` Cursor rule). Capture under
`Wawona/.agent-device/test-artifacts/`. A cell is PROPER only with a rendered
frame (or log evidence of presents) on the product-shaped binary, not on a
nix-shell one-off alone.

## Anti-patterns

- Promoting a store cell on the strength of desktop-host Mode B.
- Shipping `libwayland-mac.dylib` / Dobby / Mode B daemons in any App Store or
  Play artifact.
- Marking tvOS **GL/VK** cells anything but N/A / MISSING until
  those stacks have a public Metal floor on Watch (tvOS is bundled). Watch
  **present** is SpriteKit (Track A). Watch **software GL/VK** is CPU ICD +
  SHM readback when `WWN_WATCH_SWIFTSHADER=1`; matrix gate requires
  `WATCH: First frame` (or KMS `iland DRM present`) in console logs, not
  process-alive alone.
