# Wawona code is Rust

New Wawona-owned logic (daemons, helpers, compositor core, Mode B tty, tools)
is **Rust**. Do not add standalone `.c` programs or grow C as the implementation
language.

## Allowed C / Swift / JNI (glue only)

Native UI kits are not written in Rust. Thin interop is expected:

- **FFI / UniFFI / JNI** bindings that call into Rust (`WWNCore*`, `android_jni.c`,
  generated UniFFI C). Keep the C file a trampoline; put behavior in Rust.
- **Swift / SwiftUI / Kotlin / Jetpack** UI and Apple/Android framework entry points.
  Apple framework glue lives in `Sources/WawonaApple`. No new Objective-C classes.
- **macOS `.dylib` constructors** and other ABI that must be C (iland Mode B
  insert, `DYLD_INSERT_LIBRARIES`). Logic behind the export still prefers Rust.

Bitfield or Mach message packing may stay a few C lines next to the FFI, not a
second copy of the product.

## Not this rule

- **Upstream ports** (Weston, Niri, kmscube, libvterm, zsh, …). Keep upstream
  language. Port fidelity: substitute the platform, not the client.
- **L0 substrate** recipes in `wwn-toolchain` (cairo, pango, …).
- Existing compositor bridge: keep **hand-written** `WWNCore*` (`src/ffi/c_api.rs`
  + Swift/JNI wrappers). Do not replace it with UniFFI callbacks unless a later
  product change says so.

## Hard rejects

- New Mode B / Desktop helpers, tty daemons, or Wawona CLI in C.
- Reimplementing a Wawona feature in C because "the old file was C".
- Putting product policy or draw/session loops in Swift or leftover ObjC when
  Rust can own them.
- New Apple product `.m` / `.mm` files.

Cursor rule: `wawona-rust-first`.
