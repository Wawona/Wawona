//! Default nested-weston `weston.ini`. Honeycomb is upstream
//! `data/background.png`. Do not use indexed `pattern.png` as wallpaper
//! (cairo often fails to load it, then only `background-color` shows).

use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};

/// Resolve a directory that contains the honeycomb `background.png`.
/// Prefer `WESTON_DATA_DIR`, then `XDG_DATA_*` /usr share trees.
pub fn weston_data_dir() -> Option<PathBuf> {
    let mut candidates = Vec::new();
    if let Ok(dir) = std::env::var("WESTON_DATA_DIR") {
        if !dir.is_empty() {
            candidates.push(PathBuf::from(dir));
        }
    }
    if let Ok(home) = std::env::var("XDG_DATA_HOME") {
        if !home.is_empty() {
            candidates.push(PathBuf::from(home).join("weston"));
        }
    }
    if let Ok(dirs) = std::env::var("XDG_DATA_DIRS") {
        for part in dirs.split(':') {
            if !part.is_empty() {
                candidates.push(PathBuf::from(part).join("weston"));
            }
        }
    }
    candidates.push(PathBuf::from("/usr/share/weston"));
    candidates.push(PathBuf::from("/usr/local/share/weston"));
    candidates
        .into_iter()
        .find(|p| honeycomb_png(p).is_file())
}

pub fn honeycomb_png(data_dir: &Path) -> PathBuf {
    data_dir.join("background.png")
}

/// Write a weston.ini that tiles/scales the honeycomb wallpaper.
pub fn write_honeycomb_ini(
    path: &Path,
    data_dir: &Path,
    use_pixman: bool,
    shell_client: Option<&str>,
    input_method: Option<&str>,
) -> io::Result<bool> {
    let bg = honeycomb_png(data_dir);
    let icon = data_dir.join("terminal.png");
    let has_bg = bg.is_file();
    let has_icon = icon.is_file();

    let mut body = String::new();
    body.push_str("[core]\n");
    body.push_str(&format!(
        "use-pixman={}\n\n",
        if use_pixman { "true" } else { "false" }
    ));
    body.push_str("[shell]\n");
    if let Some(client) = shell_client.filter(|s| !s.is_empty()) {
        body.push_str(&format!("client={client}\n"));
    }
    if let Some(im) = input_method.filter(|s| !s.is_empty()) {
        body.push_str(&format!("input-method={im}\n"));
    }
    body.push_str("background-color=0xff1a1a2e\n");
    if has_bg {
        body.push_str(&format!("background-image={}\n", bg.display()));
        body.push_str("background-type=scale\n");
    }
    body.push_str("panel-color=0xff101010\n");
    body.push_str("panel-position=top\n");
    body.push_str("clock-format=seconds\n\n");
    body.push_str("[launcher]\n");
    if has_icon {
        body.push_str(&format!("icon={}\n", icon.display()));
    }
    body.push_str("path=weston-terminal\n\n");
    body.push_str("[terminal]\n");
    body.push_str("font=DejaVuSansM Nerd Font Mono\n");
    body.push_str("font-size=17\n");

    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let mut f = fs::File::create(path)?;
    f.write_all(body.as_bytes())?;
    f.flush()?;
    Ok(has_bg)
}

/// If `command` is the weston compositor (not weston-terminal), add `--config=`.
pub fn with_config_arg(command: &str, ini: &Path) -> String {
    let token = command
        .split_whitespace()
        .next()
        .unwrap_or(command)
        .trim();
    let base = Path::new(token)
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or(token);
    if base != "weston" {
        return command.to_string();
    }
    if command.contains("--config=") || command.contains("--config ") {
        return command.to_string();
    }
    format!("{command} --config={}", ini.display())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn with_config_arg_only_wraps_weston_compositor() {
        let ini = Path::new("/tmp/weston.ini");
        assert_eq!(
            with_config_arg("weston --backend=wayland", ini),
            "weston --backend=wayland --config=/tmp/weston.ini"
        );
        assert_eq!(
            with_config_arg("weston-terminal", ini),
            "weston-terminal"
        );
        assert_eq!(
            with_config_arg("weston --config=/x.ini", ini),
            "weston --config=/x.ini"
        );
    }

    #[test]
    fn write_ini_includes_honeycomb_when_present() {
        let tmp = std::env::temp_dir().join("wawona-weston-ini-test");
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(&tmp).unwrap();
        let bg = tmp.join("background.png");
        fs::write(&bg, b"png").unwrap();
        let ini = tmp.join("weston.ini");
        assert!(write_honeycomb_ini(&ini, &tmp, false, Some("weston-desktop-shell"), None).unwrap());
        let body = fs::read_to_string(&ini).unwrap();
        assert!(body.contains("background-image="));
        assert!(body.contains("background.png"));
        assert!(body.contains("background-type=scale"));
        assert!(!body.contains("pattern.png"));
        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn weston_data_dir_prefers_env_when_honeycomb_present() {
        let tmp = std::env::temp_dir().join("wawona-weston-data-dir-test");
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(&tmp).unwrap();
        fs::write(tmp.join("background.png"), b"png").unwrap();
        let prev = std::env::var_os("WESTON_DATA_DIR");
        std::env::set_var("WESTON_DATA_DIR", &tmp);
        let found = weston_data_dir();
        match prev {
            Some(v) => std::env::set_var("WESTON_DATA_DIR", v),
            None => std::env::remove_var("WESTON_DATA_DIR"),
        }
        assert_eq!(found.as_deref(), Some(tmp.as_path()));
        let _ = fs::remove_dir_all(&tmp);
    }
}
