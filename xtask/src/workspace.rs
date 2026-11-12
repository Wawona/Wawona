//! `cargo xtask workspace prepare <dir>`: make the path crates under a Wawona
//! workspace resolvable from its root Cargo.toml and Cargo.lock.
//!
//! - `coreutils/`: uutils members inherit `{ workspace = true }` pins from a
//!   root that is not Wawona's. Expand them, drop the nested workspace, keep
//!   only the safe-subset utils and prune the optional crates they never
//!   enable, so `--locked` holds against Wawona's lockfile.
//! - `waypipe/`: drop the nested workspace and gbmfallback (Wawona enables
//!   lz4, zstd and video only).
//! - `--libghostty <src>`: copy libghostty-vt{,-sys} under `vendor/` with
//!   their workspace pins expanded (a git `cargo vendor` of a workspace member
//!   keeps `edition.workspace = true`) and point Wawona at them.
//! - `--platform`, `--version`: the Nix workspace's root manifest.
//!
//! Cargo.lock is edited as text: `--locked` compares cargo's serialization
//! with the file byte for byte.

use crate::util::*;
use anyhow::{bail, Result};
use regex::Regex;
use std::collections::BTreeSet;
use std::path::{Path, PathBuf};
use toml_edit::{Array, DocumentMut, InlineTable, Item, Table, Value};

#[derive(clap::Subcommand)]
pub enum Cmd {
    Prepare {
        dir: PathBuf,
        #[arg(long)]
        libghostty: Option<PathBuf>,
        /// ios, macos, linux, android, ...; non-desktop drops the root bins.
        #[arg(long)]
        platform: Option<String>,
        #[arg(long)]
        version: Option<String>,
    },
}

pub fn main(c: Cmd) -> Result<()> {
    let Cmd::Prepare { dir, libghostty, platform, version } = c;
    // A symlink is a tree `cargo xtask backend` linked from .deps/src, which
    // Nix already prepared and keeps read-only.
    let local = |name: &str| {
        let p = dir.join(name);
        let linked = p.symlink_metadata().is_ok_and(|m| m.file_type().is_symlink());
        Some(p).filter(|p| !linked && p.join("Cargo.toml").is_file())
    };
    if let Some(p) = local("waypipe") {
        waypipe(&p)?;
    }
    if let Some(p) = local("coreutils") {
        coreutils(&p)?;
    }
    if let Some(src) = libghostty {
        libghostty_stage(&src, &dir)?;
    }
    if let Some(v) = version {
        root_manifest(&dir, platform.as_deref().unwrap_or("macos"), &v)?;
    }
    Ok(())
}

/// The utils `Cargo.toml` enables as `coreutils` features (safe-subset.txt).
const UTILS: &[&str] = &[
    "ls", "cat", "cp", "mv", "rm", "mkdir", "rmdir", "ln", "touch", "echo", "pwd", "head", "tail", "wc", "sort", "cut",
    "tr", "seq", "basename", "dirname", "stat", "du", "df", "date", "env", "printenv", "uname", "whoami", "yes", "tee",
    "nl", "tac", "fold", "expand", "unexpand", "truncate", "chmod",
];
/// Host, hash, ACL and docs crates the safe subset never enables; they must
/// stay out of Cargo.lock.
const DROP: &[&str] = &[
    "selinux",
    "selinux-sys",
    "chcon",
    "runcon",
    "zip",
    "coz",
    "blake3",
    "blake2b_simd",
    "md-5",
    "sha1",
    "sha2",
    "sha3",
    "sm3",
    "digest",
    "crc32fast",
    "hex",
    "data-encoding",
    "data-encoding-macro",
    "data-encoding-macro-internal",
    "z85",
    "exacl",
    "utmp-classic",
    "utmp-classic-raw",
    "dns-lookup",
];
/// Optional only in uucore; the utils depend on these normally.
const DROP_UUCORE: &[&str] = &[
    "memchr",
    "regex",
    "time",
    "data-encoding",
    "data-encoding-macro",
    "z85",
    "blake3",
    "blake2b_simd",
    "md-5",
    "sha1",
    "sha2",
    "sha3",
    "sm3",
    "digest",
    "crc32fast",
    "hex",
    "utmp-classic",
    "utmp-classic-raw",
    "dns-lookup",
];
const DROP_FEATURES: &[&str] = &[
    "feat_selinux",
    "feat_systemd_logind",
    "feat_require_selinux",
    "feat_hardware",
    "feat_hash",
    "selinux",
    "checksum",
    "encoding",
    "sum",
    "utmpx",
    "uptime",
    "proc-info",
    "uudoc",
];
const STRUCTURAL: &[&str] = &[
    "default",
    "uudoc",
    "test_unimplemented",
    "nightly",
    "uucore",
    "macos",
    "unix",
    "windows",
    "expensive_tests",
    "test_risky_names",
    "feat_acl",
    "feat_common_core",
    "feat_os_unix",
    "feat_os_windows",
    "feat_os_macos",
    "feat_os_unix_android",
    "feat_require_unix",
    "feat_require_unix_utmpx",
    "feat_require_unix_hostid",
    "feat_require_unix_message",
];
/// A feature mentioning one of these is filtered item by item.
const DROPPED_TOKENS: &[&str] = &[
    "selinux",
    "\"zip\"",
    "blake3",
    "blake2b",
    "md-5",
    "sha1",
    "sha2",
    "sha3",
    "sm3",
    "digest",
    "crc32fast",
    "data-encoding",
    "z85",
    "exacl",
    "utmp-classic",
    "dns-lookup",
];

