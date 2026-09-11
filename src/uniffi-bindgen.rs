// Local helper only. Do NOT add this as a Cargo [[bin]] (uniffi `cli` in
// crate2nix splits uniffi_bindgen SVHs: E0460). Nix owns bindgen:
// `dependencies/generators/uniffi-bindgen.nix` → `$out/uniffi`.
fn main() {
    uniffi::uniffi_bindgen_main();
}
