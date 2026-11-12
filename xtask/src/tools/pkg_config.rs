//! A pkg-config for the slice's `.pc` files: the queries Rust build scripts
//! make (`--cflags`, `--libs`, `--modversion`, `--exists`, `--variable`,
//! `--static`), with `Requires` followed.

use anyhow::{bail, Context, Result};
use std::collections::{BTreeMap, HashSet};
use std::path::{Path, PathBuf};

struct Pc {
    vars: BTreeMap<String, String>,
    fields: BTreeMap<String, String>,
}

fn find(name: &str) -> Option<PathBuf> {
    let paths = [std::env::var("PKG_CONFIG_PATH"), std::env::var("PKG_CONFIG_LIBDIR")];
    paths
        .into_iter()
        .flatten()
        .flat_map(|p| p.split(':').map(PathBuf::from).collect::<Vec<_>>())
        .map(|d| d.join(format!("{name}.pc")))
        .find(|f| f.exists())
}

fn parse(path: &Path) -> Result<Pc> {
    let text = std::fs::read_to_string(path)?;
    let mut pc = Pc { vars: BTreeMap::new(), fields: BTreeMap::new() };
    pc.vars.insert("pcfiledir".into(), path.parent().unwrap().to_string_lossy().into_owned());
    for line in text.lines() {
        let line = line.split('#').next().unwrap().trim();
        if let Some((k, v)) = line.split_once(':').filter(|(k, _)| !k.contains('=')) {
            let v = expand(&pc.vars, v.trim());
            pc.fields.insert(k.trim().to_string(), v);
        } else if let Some((k, v)) = line.split_once('=') {
            let v = expand(&pc.vars, v.trim());
            pc.vars.insert(k.trim().to_string(), v);
        }
    }
    Ok(pc)
}

fn expand(vars: &BTreeMap<String, String>, s: &str) -> String {
    let mut out = String::new();
    let mut rest = s;
    while let Some(i) = rest.find("${") {
        out.push_str(&rest[..i]);
        let Some(j) = rest[i..].find('}') else { break };
        let key = &rest[i + 2..i + j];
        out.push_str(vars.get(key).map(String::as_str).unwrap_or(""));
        rest = &rest[i + j + 1..];
    }
    out + rest
}

/// Package names from a `Requires` value, without version constraints.
fn requires(v: &str) -> Vec<String> {
    let mut names = Vec::new();
    let mut skip = false;
    for tok in v.split(|c: char| c == ',' || c.is_whitespace()).filter(|t| !t.is_empty()) {
        if skip {
            skip = false;
        } else if ["=", "<", ">", "<=", ">=", "!="].contains(&tok) {
            skip = true;
        } else {
            names.push(tok.to_string());
        }
    }
    names
}

fn collect(name: &str, statik: bool, seen: &mut HashSet<String>, out: &mut Vec<Pc>) -> Result<()> {
    if !seen.insert(name.to_string()) {
        return Ok(());
    }
    let path = find(name).with_context(|| format!("Package {name} was not found in the pkg-config search path"))?;
    let pc = parse(&path)?;
    let mut reqs = requires(pc.fields.get("Requires").map(String::as_str).unwrap_or(""));
    if statik {
        reqs.extend(requires(pc.fields.get("Requires.private").map(String::as_str).unwrap_or("")));
    }
    out.push(pc);
    for r in reqs {
        collect(&r, statik, seen, out)?;
    }
    Ok(())
}

pub fn main() -> Result<()> {
    let (mut cflags, mut libs, mut statik, mut modversion, mut exists) = (false, false, false, false, false);
    let mut variable = None;
    let mut names = Vec::new();
    for a in std::env::args().skip(1) {
        match a.as_str() {
            "--cflags" | "--cflags-only-I" => cflags = true,
            "--libs" | "--libs-only-L" | "--libs-only-l" => libs = true,
            "--static" => statik = true,
            "--modversion" => modversion = true,
            "--exists" | "--print-errors" | "--short-errors" => exists = true,
            "--version" => {
                println!("0.29.2");
                return Ok(());
            }
            v if v.starts_with("--variable=") => variable = Some(v["--variable=".len()..].to_string()),
            v if v.starts_with("--atleast-version") || v.starts_with("--atleast-pkgconfig-version") => {}
            v if v.starts_with('-') => {}
            n => names.extend(requires(n)),
        }
    }
    if names.is_empty() {
        bail!("pkg-config: no package");
    }
    let mut pcs = Vec::new();
    let mut seen = HashSet::new();
    for n in &names {
        if let Err(e) = collect(n, statik, &mut seen, &mut pcs) {
            eprintln!("{e}");
            std::process::exit(1);
        }
    }
    if let Some(v) = variable {
        println!("{}", pcs[0].vars.get(&v).cloned().unwrap_or_default());
        return Ok(());
    }
    if modversion {
        println!("{}", pcs[0].fields.get("Version").cloned().unwrap_or_default());
        return Ok(());
    }
    let _ = exists;
    let mut words: Vec<String> = Vec::new();
    for pc in &pcs {
        if cflags {
            words.extend(pc.fields.get("Cflags").into_iter().flat_map(|v| v.split_whitespace().map(str::to_string)));
        }
        if libs {
            words.extend(pc.fields.get("Libs").into_iter().flat_map(|v| v.split_whitespace().map(str::to_string)));
            if statik {
                words.extend(
                    pc.fields.get("Libs.private").into_iter().flat_map(|v| v.split_whitespace().map(str::to_string)),
                );
            }
        }
    }
    let mut seen = HashSet::new();
    words.retain(|w| !w.starts_with("-L") && !w.starts_with("-I") || seen.insert(w.clone()));
    println!("{}", words.join(" "));
    Ok(())
}
