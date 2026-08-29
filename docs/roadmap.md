# Wawona Roadmap

This splits the mega-checklist in [#8](https://github.com/Wawona/Wawona/issues/8)
into themed tracks, each pointing at the canonical doc or issue where the real
work lives. It is a map, not a second source of truth: status flows from the
linked docs.

## Kernel & core execution

Run bundled binaries inside the iOS/Android sandbox without `fork`/`exec`.

- Done: kernel extracted into a reusable module; in-process dispatch
  (`wawona_dispatch_inprocess`) runs multiple bundled entry points.
- In progress: broadening the bundled binary set and validating the
  multi-binary model.
- Canonical: [`ios-local-shell/ARCHITECTURE.md`](./ios-local-shell/ARCHITECTURE.md),
  [`ios-local-shell/STATUS.md`](./ios-local-shell/STATUS.md).

## Sandboxed filesystem

Linux-like rootfs (`/bin`, `/usr`, `/lib`, `/home`) embedded in the app bundle.

- Done: rootfs embed + `VIMRUNTIME`/tool paths wired for iOS.
- Canonical: `dependencies/wawona/ios-rootfs.nix`,
  [`ios-local-shell/STATUS.md`](./ios-local-shell/STATUS.md).

## Terminal & shell

On-device terminal connected to the kernel with real shell features.

- Done: App Store-compliant bundled `zsh` + Weston `terminal.c`; history,
  pipes, env vars.
- Canonical: [`ios-local-shell/README.md`](./ios-local-shell/README.md).

## Package manager

- Done: in-process, read-only `apt()` wrapper (App Store compliant); Nix-based
  ecosystem via the `wwn-*` repos.
- Follow-up: StoreKit/ODR purchase + install flow (W2-W4 in the local-shell
  plan).
- Canonical: [`ios-local-shell/STATUS.md`](./ios-local-shell/STATUS.md).

## Launcher & connection panel

- Tracked as [#32](https://github.com/Wawona/Wawona/issues/32): dedicated
  launcher panel + Bonjour discovery.
- Canonical: [`launcher-panel.md`](./launcher-panel.md).

## Session persistence (wprs-style)

- Planned: Xpra-like persistence so remote sessions survive disconnect and hold
  multiple clients across macOS/iOS/Android. Not started.

## Platform & input

- Game controllers ([#46](https://github.com/Wawona/Wawona/issues/46)):
  implemented. [`game-controller.md`](./game-controller.md).
- Platform delivery matrix:
  [`2026-platform-delivery-matrix.md`](./2026-platform-delivery-matrix.md).

## Compositor compatibility

- Nested desktops/compositors and the `p29-wwn-*` native ports:
  [`2026-COMPOSITOR-COMPARISON-AND-ROADMAP.md`](./2026-COMPOSITOR-COMPARISON-AND-ROADMAP.md),
  [`2026-toolkit-de-compat.md`](./2026-toolkit-de-compat.md).
- **Bucket C (`p29-wwn-sway`/`niri`/`kde`/`gnome`/`xfce`/`hyprland`). Deferred.**
  These native ports were the fallback for running sway/niri nested if the
  Waypipe remote path proved insufficient. With the Waypipe remote-sway launch
  fixed ([#54](https://github.com/Wawona/Wawona/issues/54), the `env`-prefix fix
  in `WWNWaypipeRunner.m`), remote nesting works over Waypipe, so the native
  ports are not required right now. Revisit only if a concrete Waypipe
  limitation blocks a target compositor.

## Project meta

- **Repo cleanup ([#1](https://github.com/Wawona/Wawona/issues/1)):** ongoing;
  structure is documented in
  [`2026-ARCHITECTURE-STRUCTURE.md`](./2026-ARCHITECTURE-STRUCTURE.md). Treat as
  continuous hygiene, not a one-shot task.
- **User survey ([#25](https://github.com/Wawona/Wawona/issues/25)):** external
  form (use case, willingness to pay, perceived value). Needs a hosted form
  (e.g. Tally/Google Forms); link it from the README when live.
- **Donations ([#26](https://github.com/Wawona/Wawona/issues/26)):** live via
  [`.github/FUNDING.yml`](../.github/FUNDING.yml). GitHub Sponsors (one-time and
  monthly) and Ko-fi.
