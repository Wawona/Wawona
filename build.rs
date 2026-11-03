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
    println!("cargo:rerun-if-env-changed=WAWONA_BUILD_NUMBER");
    println!("cargo:rerun-if-changed=src/core/wayland/catalog.rs");
    println!("cargo:rerun-if-changed=src/core/wayland/protocol_proofs.rs");

    // Fail closed at compile time when Functional catalog rows and
    // PROTOCOL_PROOF_OBLIGATIONS drift (mathematical-proof inventory).
    fail_if_protocol_proof_inventory_drifts();

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

/// Parse Functional interfaces from catalog.rs and obligation interfaces from
/// protocol_proofs.rs. Panic (fail the build) if the sets differ.
fn fail_if_protocol_proof_inventory_drifts() {
    use std::collections::BTreeSet;
    use std::path::PathBuf;

    let manifest = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap());
    let catalog = std::fs::read_to_string(manifest.join("src/core/wayland/catalog.rs"))
        .expect("read catalog.rs");
    let proofs = std::fs::read_to_string(manifest.join("src/core/wayland/protocol_proofs.rs"))
        .expect("read protocol_proofs.rs");

    let functional = functional_interfaces_from_catalog(&catalog);
    let mut obligations = BTreeSet::new();
    for line in proofs.lines() {
        let t = line.trim();
        if let Some(rest) = t.strip_prefix("interface: \"") {
            if let Some(end) = rest.find('"') {
                obligations.insert(rest[..end].to_string());
            }
        }
    }

    if functional != obligations {
        let missing: Vec<_> = functional.difference(&obligations).cloned().collect();
        let extra: Vec<_> = obligations.difference(&functional).cloned().collect();
        panic!(
            "protocol proof inventory drifted (fail closed).\n\
             Functional missing obligations: {missing:?}\n\
             Obligations not Functional: {extra:?}\n\
             Update src/core/wayland/protocol_proofs.rs and add Kani harnesses."
        );
    }
}

fn functional_interfaces_from_catalog(catalog: &str) -> std::collections::BTreeSet<String> {
    use std::collections::BTreeSet;
    let mut out = BTreeSet::new();
    let mut pos = 0;
    while let Some(rel) = catalog[pos..].find("cat!(") {
        let start = pos + rel;
        // Interface name is the first "..." after cat!(
        let after = &catalog[start + 5..];
        let Some(q0) = after.find('"') else {
            pos = start + 5;
            continue;
        };
        let name_start = start + 5 + q0 + 1;
        let Some(q1) = catalog[name_start..].find('"') else {
            pos = name_start;
            continue;
        };
        let name_end = name_start + q1;
        let name = &catalog[name_start..name_end];

        // Status is the first of Functional|Partial|Stub|Missing after the name.
        // Do not stop at ')' — module paths contain "(smithay …)".
        let tail = &catalog[name_end..];
        let window = &tail[..tail.len().min(1200)];
        let status = ["Functional", "Partial", "Stub", "Missing"]
            .iter()
            .filter_map(|s| window.find(s).map(|i| (i, *s)))
            .min_by_key(|(i, _)| *i)
            .map(|(_, s)| s);
        if status == Some("Functional") {
            out.insert(name.to_string());
        }
        pos = name_end + 1;
    }
    out
}
