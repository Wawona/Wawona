---
name: wawona-nixpkgs2wasi
description: >-
  Curated nixpkgs Wayland clients to WASI P1/P2 for Wawona Relay and
  repo.wawona.io/wasm. Use when editing nixpkgs2wasi, n2w, wasm32-wawona,
  WPM package production from nixpkgs, or the foot.wasm north star.
---

# nixpkgs2wasi (pointer)

Repo: `github.com/Wawona/nixpkgs2wasi` (`development`). Layer **L3′**,
nixpkgs-only. CLI: `n2w`.

Converts a **curated** nixpkgs userspace closure into WASI bytecode. Linux is
not a runtime. Relay executes. Wawona Compositor is still Wayland. wwn-iland
is still userspace DRM/KMS/GBM.

North star: `n2w build nixpkgs#foot` → `wpm install foot` → a Wayland window.
No Linux VM.

## Open

- Cursor rule: `wawona-repo-dag` (never invert; this repo is not an L0-L3 input)
- `wawona-relay-wasm` / skill `wawona-relay` (engine stays in Relay)
- `repo-wawona-io-catalogs` (publish to `/wasm/v1` only)
- `wawona-product-map` (wasm is data; not a native app; not a VM)
- `wawona-rust-first` (tooling is Rust; upstream apps stay upstream)

Canonical: `nixpkgs2wasi/README.md`, `nixpkgs2wasi/docs/architecture.md`.
Milestone: Wawona/Wawona `nixpkgs2wasi`.

## Hard rejects

- Auto-mirror nixpkgs onto `/wasm`
- Stub `.wasm` that "builds"
- Claim Apple App Review approved a package (`n2w verify` is the runtime profile only)
- UIKit translator instead of Wayland
- QEMU / UTM / Linux kernel inside WASM
- Mode B flavor of the Runtime catalog
- Mix APT debs into this tree
- Native `wwn-foot` deleted because wasm foot exists