fn doc(p: &Path) -> Result<DocumentMut> {
    Ok(read(p)?.parse()?)
}

/// Every dependency table: top-level and `[target.*]`, dev ones when `dev`.
fn dep_tables(d: &mut DocumentMut, dev: bool) -> Vec<&mut Table> {
    let kinds: &[&str] = if dev {
        &["dependencies", "build-dependencies", "dev-dependencies"]
    } else {
        &["dependencies", "build-dependencies"]
    };
    let mut out = Vec::new();
    let t = d.as_table_mut();
    // Split borrows: collect target tables first.
    let mut targets = Vec::new();
    for (k, v) in t.iter_mut() {
        if k == "target" {
            if let Some(tt) = v.as_table_mut() {
                targets.push(tt);
            }
        } else if kinds.contains(&k.get()) {
            if let Some(x) = v.as_table_mut() {
                out.push(x);
            }
        }
    }
    for tt in targets {
        for (_, cfg) in tt.iter_mut() {
            if let Some(cfg) = cfg.as_table_mut() {
                for (k, v) in cfg.iter_mut() {
                    if kinds.contains(&k.get()) {
                        if let Some(x) = v.as_table_mut() {
                            out.push(x);
                        }
                    }
                }
            }
        }
    }
    out
}

fn is_workspace_ref(v: &Item) -> bool {
    v.get("workspace").and_then(Item::as_bool) == Some(true)
}

/// An Item as an inline table (a bare version string becomes `{ version }`).
fn inline(v: &Item) -> InlineTable {
    match v {
        Item::Value(Value::InlineTable(t)) => t.clone(),
        Item::Table(t) => t.clone().into_inline_table(),
        Item::Value(v) => {
            let mut t = InlineTable::new();
            t.insert("version", v.clone());
            t
        }
        _ => InlineTable::new(),
    }
}

/// Expand `{ workspace = true, extra }` against the root's
/// `[workspace.dependencies]`; the root's fields win over the member's.
/// `rebase` rewrites a root-relative `path`.
fn expand_deps(d: &mut DocumentMut, ws: &Table, dev: bool, rebase: &dyn Fn(&str) -> String) {
    for t in dep_tables(d, dev) {
        let keys: Vec<String> = t.iter().filter(|(_, v)| is_workspace_ref(v)).map(|(k, _)| k.to_string()).collect();
        for k in keys {
            let Some(base) = ws.get(&k) else {
                t.remove(&k);
                continue;
            };
            let mut merged = inline(base);
            if let Some(p) = merged.get("path").and_then(|p| p.as_str()).map(rebase) {
                merged.insert("path", p.into());
            }
            for (ek, ev) in inline(&t[&k]).iter() {
                if ek != "workspace" && !merged.contains_key(ek) {
                    merged.insert(ek, ev.clone());
                }
            }
            t[&k] = if merged.len() == 1 && merged.contains_key("version") && base.is_str() {
                base.clone()
            } else {
                Item::Value(Value::InlineTable(merged))
            };
        }
    }
}

/// `key.workspace = true` in `[package]` from `[workspace.package]`; a key the
/// root does not have is dropped.
fn expand_package(d: &mut DocumentMut, ws: &Table) {
    let Some(p) = d.get_mut("package").and_then(Item::as_table_mut) else { return };
    let keys: Vec<String> = p.iter().filter(|(_, v)| is_workspace_ref(v)).map(|(k, _)| k.to_string()).collect();
    for k in keys {
        match ws.get(&k) {
            Some(v) => p[&k] = v.clone(),
            None => {
                p.remove(&k);
            }
        }
    }
}

