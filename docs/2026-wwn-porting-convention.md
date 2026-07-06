# Wawona — `wwn-*` Porting Convention

Any third-party software patched to run on Apple platforms and/or Android under
Wawona lives in a dedicated `wwn-<name>` repository in the Wawona GitHub org and
integrates through `wwn-toolchain`. This keeps upstream forks isolated, license-
clean, and independently CI-able.

## When to make a `wwn-*` repo

Make one when you must **patch** upstream source to be App Store compliant or to
cross-compile for Apple/Android (no JIT, no `fork+exec` of external binaries, no
`dlopen` of arbitrary code, sandbox-safe paths). Do **not** make one for
pure-Nix packaging of already-portable software.

## Existing repos (examples)

- `wwn-toolchain` — shared cross toolchains (Apple + Android NDK), the hub.
- `wwn-weston` — umbrella for Weston compositor + Weston clients on Apple/Android.
- `wwn-waypipe` — waypipe with libssh2 (iOS) / Dropbear (Android) transports.
- `wwn-fastfetch`, `wwn-neofetch`, `wwn-zsh` — App Store-compliant CLI ports.
- `wwn-apt` — StoreKit-backed package manager for optional modules.

## Naming (authoritative)

- Repo: `wwn-<upstream-name>`, lowercase, hyphenated (`wwn-hyprland`, not
  `wwn-Hyprland`).
- Resolved exception: there is **no `wwn-utm` repo**. The UTM engine unit
  (QEMU-TCTI patches + build scripts + reference backends) is vendored inside
  `wwn-vms` at `dependencies/vms/utm/` (the old `Wawona/UTM` fork was never
  published; folding it into `wwn-vms` removed the phantom dependency).
- Bundle/attr names in Nix follow the same stem (`wwn-niri`, attr `niri` inside).

## Repo skeleton

Each `wwn-*` repo provides:

1. `flake.nix` — exposes the port as packages keyed by target
   (`<name>-ios`, `-ios-sim`, `-android`, `-macos`), consuming `wwn-toolchain`.
2. `registryFragment` — a Nix attrset Wawona merges into its client registry so
   the app can discover/launch the port (see `dependencies/`).
3. `patches/` — upstream patches, one anchored file per concern, verifiable by a
   `verify-*-patches.py` anchor script (pattern used by `wwn-weston`).
4. `README.md` — port plan: upstream version, compliance deltas, delivery mode
   (native/nested/waypipe), current status.

## Planned ports

`wwn-niri`, `wwn-sway`, `wwn-hyprland`, `wwn-xfce`, `wwn-kde`, `wwn-gnome`,
`wwn-cosmic` (VM/UTM engine: vendored in `wwn-vms`, not a separate repo).
Full ports are downstream; repos start as
flake + `registryFragment` skeleton + port-plan README
(tracked by `p29-wwn-ports-scaffold`). Their StoreKit catalog entries already
exist in `wwn-apt` with `status: planned`.
