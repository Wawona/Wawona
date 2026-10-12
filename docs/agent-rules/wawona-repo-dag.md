---
description: Wawona org repo dependency DAG (L0-L4 acyclic); never invert layers when editing flakes/registry
alwaysApply: true
---

# Wawona repo DAG (acyclic, never invert)

Authority for how the Wawona organization repos depend on each other. Prefer
this over any prose that suggests putting graphics libs in the toolchain or
adding upward flake inputs. Canonical doc:
[`docs/wwn-repo-dag.md`](../../docs/wwn-repo-dag.md).

```text
L0 wwn-toolchain. Substrate only (cairo, pango, pixman, fontconfig, freetype,
 harfbuzz, fribidi, glib, libwayland, xkbcommon, epoll-shim, openssl, …).
 NO wwn-* flake inputs. NO iland/weston/kmscube keys in baseRegistry.
L1 iLand. Complete graphics stack (iland, iland-baremetal, ANGLE,
 SwiftShader, MoltenVK, KosmicKrisp, Turnip hooks, iland-cpu). Depends on
 wwn-toolchain ONLY.
catalog repo.wawona.io. wasm and deb, each cli, gui, and lib. Inputs
 wwn-toolchain only. One registryFragment for weston, niri, foot, kmscube,
 fastfetch, and phoon. `extraArgs.ilandSrc` stays a toolchain extra arg.
L3′ wwn-waypipe / Wawona-Swinging-Bridge / wwn-relay / wwn-ssh / wwn-iowatchdog / wwn-vphone / wwn-iomfb-rs / doorman / wwn-igetty. Toolchain (or nixpkgs-only for Watchdog / Doorman / vphone / IOMFB); merge iland only if GPU is needed (igetty presents via iland DRM); VT switching is wwn-igetty, not iland-baremetal. `wwn-vphone` never ships a prebuilt iOS VM. `wwn-iomfb-rs` is nixpkgs-only; L1 must not import it. Wawona L4 Mode B iOS links `ios.nix`. `wwn-relay` is Linux VMs + OCI-in-VM + Mode A WASI (never QEMU/UTM).
L4 Wawona. Merges all fragments; never an input of L0-L3.
```

## Hard rules

1. **L0 never imports L1+.** Never add `iLand`, `repo.wawona.io`, or a
 port flake (`weston`, `kmscube`, `niri`, `foot`, `fastfetch`, `phoon`) as a
 `wwn-toolchain` input, and never add their keys to `baseRegistry`. Those
 port GitHub repos are deleted. Recipes and one `registryFragment` live in
 `repo.wawona.io` `catalog/`.
2. **L1 never imports L2+.** `iLand` must not flake- or build-depend on
 weston, kmscube, waypipe, Wawona, or toytoolkit.
3. **Registry merges only upward.** Consumers do `baseRegistry // ilandFragment
 // …`; never merge app fragments back into toolchain's published
 `baseRegistry`.
4. **Source injection ≠ cycle.** `extraArgs.ilandSrc` (weston copies iland
 shims) is allowed; building iland *from* weston sources is not.
5. **One-way optional clients.** weston → kmscube is OK; kmscube → weston is
 forbidden.
6. **Graphics keys live in L1** (`angle`, `swiftshader`, MVK,
 KK, Turnip hooks). Substrate text/2D stack stays L0. Consumers needing
 GLES/Vulkan merge the iland fragment (or Wawona's merge), not bare toolchain.

## FORBIDDEN edges (reject in review)

- `pixman` / `cairo` / `pango` moved into `iLand` (would force cairo→iland;
 keep them L0, `iland-cpu` *uses* toolchain pixman).
- `angle` / `swiftshader` owned by `wwn-toolchain` (single owner is L1).
- `iLand` → weston / kmscube / waypipe (any direction that makes iland
 depend on its consumers).
- `wwn-toolchain` ← iland / weston (toolchain absorbing app fragments).
- `wwn-kmscube` → weston.
- `Wawona` as a flake input of any `wwn-*`.
- `iLand` → `wwn-iomfb-rs` (L1 must not import L3′ IOMFB).
- Android Turnip packaged in toolchain (Adreno ICD = L1 graphics, not
 substrate).

**When adding a flake input or a `registry.nix` key, re-read
`docs/wwn-repo-dag.md` and its cycle watch list first.** Any `flake.nix` /
`registry.nix` change must update or cite that doc in the same change.
