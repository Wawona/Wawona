---
name: wawona-icon-composer
description: Author or validate Wawona icon drafts and install shared Icon Composer agent tooling.
---

# Wawona Icon Composer

Read Wawona/design/icons/wwn-monogram/README.md and the globally installed
compose-app-icon skill. Shared tooling lives in
/etc/nix-darwin/.dotfiles/modules/apps/_ide-mcp.nix.

- Icon Composer 1.6 (build 99.1) is installed inside Xcode on this host.
- Native icon.json groups and layers are front-to-back. The carved face goes
  above the inner-wall group, which goes above the HDR emission group.
- The third-party schema accepted color-space-for-untagged-svg-colors set to
  srgb, but ictool 1.6 rejected that document. Omitting that key rendered.
  Always verify the full package with the installed Apple renderer.
- Current identity is an interlocking WWN monogram, superseding W, W! and
  the literal tree with lettering. Build a single-color letter symbol first;
  the tunnel can inform its counters. Annotate the separate silhouettes for
  native Liquid Glass. Keep the identity separate from its icon materials.
- Keep source SVGs, export transparent PNG wood layers, and validate assets.
- ictool 1.6 accepts an OpenEXR image-name asset. The dedicated 32-bit float
  RGBA glow layer in the earlier W! draft reached 4.0; the current WWN
  tunnel-tree draft reaches 2.0. Both were reopened and verified with
  SDR reference white 1.0. PNG previews are SDR; HDR display output remains
  unmeasured. Keep those two verification claims separate.
- Native renders add system edge lighting. Keep internal emission separate
  from wood artwork; carve real alpha cutouts rather than overlaying a glyph.
- The canonical shared skill is in dotfiles. Activation copies its runtime
  to a writable ~/.local/share/agent-skills directory before linking global
  skill paths. uv cannot create .venv inside an immutable Nix store source.
- Skill backups belong outside ~/.agents/skills to prevent duplicate discovery.
- Zed uses ~/.agents/skills. Antigravity uses ~/.gemini/config/skills;
  retain the legacy ~/.gemini/antigravity/skills path for older installations.
- A local stdio MCP is usable by local agent clients, not ChatGPT web.

Knowledge: wwn-mcp/knowledge/wawona/icon-composer.md.
