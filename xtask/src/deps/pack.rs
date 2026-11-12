//! Turn a Nix-built slice (a tree of store links) into a self-contained
//! `.tar.zst` that unpacks anywhere:
//!
//! - top-level links (bundle, zsh, fastfetch, src trees) become copies;
//!   links inside them stay links when relative and are copied when they
//!   point into the store;
//! - every store path the slice's text files, `.pc` files and Mach-O load
//!   commands name is copied under `store/`, transitively;
//! - those references are rewritten: `$(SRCROOT)/.deps/<sdk>/store/` in the
//!   xcconfig, `@SLICE@/store/` in slice.json and wawona.properties (the
//!   readers substitute the unpacked directory), and `${pcfiledir}`-relative
//!   in `.pc` files. Mach-O load commands keep their store paths; the
//!   embed step resolves them under `store/`.
//!
//! The archive is deterministic: sorted entries, zero mtimes and owners.

use crate::util::*;
use anyhow::{Context, Result};
use regex::Regex;
use std::collections::{BTreeSet, VecDeque};
use std::path::{Path, PathBuf};

const STORE: &str = "/nix/store/";

fn store_re() -> Regex {
    Regex::new(r"/nix/store/[0-9a-z]{32}-[^/\s'\x22$)<>:;,]+").unwrap()
}

pub fn pack(sdk: &str, from: &Path, out: &Path) -> Result<()> {
    let root = root();
    let stage = root.join("target/wawona-pack").join(sdk);
    let _ = std::fs::remove_dir_all(&stage);
    std::fs::create_dir_all(&stage)?;
    let re = store_re();
    let mut roots: BTreeSet<String> = BTreeSet::new();

    for e in std::fs::read_dir(from).with_context(|| format!("read_dir {}", from.display()))? {
        let e = e?;
        let name = e.file_name().to_string_lossy().into_owned();
        let src = std::fs::canonicalize(e.path())
            .with_context(|| format!("canonicalize {}", e.path().display()))?;
        let dst = stage.join(&name);
        if src.is_dir() {
            copy_tree(&src, &dst).with_context(|| format!("copy_tree {} -> {}", src.display(), dst.display()))?;
        } else {
            std::fs::copy(&src, &dst)
                .with_context(|| format!("copy {} -> {}", src.display(), dst.display()))?;
        }
    }

    // Seed: store paths that text files name.
    for f in walk_files(&stage) {
        if is_text_ref_file(&f) {
            if let Ok(s) = std::fs::read_to_string(&f) {
                roots.extend(re.find_iter(&s).map(|m| m.as_str().to_string()));
            }
        }
    }
    // Close over Mach-O load commands and .pc references.
    let mut queue: VecDeque<String> = roots.iter().cloned().collect();
    let mut copied = BTreeSet::new();
    for f in walk_files(&stage) {
        for r in macho_store_deps(&f) {
            if roots.insert(r.clone()) {
                queue.push_back(r);
            }
        }
    }
    while let Some(r) = queue.pop_front() {
        if !copied.insert(r.clone()) {
            continue;
        }
        let dst = stage.join("store").join(r.trim_start_matches(STORE));
        if !Path::new(&r).exists() {
            eprintln!("warning: {r} is referenced but not in the store");
            continue;
        }
        // The slice may already ship a `store/` tree (Android). Skip if the
        // path is already present from the top-level copy.
        if !dst.exists() {
            copy_tree(Path::new(&r), &dst)
                .with_context(|| format!("copy store {r} -> {}", dst.display()))?;
        }
        for f in walk_files(&dst) {
            let mut refs = macho_store_deps(&f);
            if f.extension().is_some_and(|x| x == "pc") {
                refs.extend(re.find_iter(&read(&f)?).map(|m| m.as_str().to_string()));
            }
            for x in refs {
                if roots.insert(x.clone()) {
                    queue.push_back(x);
                }
            }
        }
    }

    // Rewrite references.
    for f in walk_files(&stage) {
        let name = f.file_name().unwrap().to_string_lossy().into_owned();
        let to = match name.as_str() {
            "Wawona.xcconfig" => format!("$(SRCROOT)/.deps/{sdk}/store/"),
            "slice.json" | "wawona.properties" => "@SLICE@/store/".to_string(),
            n if n.ends_with(".pc") => "${pcfiledir}/../../../".to_string(),
            _ => continue,
        };
        let s = read(&f)?;
        if s.contains(STORE) {
            make_writable(&f)?;
            write(&f, s.replace(STORE, &to))?;
        }
    }

    archive(&stage, out)?;
    eprintln!("{sdk}: {} ({} store paths)", out.display(), copied.len());
    Ok(())
}

