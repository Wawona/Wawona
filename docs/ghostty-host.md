# Ghostty host

L3′ repo `github.com/Wawona/Ghostty`. Flake input name `wwn-ghostty`.

One terminal grid for the local shell, SSH, and the Relay guest console, on
macOS, iOS, iPadOS, tvOS, watchOS, visionOS, Android, and Linux. Bytes come
from `wawona-pty` or Relay `relay_copy_log`.

Zig 0.16 stays. Its OS tags include `ios`, `tvos`, `visionos`, `watchos`,
and `macos`. Android is `linux` plus the Android ABI, OpenGL renderer.
Do not rewrite libghostty to Rust while those triples can emit objects.
watchOS has no Metal. The grid there is software, presented with SpriteKit.

libghostty is Ghostty. Copyright (c) 2024 Mitchell Hashimoto, Ghostty
contributors. MIT. https://github.com/ghostty-org/ghostty

The iOS embed is the starting point for Wawona's Ghostty work. That port
comes from Rootshell. Copyright (c) 2026 Rootshell LLC, Kit Knox. MIT.
iOS and iPadOS: static archive, deployment target 13.0, export `ghostty_*`
only. No product `.dylib`. Wawona does not vendor GhosttyKit headers.
Published GhosttyKit (minimum OS 17) is not an input. Do not rewrite
`LC_BUILD_VERSION`.
Toolbar keys are `ToolbarKeys`, not this repo.
Relay stays the VM engine.
