//! Resolve Machines kind `wasm` the same way native shell does: `wasm <file|package>`.
//!
//! Catalog is Mode A only (`https://repo.wawona.io/wasm/v1`). Never APT.

use crate::linux::machine_profile::MachineProfile;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

pub const DEFAULT_COMMAND: &str = "wasm hello-wasi-gui";
pub const DEFAULT_PACKAGE: &str = "hello-wasi-gui";
pub const CATALOG_BASE: &str = "https://repo.wawona.io/wasm/v1";
pub const CATALOG_INDEX: &str = "https://repo.wawona.io/wasm/v1/index.json";

const BUNDLED_ALIASES: &[&str] = &[
    "hello-wasi-gui",
    "hello-wasi-gui.wasm",
    "wasi-hello-gui",
    "wasi-hello-gui.wasm",
    "hello-wasi",
];

pub fn is_allowed_catalog_url(url: &str) -> bool {
    let lower = url.to_ascii_lowercase();
    if lower.contains("/jailbreak/") || lower.contains("/termux/") {
        return false;
    }
    if lower.contains("/packages") && !lower.contains("/wasm/") {
        return false;
    }
    if lower.ends_with(".deb") {
        return false;
    }
    lower.starts_with(CATALOG_BASE) || lower.contains("/wasm/v1") || lower.contains("/wasm/")
}

pub fn normalize_alias(token: &str) -> String {
    let trimmed = token.trim();
    if trimmed.is_empty() || BUNDLED_ALIASES.contains(&trimmed) {
        DEFAULT_PACKAGE.to_string()
    } else {
        trimmed.to_string()
    }
}

pub fn command_requests_install(raw: &str) -> bool {
    let tokens: Vec<&str> = raw.split_whitespace().collect();
    tokens.len() >= 2 && tokens[0] == "wpm" && tokens[1] == "install"
}

pub fn wasm_arg_from_command(raw: &str) -> String {
    let tokens: Vec<&str> = raw.split_whitespace().collect();
    if tokens.is_empty() {
        return DEFAULT_PACKAGE.to_string();
    }
    match tokens[0] {
        "wasm" => normalize_alias(tokens.get(1).copied().unwrap_or(DEFAULT_PACKAGE)),
        "wpm" => {
            if tokens.len() >= 3 && matches!(tokens[1], "install" | "path" | "show" | "run") {
                let name = tokens[2].split('@').next().unwrap_or(tokens[2]);
                return normalize_alias(name);
            }
            if tokens.len() >= 2 {
                return normalize_alias(tokens[1]);
            }
            DEFAULT_PACKAGE.to_string()
        }
        other => normalize_alias(other),
    }
}