fn workspace_table(d: &DocumentMut, name: &str) -> Table {
    d.get("workspace").and_then(|w| w.get(name)).and_then(Item::as_table).cloned().unwrap_or_default()
}

fn package_name(d: &DocumentMut) -> String {
    d.get("package").and_then(|p| p.get("name")).and_then(Item::as_str).unwrap_or_default().to_string()
}

fn strs(a: &Array) -> Vec<String> {
    a.iter().filter_map(|v| v.as_str().map(str::to_string)).collect()
}

fn array(items: &[String]) -> Item {
    Item::Value(Value::Array(items.iter().map(String::as_str).collect()))
}

/// Drop the items of a feature that name a pruned crate or util; None drops
/// the feature.
fn filter_feature(feat: &str, items: &[String]) -> Option<Vec<String>> {
    if DROP_FEATURES.contains(&feat) || feat.contains("selinux") {
        return None;
    }
    let umbrella = feat.starts_with("feat_") || feat == "default";
    let mut kept: Vec<String> = items
        .iter()
        .filter(|item| {
            let base = item.split('/').next().unwrap_or(item);
            if DROP.contains(&base) || item.contains("selinux") {
                return false;
            }
            if umbrella
                && !UTILS.contains(&base)
                && !STRUCTURAL.contains(&base)
                && !base.starts_with("feat_")
                && base != "dep:uuhelp_parser"
                && base != "zip"
            {
                return base.strip_prefix("dep:").is_some_and(|d| !DROP.contains(&d));
            }
            true
        })
        .cloned()
        .collect();
    if feat == "uudoc" {
        kept.retain(|x| !x.contains("zip"));
    }
    Some(kept)
}

fn prune_optional(d: &mut DocumentMut) {
    let uucore = package_name(d) == "uucore";
    for t in dep_tables(d, false) {
        t.retain(|k, _| !DROP.contains(&k) && !(uucore && DROP_UUCORE.contains(&k)));
    }
    let Some(f) = d.get_mut("features").and_then(Item::as_table_mut) else { return };
    let names: Vec<String> = f.iter().map(|(k, _)| k.to_string()).collect();
    for feat in names {
        let Some(items) = f[&feat].as_array().map(strs) else { continue };
        if DROP_FEATURES.contains(&feat.as_str()) || feat.contains("selinux") {
            f.remove(&feat);
            continue;
        }
        let joined = format!("{feat} = [{}]", items.iter().map(|i| format!("{i:?}")).collect::<Vec<_>>().join(", "));
        let hit = DROPPED_TOKENS.iter().any(|t| joined.contains(t))
            || (uucore && ["memchr", "\"time\"", "regex"].iter().any(|t| joined.contains(t)));
        if hit {
            match filter_feature(&feat, &items) {
                Some(k) => f[&feat] = array(&k),
                None => {
                    f.remove(&feat);
                }
            }
        }
    }
}

/// The umbrella keeps only the safe-subset utils' path crates and features.
fn prune_umbrella(d: &mut DocumentMut) {
    for t in dep_tables(d, true) {
        t.retain(|k, v| {
            let util = v.get("package").and_then(Item::as_str).and_then(|p| p.strip_prefix("uu_")).unwrap_or(k);
            let path = v.get("path").and_then(Item::as_str);
            let path_util = path.is_some_and(|p| p.contains("/uu/"))
                || v.get("package").and_then(Item::as_str).is_some_and(|p| p.starts_with("uu_")) && path.is_some();
            !(DROP.contains(&k) || DROP.contains(&util) || (path_util && !UTILS.contains(&util)))
        });
    }
    let Some(f) = d.get_mut("features").and_then(Item::as_table_mut) else { return };
    let names: Vec<String> = f.iter().map(|(k, _)| k.to_string()).collect();
    for feat in names {
        let keep = !(DROP_FEATURES.contains(&feat.as_str()) || feat.contains("selinux"))
            && (UTILS.contains(&feat.as_str()) || STRUCTURAL.contains(&feat.as_str()) || feat.starts_with("feat_"));
        let filtered = if keep { f[&feat].as_array().map(strs).map(|i| filter_feature(&feat, &i)) } else { Some(None) };
        match filtered {
            Some(Some(k)) => f[&feat] = array(&k),
            Some(None) => {
                f.remove(&feat);
            }
            None => {}
        }
    }
}

