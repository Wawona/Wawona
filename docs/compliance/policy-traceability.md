# Policy Traceability Matrix

This matrix links protocol/capability exposure policy to source policy documents.

## Apple Sources

- `inspirational_projects/apple-app-store/html/app-store_review_guidelines.html`
- `inspirational_projects/apple-app-store/html/support_terms_apple-developer-program-license-agreement.html`
- `inspirational_projects/apple-app-store/html/app-store_user-privacy-and-data-use.html`

## Google Play Sources

- `inspirational_projects/google-play-store/html/about_developer-content-policy.html`
- `inspirational_projects/google-play-store/html/distribute_play-policies.html`
- `inspirational_projects/google-play-store/html/console_about_guides_build-a-high-quality-app-or-game.html`

## Capability Mapping

| Capability | Exposure Class | Store-safe policy stance | Evidence anchor |
|---|---|---|---|
| Core compositor/shell (`wl_*`, `xdg_wm_base`) | `store-safe-core` | Allowed baseline | App Review core functionality guidance, Play quality baseline |
| Screencopy / image capture | `desktop-only` | Disabled in store-safe builds by profile | Apple explicit recording consent/visibility constraints; Play user-data and abuse protections |
| DMA-BUF export | `desktop-only` | Disabled in store-safe builds | Store-safe least-privilege and non-abuse requirement |
| Virtual pointer/keyboard | `desktop-only` | Disabled in store-safe builds | Input-injection abuse risk; store-safe profile excludes synthetic global managers |
| WLR data-control manager | `desktop-only` | Disabled in store-safe builds | Clipboard/privacy surface minimization |
| XWayland shell / keyboard grab | `desktop-only` | Disabled in store-safe builds | Desktop-only interoperability path |
| EXT data-control | `store-safe-conditional` | Allowed only with explicit product policy and disclosure | User data handling and permission minimization |
| Local embedded shell (bundled zsh via PTY) | `store-safe-conditional` | Allowed when spawn path is locked to app rootfs; keyboard + file access disclosed | [ios-local-shell/APP-STORE-COMPLIANCE.md](../ios-local-shell/APP-STORE-COMPLIANCE.md), [SECURITY-SPAWN-POLICY.md](../ios-local-shell/SECURITY-SPAWN-POLICY.md) |
| Remote SSH / waypipe shell | `store-safe-remote` | Allowed; executes on user-configured remote host | [2026-waypipe.md](../2026-waypipe.md) |
| Post-review native binary download + exec | **forbidden** | Never allowed in store-safe profiles | `wwn_pty_is_allowed_shell_path`, waypipe guards |
| x86 usermode guest / JIT shell | **forbidden** | Out of product scope (iSH-style) | [ios-local-shell/README.md](../ios-local-shell/README.md) |

## Enforcement Points

- Runtime policy gating in `src/core/wayland/policy.rs`.
- Registry application points in:
  - `src/core/wayland/wlr/mod.rs`
  - `src/core/wayland/ext/mod.rs`
  - `src/core/wayland/plasma/mod.rs`
- Release profile selection:
  - Cargo features (`profile-store-safe`, `profile-store-safe-remote`, `profile-desktop-host`, `profile-full-dev`)
  - Optional env override: `WAWONA_PROTOCOL_PROFILE`.
- Local shell spawn (Apple mobile):
  - `wwn-toolchain/dependencies/libs/wawona-pty/`. Path allowlist, in-process spawn on Apple mobile
  - `WWNRootfsManager`. Bundled rootfs install under Application Support
  - `WWNWaypipeRunner.m`. Sanitized env before `weston_terminal_main`
  - Documentation: [docs/ios-local-shell/](../ios-local-shell/README.md)
