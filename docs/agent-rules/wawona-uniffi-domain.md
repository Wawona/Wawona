# UniFFI product domain (JFFI-shaped split)

Steal JFFI’s **split**, not the JFFI CLI. Wawona stays Wawona.

Cursor rule: `wawona-uniffi-domain`.
Related: `wawona-rust-first`, `wawona-platform-targets`,
`docs/2026-SOURCE-LAYOUT-RULES.md`.

## Idea

- Rust owns product logic: one schema, every target.
- UniFFI writes Swift and Kotlin **bindings**. Never hand-edit those files.
- SwiftUI stays SwiftUI (`Sources/WawonaUI`, `Sources/WawonaWatch`).
- Views call rust. No second profile engine in Swift or Kotlin.

JFFI 0.4.18 emits iOS, macOS, Android, Linux, Windows, web only. That list does
not define Wawona. Wawona owns the full Apple set (macOS, iOS, iPadOS, tvOS,
watchOS, visionOS) plus Android and Linux.

## Two bridges (do not merge)

1. **UniFFI** = product domain: machine profiles, prefs, launch, validation,
   session policy.
2. **`WWNCore*`** C + ObjC/JNI poll = compositor ABI (`src/ffi/c_api.rs`).
   Do not replace with UniFFI callbacks unless a later product change says so
   (`wawona-rust-first`).

## Hard rejects

- `jffi new` / `jffi add` inside this repo.
- Forking Jitpomi/jffi as `wwn-jffi` or `wffi`.
- New `MachineProfile` (or equivalent) fields only in Swift, Kotlin, or
  `src/linux/machine_profile.rs`.
- New feature SwiftUI under `src/platform/macos/ui/*`.
- Per-OS forks of domain types (`WWN*` copies of `WawonaModel`).
- Policy or validation in ObjC trampolines or generated bindings.

A bindgen + Apple-triples helper in Wawona or `wwn-toolchain` is fine. A JFFI
clone is not. Host bindgen is `dependencies/generators/uniffi-bindgen.nix`.
Generated Swift/Kotlin live in the Nix store (`wawona-nix-generated`).

## Where code lives

| Layer | Path | Role |
|---|---|---|
| Domain | rust + `#[uniffi::export]` | Source of truth |
| Bindings | Nix `$out/uniffi/{swift,kotlin}` | Sacred. Rebuild. Never git |
| Apple views | `Sources/WawonaUI` | Machines, Welcome, shared SwiftUI |
| Watch views | `Sources/WawonaWatch` | WatchKit-shaped. Same rust API |
| Apple leftover non-view Swift | one SPM target (`WawonaModel` or thinner) | Shared by all Apple platforms. Thin wrap only |
| Android UI | Compose | Calls the same rust API |
| Linux UI | `src/linux/ui` | Calls the same rust API |
| Old Machines UI | `src/platform/macos/ui` | Bridge. Die incrementally |

tvOS and watchOS get **target-shaped views**. Shared part is rust + generated
Swift, not one `ContentView` for every device.

## Freeze then lift

Today `MachineProfile` is triplicated:

- `Sources/WawonaModel/MachineProfile.swift`
- `src/linux/machine_profile.rs` (JSON mirror of Swift / Kotlin)
- `android/app/.../MachineProfiles.kt`

Do not grow those mirrors. First slice (landed): `src/domain` owns the schema,
`MachineProfileStoreApi` (list/get/put/delete + JSON v1), and editor
validation. Hosts persist the blob. Apple `WawonaModel` wraps via
`wawona_profiles_v1_*` until generated UniFFI Swift is imported. Then
launcher, wasm, session.

Keep `wawona.machineProfiles.v1` JSON keys byte-compatible so old profiles
still load.

`WawonaModel` may wrap generated Swift (`ObservableObject`) until the lift is
done. It is not allowed to stay the schema owner.

## Tests

Rust domain tests own serde / UniFFI behavior. An old profile JSON must still
decode after the lift.