/// Only the explicit multicall bin: no uudoc, no auto-discovered src/bin.
fn umbrella_bins(d: &mut DocumentMut) {
    if let Some(p) = d.get_mut("package").and_then(Item::as_table_mut) {
        p["autobins"] = toml_edit::value(false);
    }
    let bin_name = |t: &Table| t.get("name").and_then(Item::as_str).map(str::to_string);
    if let Some(bins) = d.get_mut("bin").and_then(Item::as_array_of_tables_mut) {
        bins.retain(|t| bin_name(t).as_deref() != Some("uudoc"));
    }
    let has = d
        .get("bin")
        .and_then(Item::as_array_of_tables)
        .is_some_and(|b| b.iter().any(|t| bin_name(t).as_deref() == Some("coreutils")));
    if !has {
        let mut t = Table::new();
        t["name"] = toml_edit::value("coreutils");
        t["path"] = toml_edit::value("src/bin/coreutils.rs");
        match d.get_mut("bin").and_then(Item::as_array_of_tables_mut) {
            Some(b) => b.push(t),
            None => {
                let mut b = toml_edit::ArrayOfTables::new();
                b.push(t);
                d["bin"] = Item::ArrayOfTables(b);
            }
        }
    }
}

/// uucore's thiserror derives are unconditional.
fn uucore_thiserror(d: &mut DocumentMut) {
    if package_name(d) != "uucore" {
        return;
    }
    if let Some(t) = d.get_mut("dependencies").and_then(Item::as_table_mut) {
        if !t.contains_key("thiserror") {
            t["thiserror"] = toml_edit::value("2.0.18");
        }
    }
}

fn strip_dev(d: &mut DocumentMut) {
    d.remove("dev-dependencies");
    if let Some(tt) = d.get_mut("target").and_then(Item::as_table_mut) {
        for (_, cfg) in tt.iter_mut() {
            if let Some(cfg) = cfg.as_table_mut() {
                cfg.remove("dev-dependencies");
            }
        }
    }
}

/// Lock package names of the normal, build and target dependencies.
fn dep_names(d: &mut DocumentMut) -> Vec<String> {
    let mut s = BTreeSet::new();
    for t in dep_tables(d, false) {
        for (k, v) in t.iter() {
            s.insert(v.get("package").and_then(Item::as_str).unwrap_or(k).to_string());
        }
    }
    s.into_iter().collect()
}

