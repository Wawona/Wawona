//! Build tools the backend's build scripts call by name, served by this
//! binary under that name so a checkout needs no bindgen, pkg-config or
//! uniffi-bindgen install.

mod bindgen;
mod pkg_config;

use anyhow::Result;
use std::path::{Path, PathBuf};

pub const NAMES: &[&str] = &["pkg-config", "bindgen", "uniffi-bindgen"];

/// Runs the tool `argv[0]` names, if it is one.
pub fn dispatch() -> Option<Result<()>> {
    let arg0 = std::env::args_os().next()?;
    let name = Path::new(&arg0).file_name()?.to_string_lossy().into_owned();
    Some(match name.as_str() {
        "pkg-config" => pkg_config::main(),
        "bindgen" => bindgen::main(),
        "uniffi-bindgen" => {
            uniffi::uniffi_bindgen_main();
            Ok(())
        }
        _ => return None,
    })
}

/// Links each tool name to this executable in `target/wawona-tools`.
pub fn install(root: &Path) -> Result<PathBuf> {
    let dir = root.join("target/wawona-tools");
    let exe = std::env::current_exe()?;
    for n in NAMES {
        let link = dir.join(n);
        if std::fs::read_link(&link).ok().as_deref() != Some(exe.as_path()) {
            crate::util::symlink(&exe, &link)?;
        }
    }
    Ok(dir)
}
