//! Per-machine thumbnail persistence (mirrors Android `MachineThumbnailStore`).
//!
//! PNG files live under `~/.config/wawona/machine-thumbnails/<machine-id>.png`.

use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};

fn base_dir() -> Result<PathBuf> {
    let base = if let Ok(custom) = std::env::var("XDG_CONFIG_HOME") {
        PathBuf::from(custom)
    } else {
        let home = std::env::var("HOME").context("HOME is not set")?;
        Path::new(&home).join(".config")
    };
    Ok(base.join("wawona").join("machine-thumbnails"))
}

/// Path to the PNG thumbnail for a machine, if stored.
pub fn thumbnail_path(machine_id: &str) -> Result<PathBuf> {
    Ok(base_dir()?.join(format!("{machine_id}.png")))
}

/// True when a thumbnail PNG exists on disk.
pub fn has_thumbnail(machine_id: &str) -> bool {
    thumbnail_path(machine_id)
        .ok()
        .is_some_and(|p| p.is_file())
}

/// Write raw PNG bytes for a machine thumbnail.
pub fn save_png(machine_id: &str, png_bytes: &[u8]) -> Result<()> {
    let path = thumbnail_path(machine_id)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("failed to create {}", parent.display()))?;
    }
    fs::write(&path, png_bytes).with_context(|| format!("failed to write {}", path.display()))?;
    Ok(())
}

/// Remove a machine's stored thumbnail.
pub fn delete(machine_id: &str) -> Result<()> {
    let path = thumbnail_path(machine_id)?;
    if path.exists() {
        fs::remove_file(&path).with_context(|| format!("failed to remove {}", path.display()))?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn thumbnail_path_is_under_config() {
        let path = thumbnail_path("abc-123").unwrap();
        assert!(path.to_string_lossy().contains("machine-thumbnails"));
        assert!(path.to_string_lossy().ends_with("abc-123.png"));
    }
}
