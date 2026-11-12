//! Mach-O load commands that name the Nix store.

use crate::util::*;
use anyhow::Result;
use std::path::{Path, PathBuf};

/// A store path as it exists on this machine: itself under a `--nix` slice,
/// else inside the packed slice's `store/` directory.
pub fn resolve(deps: &Path, p: &Path) -> PathBuf {
    if p.exists() {
        return p.to_path_buf();
    }
    match p.strip_prefix("/nix/store") {
        Ok(rel) => deps.join("store").join(rel),
        Err(_) => p.to_path_buf(),
    }
}

pub fn is_macho(p: &Path) -> bool {
    let mut b = [0u8; 4];
    use std::io::Read;
    std::fs::File::open(p).and_then(|mut f| f.read_exact(&mut b)).is_ok()
        && matches!(u32::from_le_bytes(b), 0xfeedfacf | 0xfeedface | 0xcafebabe | 0xbebafeca)
}

/// The store paths a Mach-O loads (LC_LOAD, LC_LOAD_WEAK, LC_REEXPORT).
pub fn store_deps(m: &Path) -> Result<Vec<String>> {
    let l = output(cmd("otool").arg("-l").arg(m))?;
    let mut v = Vec::new();
    let mut want = false;
    for line in l.lines().map(str::trim) {
        if let Some(c) = line.strip_prefix("cmd ") {
            want = matches!(c, "LC_LOAD_DYLIB" | "LC_LOAD_WEAK_DYLIB" | "LC_REEXPORT_DYLIB");
        } else if want {
            if let Some(name) = line.strip_prefix("name ") {
                let p = name.split(" (offset").next().unwrap_or(name);
                if p.starts_with("/nix/store/") {
                    v.push(p.to_string());
                }
                want = false;
            }
        }
    }
    Ok(v)
}

fn rpaths(m: &Path) -> Result<Vec<String>> {
    let l = output(cmd("otool").arg("-l").arg(m))?;
    let mut v = Vec::new();
    let mut want = false;
    for line in l.lines().map(str::trim) {
        if let Some(c) = line.strip_prefix("cmd ") {
            want = c == "LC_RPATH";
        } else if want {
            if let Some(p) = line.strip_prefix("path ") {
                v.push(p.split(" (offset").next().unwrap_or(p).to_string());
                want = false;
            }
        }
    }
    Ok(v)
}

/// The app and its helpers link store dylibs by absolute path. Copy each into
/// Frameworks, point the load commands at @rpath, and re-sign the helpers,
/// since the app's CodeSign phase refuses an unsigned nested Mach-O. The app
/// itself is signed by that phase, which runs after this one.
pub fn bundle_dylibs(deps: &Path, contents: &Path) -> Result<()> {
    let fw = contents.join("Frameworks");
    std::fs::create_dir_all(&fw)?;
    let main = contents.join("MacOS").join(std::env::var("EXECUTABLE_NAME")?);
    let machos = || -> Vec<PathBuf> {
        let mut dirs = vec![contents.join("MacOS"), contents.join("Resources/bin"), fw.clone()];
        if let Ok(rd) = std::fs::read_dir(contents.join("Resources/lib")) {
            dirs.extend(rd.flatten().map(|e| e.path()));
        }
        dirs.iter()
            .flat_map(|d| match std::fs::read_dir(d) {
                Ok(rd) => rd.flatten().map(|e| e.path()).collect(),
                Err(_) => vec![d.clone()],
            })
            .filter(|p| p.is_file() && !p.is_symlink() && is_macho(p))
            .collect()
    };

    for d in machos() {
        let id = output(cmd("otool").arg("-D").arg(&d))?;
        if id.lines().nth(1).is_some_and(|l| l.starts_with("/nix/store/")) {
            run(cmd("install_name_tool").arg("-id").arg(format!("@rpath/{}", name(&d))).arg(&d))?;
        }
    }
    loop {
        let mut added = false;
        for m in machos() {
            for d in store_deps(&m)? {
                let b = name(Path::new(&d));
                let dst = fw.join(&b);
                if dst.exists() {
                    continue;
                }
                std::fs::copy(resolve(deps, Path::new(&d)), &dst)?;
                crate::xcode::make_writable(&dst)?;
                run(cmd("install_name_tool").arg("-id").arg(format!("@rpath/{b}")).arg(&dst))?;
                added = true;
            }
        }
        if !added {
            break;
        }
    }
    let identity = std::env::var("EXPANDED_CODE_SIGN_IDENTITY").ok().filter(|s| !s.is_empty()).unwrap_or("-".into());
    let signing = std::env::var("CODE_SIGNING_ALLOWED").map(|v| v == "YES").unwrap_or(true);
    for m in machos() {
        for d in store_deps(&m)? {
            run(cmd("install_name_tool")
                .arg("-change")
                .arg(&d)
                .arg(format!("@rpath/{}", name(Path::new(&d))))
                .arg(&m))?;
        }
        let have = rpaths(&m)?;
        for rp in have.iter().filter(|r| r.starts_with("/nix/store/")) {
            run(cmd("install_name_tool").arg("-delete_rpath").arg(rp).arg(&m))?;
        }
        let rp = if m.starts_with(contents.join("Resources")) {
            "@executable_path/../../Frameworks"
        } else {
            "@executable_path/../Frameworks"
        };
        let uses_rpath = output(cmd("otool").arg("-L").arg(&m))?.contains("@rpath/");
        if uses_rpath && !have.iter().any(|r| r == rp) {
            run(cmd("install_name_tool").arg("-add_rpath").arg(rp).arg(&m))?;
        }
        if signing && m != main {
            run(cmd("codesign").args(["--force", "--timestamp=none", "--sign", &identity]).arg(&m))?;
        }
    }
    Ok(())
}

fn name(p: &Path) -> String {
    p.file_name().unwrap_or_default().to_string_lossy().into_owned()
}
