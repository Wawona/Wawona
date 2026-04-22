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

## Enforcement Points

- Runtime policy gating in `src/core/wayland/policy.rs`.
- Registry application points in:
  - `src/core/wayland/wlr/mod.rs`
  - `src/core/wayland/ext/mod.rs`
  - `src/core/wayland/plasma/mod.rs`
- Release profile selection:
  - Cargo features (`profile-store-safe`, `profile-store-safe-remote`, `profile-desktop-host`, `profile-full-dev`)
  - Optional env override: `WAWONA_PROTOCOL_PROFILE`.