/// Rewrite the dependency list of `package`'s Cargo.lock entry, keeping the
/// version suffix (`"phf 0.11.3"`) each name had.
fn sync_lock(lock: &Path, package: &str, deps: &[String]) -> Result<()> {
    let Ok(text) = read(lock) else { return Ok(()) };
    let re = Regex::new(&format!(
        r#"(name = "{}"\nversion = [^\n]+\n(?:source = [^\n]+\n)?(?:checksum = [^\n]+\n)?)dependencies = \[([^\]]*)\]\n"#,
        regex::escape(package)
    ))?;
    let Some(m) = re.captures(&text) else {
        eprintln!("note: no lock package {package} to sync in {}", lock.display());
        return Ok(());
    };
    let old: Vec<&str> = Regex::new(r#""([^"]+)""#)?.captures_iter(&m[2]).map(|c| c.get(1).unwrap().as_str()).collect();
    let body: String = deps
        .iter()
        .map(|n| {
            let e = old.iter().find(|e| e.split(' ').next() == Some(n)).copied().unwrap_or(n);
            format!(" \"{e}\",\n")
        })
        .collect();
    let all = m.get(0).unwrap();
    let new = format!("{}{}dependencies = [\n{body}]\n{}", &text[..all.start()], &m[1], &text[all.end()..]);
    if new != text {
        write(lock, new)?;
    }
    Ok(())
}

fn coreutils(root: &Path) -> Result<()> {
    let root_toml = root.join("Cargo.toml");
    let mut top = doc(&root_toml)?;
    let ws_deps = workspace_table(&top, "dependencies");
    let ws_pkg = workspace_table(&top, "package");
    let expanded = top.get("workspace").and_then(|w| w.get("dependencies")).is_none();
    if expanded {
        umbrella_bins(&mut top);
        write(&root_toml, top.to_string())?;
    } else {
        let mut tomls = vec![root_toml.clone()];
        let mut rest: Vec<PathBuf> = walkdir::WalkDir::new(root)
            .into_iter()
            .filter_map(Result::ok)
            .map(|e| e.into_path())
            .filter(|p| p.file_name().is_some_and(|n| n == "Cargo.toml") && *p != root_toml)
            .collect();
        rest.sort();
        tomls.extend(rest);
        let abs_root = root.canonicalize()?;
        for t in &tomls {
            let mut d = doc(t)?;
            let crate_dir = t.parent().unwrap().canonicalize()?;
            let rebase = |p: &str| -> String {
                if Path::new(p).is_absolute() {
                    return p.to_string();
                }
                relative(&crate_dir, &abs_root.join(p))
            };
            expand_deps(&mut d, &ws_deps, true, &rebase);
            expand_package(&mut d, &ws_pkg);
            d.remove("workspace");
            strip_dev(&mut d);
            prune_optional(&mut d);
            uucore_thiserror(&mut d);
            if *t == root_toml {
                prune_umbrella(&mut d);
                umbrella_bins(&mut d);
            }
            write(t, d.to_string())?;
        }
        eprintln!("Expanded uutils workspace pins under {} ({} manifests)", root.display(), tomls.len());
    }
    let _ = std::fs::remove_file(root.join("src/bin/uudoc.rs"));
    let multicall = root.join("src/bin/coreutils.rs");
    if let Ok(src) = read(&multicall) {
        // Wawona builds the umbrella as a lib; the multicall bin reaches it by path.
        let mut s = src.replace("#[no_mangle]", "#[unsafe(no_mangle)]");
        if !s.contains("#[path = \"../lib.rs\"]") {
            s = s.replace(
                "use coreutils::validation::{self, exit};",
                "#[path = \"../lib.rs\"]\nmod coreutils;\nuse coreutils::validation::{self, exit};",
            );
        }
        if s != src {
            write(&multicall, s)?;
        }
    }
    let uucore = root.join("src/uucore/Cargo.toml");
    if uucore.is_file() {
        let mut d = doc(&uucore)?;
        uucore_thiserror(&mut d);
        write(&uucore, d.to_string())?;
    }
    let lock = root.parent().unwrap().join("Cargo.lock");
    sync_lock(&lock, "coreutils", &dep_names(&mut doc(&root_toml)?))?;
    if uucore.is_file() {
        sync_lock(&lock, "uucore", &dep_names(&mut doc(&uucore)?))?;
    }
    Ok(())
}

fn relative(from: &Path, to: &Path) -> String {
    let (f, t): (Vec<_>, Vec<_>) = (from.components().collect(), to.components().collect());
    let common = f.iter().zip(&t).take_while(|(a, b)| a == b).count();
    let mut parts: Vec<String> = std::iter::repeat_n("..".to_string(), f.len() - common).collect();
    parts.extend(t[common..].iter().map(|c| c.as_os_str().to_string_lossy().into_owned()));
    if parts.is_empty() {
        ".".into()
    } else {
        parts.join("/")
    }
}

fn waypipe(root: &Path) -> Result<()> {
    let toml = root.join("Cargo.toml");
    let _ = run(cmd("chmod").args(["-R", "u+w"]).arg(root));
    let mut d = doc(&toml)?;
    d.remove("workspace");
    for t in dep_tables(&mut d, true) {
        t.remove("gbmfallback");
        t.remove("waypipe-gbm-wrapper");
    }
    if let Some(f) = d.get_mut("features").and_then(Item::as_table_mut) {
        f.remove("gbmfallback");
        for (_, v) in f.iter_mut() {
            if let Some(a) = v.as_array_mut() {
                a.retain(|x| x.as_str() != Some("gbmfallback"));
            }
        }
    }
    write(&toml, d.to_string())?;
    sync_lock(&root.parent().unwrap().join("Cargo.lock"), "waypipe", &dep_names(&mut d))
}

fn libghostty_stage(src: &Path, workspace: &Path) -> Result<()> {
    let top = doc(&src.join("Cargo.toml"))?;
    let (ws_deps, ws_pkg) = (workspace_table(&top, "dependencies"), workspace_table(&top, "package"));
    let vendor = workspace.join("vendor");
    std::fs::create_dir_all(&vendor)?;
    for name in ["libghostty-vt", "libghostty-vt-sys"] {
        let from = src.join("crates").join(name);
        if !from.is_dir() {
            bail!("missing {}", from.display());
        }
        let dest = vendor.join(name);
        if dest.exists() {
            run(cmd("chmod").args(["-R", "u+w"]).arg(&dest))?;
            std::fs::remove_dir_all(&dest)?;
        }
        run(cmd("cp").arg("-R").arg(&from).arg(&dest))?;
        // Nix store sources are read-only.
        run(cmd("chmod").args(["-R", "u+w"]).arg(&dest))?;
        let _ = std::fs::remove_dir_all(dest.join("target"));
        let _ = std::fs::remove_dir_all(dest.join(".git"));
        let toml = dest.join("Cargo.toml");
        let mut d = doc(&toml)?;
        expand_package(&mut d, &ws_pkg);
        expand_deps(&mut d, &ws_deps, true, &|p| p.to_string());
        d.remove("workspace");
        // Only what Wawona's Cargo.lock pins: crate2nix vendors from it.
        let sys: Item = "{ path = \"../libghostty-vt-sys\", version = \"0.2.1\" }".parse::<Value>()?.into();
        let replace = |d: &mut DocumentMut, k: &str, body: &str| -> Result<()> {
            if d.contains_key(k) {
                d[k] = Item::Table(format!("[{k}]\n{body}").parse::<DocumentMut>()?[k].as_table().unwrap().clone());
            }
            Ok(())
        };
        if name == "libghostty-vt" {
            replace(&mut d, "features", "default = [\"kitty-graphics\"]\nkitty-graphics = [\"libghostty-vt-sys/kitty-graphics\"]\nlink-dynamic = [\"libghostty-vt-sys/link-dynamic\"]\n")?;
            replace(&mut d, "dependencies", "bitflags = \"2.11.0\"\nint-enum = \"1.2.0\"\n")?;
            if let Some(t) = d.get_mut("dependencies").and_then(Item::as_table_mut) {
                t["libghostty-vt-sys"] = sys.clone();
            }
            if d.contains_key("dev-dependencies") {
                let mut t = Table::new();
                t["libghostty-vt-sys"] = sys.clone();
                d["dev-dependencies"] = Item::Table(t);
            }
            if let Some(m) = d.get_mut("package").and_then(|p| p.get_mut("metadata")).and_then(Item::as_table_mut) {
                m.remove("docs");
            }
        } else {
            replace(&mut d, "features", "default = [\"vendored\"]\nvendored = []\npkg-config = [\"dep:pkg-config\"]\nlink-dynamic = []\nkitty-graphics = []\n")?;
            replace(&mut d, "dependencies", "")?;
            replace(&mut d, "build-dependencies", "pkg-config = { version = \"0.3\", optional = true }\n")?;
            // gen-bindings needs bindgen-tool.
            d.remove("bin");
        }
        write(&toml, d.to_string())?;
    }
    let cargo = workspace.join("Cargo.toml");
    let mut d = doc(&cargo)?;
    for t in dep_tables(&mut d, true) {
        for name in ["libghostty-vt", "libghostty-vt-sys"] {
            if t.contains_key(name) {
                t[name] = format!("{{ path = \"./vendor/{name}\", optional = true }}").parse::<Value>()?.into();
            }
        }
    }
    write(&cargo, d.to_string())?;
    // Path crates have no lock source.
    let lock = workspace.join("Cargo.lock");
    if let Ok(text) = read(&lock) {
        let re = Regex::new(r#"(name = "libghostty-vt(?:-sys)?"\nversion = [^\n]+\n)source = [^\n]+\n"#)?;
        write(&lock, re.replace_all(&text, "$1").as_ref())?;
    }
    Ok(())
}

/// The Nix workspace's version, and static libraries only off the desktop.
fn root_manifest(dir: &Path, platform: &str, version: &str) -> Result<()> {
    let cargo = dir.join("Cargo.toml");
    let mut d = doc(&cargo)?;
    if !matches!(platform, "macos" | "linux") {
        if let Some(l) = d.get_mut("lib").and_then(Item::as_table_mut) {
            l["crate-type"] = array(&["rlib".into(), "staticlib".into()]);
        }
        if let Some(p) = d.get_mut("package").and_then(Item::as_table_mut) {
            p["autobins"] = toml_edit::value(false);
        }
        d.remove("bin");
    }
    d["package"]["version"] = toml_edit::value(version);
    write(&cargo, d.to_string())?;
    let lock = dir.join("Cargo.lock");
    if let Ok(text) = read(&lock) {
        let re = Regex::new(r#"(name = "wawona"\n)version = [^\n]+\n"#)?;
        write(&lock, re.replacen(&text, 1, format!("${{1}}version = \"{version}\"\n")).as_ref())?;
    }
    Ok(())
}
