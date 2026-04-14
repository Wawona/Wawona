fn main() {
    // Generate UniFFI scaffolding
    uniffi_build::generate_scaffolding("src/wawona.udl")
        .expect("Failed to generate UniFFI scaffolding");
    println!("cargo:rerun-if-changed=src/wawona.udl");

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
