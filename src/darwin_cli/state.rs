//! Wawona-scoped virtual state for launchctl, disks, search, registry, trust.

use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

pub fn state_dir() -> PathBuf {
    if let Ok(p) = std::env::var("WAWONA_DARWIN_STATE") {
        if !p.is_empty() {
            return PathBuf::from(p);
        }
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".into());
    PathBuf::from(home).join("Library/Wawona/darwin-cli")
}

pub fn ensure_dir(p: &Path) -> std::io::Result<()> {
    fs::create_dir_all(p)
}

#[derive(Default, Serialize, Deserialize)]
pub struct DiskInventory {
    pub disks: Vec<VirtualDisk>,
}

#[derive(Serialize, Deserialize)]
pub struct VirtualDisk {
    pub id: String,
    pub name: String,
    pub size_bytes: u64,
}

#[derive(Default, Serialize, Deserialize)]
pub struct AppRegistry {
    pub ids: Vec<String>,
}

#[derive(Default, Serialize, Deserialize)]
pub struct TrustDb {
    pub allowed: Vec<String>,
}

#[derive(Default, Serialize, Deserialize)]
pub struct BackupDb {
    pub snapshots: Vec<String>,
}

pub fn load_json<T: for<'de> Deserialize<'de> + Default>(path: &Path) -> T {
    let Ok(data) = fs::read(path) else {
        return T::default();
    };
    serde_json::from_slice(&data).unwrap_or_default()
}

pub fn save_json<T: Serialize>(path: &Path, value: &T) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        ensure_dir(parent)?;
    }
    let data = serde_json::to_vec_pretty(value).unwrap_or_else(|_| b"{}\n".to_vec());
    fs::write(path, data)
}

pub fn launchd_dir() -> PathBuf {
    state_dir().join("launchd")
}

#[allow(dead_code)]
pub fn read_to_string(path: &Path) -> std::io::Result<String> {
    let mut f = fs::File::open(path)?;
    let mut s = String::new();
    f.read_to_string(&mut s)?;
    Ok(s)
}

#[allow(dead_code)]
pub fn write_string(path: &Path, s: &str) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        ensure_dir(parent)?;
    }
    let mut f = fs::File::create(path)?;
    f.write_all(s.as_bytes())
}

pub fn walk_names(root: &Path, needle: &str, out: &mut Vec<PathBuf>) {
    let Ok(rd) = fs::read_dir(root) else {
        return;
    };
    for ent in rd.flatten() {
        let p = ent.path();
        let name = ent.file_name().to_string_lossy().to_string();
        if name.contains(needle) {
            out.push(p.clone());
        }
        if p.is_dir() {
            walk_names(&p, needle, out);
        }
    }
}
