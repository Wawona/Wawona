fn main() {
    // UniFFI scaffolding is generated in-crate via uniffi::setup_scaffolding!
    // (see src/lib.rs). We deliberately do NOT call
    // uniffi_build::generate_scaffolding here: pulling uniffi_build into the
    // build-dependency graph makes crate2nix resolve uniffi_bindgen with a
    // different feature set than the `uniffi` (cli) normal dependency, which
    // produces two mismatched uniffi_bindgen rlibs and fails with E0460
    // ("found possibly newer version of crate uniffi_bindgen").

    // Rerun if wlroots protocols change
    println!("cargo:rerun-if-changed=protocols/wlroots/");

    // Android cross-link fallback: force xkbcommon link args when pkg-config
    // metadata does not propagate to the final crate link step.
    println!("cargo:rerun-if-env-changed=WAWONA_ANDROID_XKBCOMMON_LIBDIR");
    if std::env::var("CARGO_CFG_TARGET_OS").ok().as_deref() == Some("android") {
        if let Ok(libdir) = std::env::var("WAWONA_ANDROID_XKBCOMMON_LIBDIR") {
            if !libdir.is_empty() {
                println!("cargo:rustc-link-search=native={libdir}");
            }
        }
        println!("cargo:rustc-link-lib=xkbcommon");
    }
}