pub fn modules_dir() -> PathBuf {
    if let Ok(env) = std::env::var("WAWONA_WASM_MODULES") {
        if !env.is_empty() {
            return PathBuf::from(env);
        }
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".into());
    PathBuf::from(home).join(".local/share/Wawona/wasm-modules")
}

fn local_module_named(name: &str) -> Option<PathBuf> {
    let dest = modules_dir().join(format!("{}.wasm", normalize_alias(name)));
    dest.is_file().then_some(dest)
}

/// Fetch `/wasm/v1` into the Wawona folder when the package is not local.
pub fn ensure_package_file(name: &str) -> Option<PathBuf> {
    let wanted = normalize_alias(name);
    if BUNDLED_ALIASES.contains(&wanted.as_str()) || wanted == DEFAULT_PACKAGE {
        return None;
    }
    if let Some(existing) = local_module_named(&wanted) {
        return Some(existing);
    }
    if !is_allowed_catalog_url(CATALOG_INDEX) {
        return None;
    }
    let index = http_get(CATALOG_INDEX)?;
    let pkg_url = catalog_url_for_name(&index, &wanted)?;
    if !is_allowed_catalog_url(&pkg_url) {
        return None;
    }
    let bytes = http_get_bytes(&pkg_url)?;
    if bytes.len() < 4 || &bytes[..4] != b"\0asm" {
        return None;
    }
    let dir = modules_dir();
    let _ = fs::create_dir_all(&dir);
    let dest = dir.join(format!("{wanted}.wasm"));
    fs::write(&dest, bytes).ok()?;
    dest.is_file().then_some(dest)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CatalogPackage {
    pub name: String,
    pub version: String,
    pub summary: String,
}

pub fn list_local_modules() -> Vec<PathBuf> {
    let dir = modules_dir();
    let Ok(entries) = fs::read_dir(&dir) else {
        return Vec::new();
    };
    let mut out: Vec<PathBuf> = entries
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| {
            p.is_file()
                && p.extension()
                    .and_then(|e| e.to_str())
                    .is_some_and(|e| e.eq_ignore_ascii_case("wasm"))
        })
        .collect();
    out.sort();
    out
}

pub fn search_catalog(query: &str) -> Result<Vec<CatalogPackage>, String> {
    if !is_allowed_catalog_url(CATALOG_INDEX) {
        return Err("Wasm catalog only. Refusing a non /wasm/v1 URL.".into());
    }
    let index = http_get(CATALOG_INDEX).ok_or_else(|| "Wasm catalog fetch failed".to_string())?;
    let q = query.trim().to_ascii_lowercase();
    Ok(parse_catalog_packages(&index)
        .into_iter()
        .filter(|pkg| {
            q.is_empty()
                || pkg.name.to_ascii_lowercase().contains(&q)
                || pkg.summary.to_ascii_lowercase().contains(&q)
        })
        .collect())
}

fn extract_json_str(window: &str, key: &str) -> Option<String> {
    let needle = format!("\"{key}\":\"");
    let start = window.find(&needle)? + needle.len();
    let end = window[start..].find('"')?;
    Some(window[start..start + end].to_string())
}

fn parse_catalog_packages(index_json: &str) -> Vec<CatalogPackage> {
    let compact: String = index_json.chars().filter(|c| !c.is_whitespace()).collect();
    let mut out = Vec::new();
    let mut rest = compact.as_str();
    while let Some(i) = rest.find("\"name\":\"") {
        rest = &rest[i + 8..];
        let end = rest.find('"').unwrap_or(0);
        let name = rest[..end].to_string();
        let window = &rest[..rest.len().min(800)];
        let version = extract_json_str(window, "version").unwrap_or_default();
        let summary = extract_json_str(window, "summary").unwrap_or_default();
        if !name.is_empty() {
            out.push(CatalogPackage {
                name,
                version,
                summary,
            });
        }
        rest = &rest[end..];
    }
    out
}

fn catalog_url_for_name(index_json: &str, name: &str) -> Option<String> {
    // Tiny scan: look for "name":"<name>" then a nearby "url".
    let needle = format!("\"name\":\"{name}\"");
    let lower = index_json.replace(' ', "");
    let start = lower.find(&needle.replace(' ', ""))?;
    let window = &lower[start..lower.len().min(start + 800)];
    let url_key = "\"url\":\"";
    let u = window.find(url_key)? + url_key.len();
    let end = window[u..].find('"')?;
    let rel = &window[u..u + end];
    if rel.starts_with("https://") || rel.starts_with("http://") {
        Some(rel.to_string())
    } else {
        Some(format!("{}/{}", CATALOG_BASE, rel.trim_start_matches('/')))
    }
}

fn http_get(url: &str) -> Option<String> {
    String::from_utf8(http_get_bytes(url)?).ok()
}

fn http_get_bytes(url: &str) -> Option<Vec<u8>> {
    let out = Command::new("curl")
        .args(["-fsSL", "--max-time", "30", url])
        .output()
        .ok()?;
    out.status.success().then_some(out.stdout)
}

/// Shell command for Start. Same argv as `wasm hello-wasi-gui` in zsh.
/// `wpm install <name>` downloads `/wasm/v1` first, then runs `wasm <file|name>`.
pub fn effective_wasm_command(profile: &MachineProfile) -> String {
    let ov = &profile.runtime_overrides;
    if let Some(path) = ov.wasm_module_path.as_deref().map(str::trim).filter(|s| !s.is_empty())
    {
        if Path::new(path).is_file() {
            return format!("wasm {}", shell_quote(path));
        }
    }
    if let Some(pkg) = ov.wasm_package.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
        let name = normalize_alias(pkg);
        if let Some(file) = ensure_package_file(&name) {
            return format!("wasm {}", shell_quote(&file.to_string_lossy()));
        }
        return format!("wasm {}", shell_quote(&name));
    }
    let cmd = ov
        .wasm_command
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .unwrap_or(DEFAULT_COMMAND);
    let arg = wasm_arg_from_command(cmd);
    if command_requests_install(cmd) || !Path::new(&arg).is_file() {
        if let Some(file) = ensure_package_file(&arg) {
            return format!("wasm {}", shell_quote(&file.to_string_lossy()));
        }
    }
    if cmd.starts_with("wasm ") && Path::new(&arg).is_file() {
        return cmd.to_string();
    }
    format!("wasm {}", shell_quote(&arg))
}

fn shell_quote(path: &str) -> String {
    format!("'{}'", path.replace('\'', "'\\''"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_native_shell_commands() {
        assert_eq!(wasm_arg_from_command("wasm hello-wasi-gui"), "hello-wasi-gui");
        assert_eq!(wasm_arg_from_command("wasm wasi-hello-gui"), "hello-wasi-gui");
        assert_eq!(
            wasm_arg_from_command("wpm install hello-wasi-gui"),
            "hello-wasi-gui"
        );
        assert_eq!(wasm_arg_from_command(""), "hello-wasi-gui");
        assert_eq!(wasm_arg_from_command("./foo.wasm"), "./foo.wasm");
        assert!(command_requests_install("wpm install hello-wasi-gui"));
        assert!(!command_requests_install("wasm hello-wasi-gui"));
        assert!(is_allowed_catalog_url(CATALOG_INDEX));
        assert!(!is_allowed_catalog_url("https://repo.wawona.io/jailbreak/"));
        assert!(!is_allowed_catalog_url("https://repo.wawona.io/Packages"));
    }

    #[test]
    fn catalog_url_scan() {
        let json = r#"{"packages":[{"name":"hello-wasi-gui","version":"1","digest":"x","url":"hello-wasi-gui.wasm"}]}"#;
        assert_eq!(
            catalog_url_for_name(json, "hello-wasi-gui").as_deref(),
            Some("https://repo.wawona.io/wasm/v1/hello-wasi-gui.wasm")
        );
        let pkgs = parse_catalog_packages(json);
        assert_eq!(pkgs.len(), 1);
        assert_eq!(pkgs[0].name, "hello-wasi-gui");
    }
}