fn is_text_ref_file(f: &Path) -> bool {
    let n = f.file_name().unwrap().to_string_lossy();
    n == "Wawona.xcconfig" || n == "slice.json" || n == "wawona.properties"
}

fn make_writable(f: &Path) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;
    let mut p = std::fs::metadata(f)?.permissions();
    p.set_mode(p.mode() | 0o200);
    std::fs::set_permissions(f, p)?;
    Ok(())
}

fn walk_files(d: &Path) -> Vec<PathBuf> {
    walkdir::WalkDir::new(d)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().is_file())
        .map(|e| e.into_path())
        .collect()
}

/// Copies a tree: store links are dereferenced, relative links kept.
fn copy_tree(src: &Path, dst: &Path) -> Result<()> {
    let meta = std::fs::symlink_metadata(src)?;
    if meta.file_type().is_symlink() {
        let t = std::fs::read_link(src)?;
        if t.is_absolute() {
            return copy_tree(&std::fs::canonicalize(src)?, dst);
        }
        if let Some(d) = dst.parent() {
            std::fs::create_dir_all(d)?;
        }
        std::os::unix::fs::symlink(&t, dst)?;
        return Ok(());
    }
    if meta.is_dir() {
        std::fs::create_dir_all(dst)?;
        for e in std::fs::read_dir(src)? {
            let e = e?;
            copy_tree(&e.path(), &dst.join(e.file_name()))?;
        }
        return Ok(());
    }
    if let Some(d) = dst.parent() {
        std::fs::create_dir_all(d)?;
    }
    std::fs::copy(src, dst).with_context(|| format!("copy {}", src.display()))?;
    make_writable(dst)
}

fn is_macho(f: &Path) -> bool {
    use std::io::Read;
    let mut b = [0u8; 4];
    std::fs::File::open(f).and_then(|mut h| h.read_exact(&mut b)).is_ok()
        && matches!(u32::from_le_bytes(b), 0xfeedfacf | 0xfeedface | 0xbebafeca | 0xcafebabe)
}

/// Store roots named by a Mach-O's dylib load commands.
fn macho_store_deps(f: &Path) -> Vec<String> {
    if !is_macho(f) {
        return Vec::new();
    }
    let Some(s) = try_output(cmd("otool").arg("-L").arg(f)) else { return Vec::new() };
    let re = store_re();
    re.find_iter(&s).map(|m| m.as_str().to_string()).collect()
}

fn archive(stage: &Path, out: &Path) -> Result<()> {
    if let Some(d) = out.parent() {
        std::fs::create_dir_all(d)?;
    }
    let f = std::fs::File::create(out)?;
    let mut z = zstd::Encoder::new(f, 19)?;
    z.long_distance_matching(true)?;
    let mut t = tar::Builder::new(z);
    t.follow_symlinks(false);
    let mut entries: Vec<_> = walkdir::WalkDir::new(stage)
        .min_depth(1)
        .sort_by_file_name()
        .into_iter()
        .collect::<std::result::Result<_, _>>()?;
    entries.sort_by(|a, b| a.path().cmp(b.path()));
    for e in entries {
        let rel = e.path().strip_prefix(stage)?;
        let meta = std::fs::symlink_metadata(e.path())?;
        let mut h = tar::Header::new_gnu();
        h.set_mtime(0);
        h.set_uid(0);
        h.set_gid(0);
        use std::os::unix::fs::PermissionsExt;
        let mode = meta.permissions().mode();
        if meta.file_type().is_symlink() {
            h.set_entry_type(tar::EntryType::Symlink);
            h.set_size(0);
            h.set_mode(0o777);
            t.append_link(&mut h, rel, std::fs::read_link(e.path())?)?;
        } else if meta.is_dir() {
            h.set_entry_type(tar::EntryType::Directory);
            h.set_size(0);
            h.set_mode(0o755);
            t.append_data(&mut h, rel, std::io::empty())?;
        } else {
            h.set_entry_type(tar::EntryType::Regular);
            h.set_size(meta.len());
            h.set_mode(if mode & 0o111 != 0 { 0o755 } else { 0o644 });
            t.append_data(&mut h, rel, std::fs::File::open(e.path())?)?;
        }
    }
    t.into_inner()?.finish()?;
    Ok(())
}
