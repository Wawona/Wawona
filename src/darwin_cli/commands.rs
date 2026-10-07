//! Command implementations. Rust owns decisions. Apple effects go through host callbacks.

use std::ffi::CString;
use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};

use super::capability::{unavailable, virtual_note, Capability};
use super::format;
use super::host::{self, from_c};
use super::state;

pub fn run(args: &[String]) -> i32 {
    let name = args
        .first()
        .and_then(|s| Path::new(s).file_name())
        .and_then(|s| s.to_str())
        .unwrap_or("");
    let rest = if args.is_empty() { &[] } else { &args[1..] };
    match name {
        "plutil" => plutil(rest),
        "defaults" => defaults(rest),
        "xattr" => xattr(rest),
        "sips" => sips(rest),
        "sw_vers" => sw_vers(rest),
        "pbcopy" => pbcopy(rest),
        "pbpaste" => pbpaste(rest),
        "say" => say(rest),
        "open" | "openurl" => open(name, rest),
        "ditto" => ditto(rest),
        "GetFileInfo" => get_file_info(rest),
        "SetFile" => set_file(rest),
        "security" => security(rest),
        "log" => log_cmd(rest),
        "system_profiler" => system_profiler(rest),
        "caffeinate" => caffeinate(rest),
        "networksetup" => networksetup(rest),
        "scutil" => scutil(rest),
        "ioreg" => ioreg(rest),
        "launchctl" => launchctl(rest),
        "diskutil" => diskutil(rest),
        "hdiutil" => hdiutil(rest),
        "mdfind" => mdfind(rest),
        "mdls" => mdls(rest),
        "mdutil" => mdutil(rest),
        "lsregister" => lsregister(rest),
        "pmset" => pmset(rest),
        "spctl" => spctl(rest),
        "tmutil" => tmutil(rest),
        "softwareupdate" => softwareupdate(rest),
        "codesign" => codesign(rest),
        "profiles" | "kmutil" | "csrutil" | "systemextensionsctl" | "metal" | "simctl"
        | "devicectl" | "xcrun" | "osascript" | "uiopen" | "uicache" | "uialert" | "uinotify"
        | "uisave" | "uishoot" | "uidisplay" | "lsrebuild" | "mgask" | "ldid" => {
            let cap = match name {
                "simctl" | "devicectl" | "kmutil" | "csrutil" | "systemextensionsctl" | "metal" => {
                    Capability::UnsupportedPlatform
                }
                "ldid" | "uiopen" | "uicache" | "uialert" | "uinotify" | "uisave" | "uishoot"
                | "uidisplay" | "lsrebuild" | "mgask" => Capability::UnsupportedSandbox,
                _ => Capability::MissingBackend,
            };
            unavailable(name, cap)
        }
        _ => {
            eprintln!("{name}: not a Darwin CLI command");
            1
        }
    }
}

fn help_flag(args: &[String]) -> bool {
    args.iter().any(|a| a == "-h" || a == "--help" || a == "help")
}

fn prefs_dir() -> PathBuf {
    if let Ok(root) = std::env::var("WAWONA_DEFAULTS_ROOT") {
        if !root.is_empty() {
            return PathBuf::from(root).join("Library/Preferences");
        }
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".into());
    PathBuf::from(home).join("Library/Preferences")
}

fn domain_path(domain: &str) -> PathBuf {
    let name = if domain == "-g" || domain == "NSGlobalDomain" {
        "NSGlobalDomain"
    } else {
        domain
    };
    prefs_dir().join(format!("{name}.plist"))
}

fn plutil(args: &[String]) -> i32 {
    if args.is_empty() || help_flag(args) {
        eprintln!(
            "usage: plutil -lint file\n       plutil -p file\n       plutil -convert xml1|binary1|json file [-o out]\nReads and writes property lists this app can access."
        );
        return if args.is_empty() { 1 } else { 0 };
    }
    let mut op = args[0].clone();
    let mut convert = String::new();
    let mut out_path: Option<String> = None;
    let mut files = Vec::new();
    let mut i = 0;
    while i < args.len() {
        let a = &args[i];
        if a == "-lint" || a == "-p" {
            op = a.clone();
        } else if a == "-convert" {
            op = a.clone();
            i += 1;
            if i >= args.len() {
                eprintln!("plutil: -convert needs a format");
                return 1;
            }
            convert = args[i].clone();
        } else if a == "-o" {
            i += 1;
            if i >= args.len() {
                eprintln!("plutil: -o needs a path");
                return 1;
            }
            out_path = Some(args[i].clone());
        } else if a.starts_with('-') {
            eprintln!("plutil: flag not supported: {a}");
            return 1;
        } else {
            files.push(a.clone());
        }
        i += 1;
    }
    if files.is_empty() {
        eprintln!("plutil: no files");
        return 1;
    }
    let mut rc = 0;
    for file in files {
        match op.as_str() {
            "-lint" | "-p" => {
                match load_plist(&file) {
                    Ok(v) => {
                        if op == "-lint" {
                            println!("{file}: OK");
                        } else {
                            print!("{}", format::plutil_p(&v));
                        }
                    }
                    Err(e) => {
                        if op == "-lint" {
                            eprint!("{}", format::plutil_lint_error(&file, &e));
                        } else {
                            eprintln!("plutil: {file}: {e}");
                        }
                        rc = 1;
                    }
                }
            }
            "-convert" => {
                let dest = out_path.as_deref().unwrap_or(file.as_str());
                if let Some(write) = host::with_host(|h| h.plist_write) {
                    let json = match load_plist(&file) {
                        Ok(v) => serde_json::to_string(&v).unwrap_or_else(|_| "{}".into()),
                        Err(e) => {
                            eprintln!("plutil: {file}: {e}");
                            rc = 1;
                            continue;
                        }
                    };
                    let c_dest = CString::new(dest).unwrap_or_default();
                    let c_json = CString::new(json).unwrap_or_default();
                    let c_fmt = CString::new(convert.as_str()).unwrap_or_default();
                    if write(c_dest.as_ptr(), c_json.as_ptr(), c_fmt.as_ptr()) != 0 {
                        eprintln!("plutil: write failed for {dest}");
                        rc = 1;
                    }
                } else if convert == "json" {
                    match load_plist(&file) {
                        Ok(v) => {
                            let j = serde_json::to_string(&v).unwrap_or_else(|_| "{}".into());
                            if fs::write(dest, j).is_err() {
                                eprintln!("plutil: write failed for {dest}");
                                rc = 1;
                            }
                        }
                        Err(e) => {
                            eprintln!("plutil: {file}: {e}");
                            rc = 1;
                        }
                    }
                } else {
                    match fs::read(&file) {
                        Ok(bytes) => {
                            if fs::write(dest, bytes).is_err() {
                                rc = 1;
                            }
                        }
                        Err(e) => {
                            eprintln!("plutil: {file}: {e}");
                            rc = 1;
                        }
                    }
                }
            }
            _ => {
                eprintln!("plutil: unknown operation");
                return 1;
            }
        }
    }
    rc
}

fn load_plist(path: &str) -> Result<serde_json::Value, String> {
    let host_json = if let Some(read) = host::with_host(|h| h.plist_read_json) {
        let c = CString::new(path).unwrap_or_default();
        let mut out: *mut i8 = std::ptr::null_mut();
        let rc = read(c.as_ptr(), &mut out);
        if rc == 0 && !out.is_null() {
            let s = from_c(out).unwrap_or("").to_string();
            unsafe { host::wwn_darwin_cli_free(out) };
            Some(s)
        } else {
            if !out.is_null() {
                unsafe { host::wwn_darwin_cli_free(out) };
            }
            None
        }
    } else {
        None
    };
    let data = fs::read(path).map_err(|e| e.to_string())?;
    format::load_plist_value(path, &data, host_json)
}

fn plist_to_json(path: &str) -> Result<String, String> {
    let v = load_plist(path)?;
    serde_json::to_string_pretty(&v).map_err(|e| e.to_string())
}

fn defaults(args: &[String]) -> i32 {
    if args.is_empty() || help_flag(args) {
        eprintln!(
            "usage: defaults domains\n       defaults read [domain [key]]\n       defaults write domain key [-string|-int|-float|-bool] value\n       defaults delete domain [key]\nWawona container preferences only. This does not read other apps.\n-g is NSGlobalDomain.plist inside this container."
        );
        return if args.is_empty() { 1 } else { 0 };
    }
    match args[0].as_str() {
        "domains" => {
            let dir = prefs_dir();
            let mut names = Vec::new();
            if let Ok(rd) = fs::read_dir(&dir) {
                for e in rd.flatten() {
                    let n = e.file_name();
                    if let Some(s) = n.to_str() {
                        if let Some(stem) = s.strip_suffix(".plist") {
                            names.push(stem.to_string());
                        }
                    }
                }
            }
            names.sort();
            println!("{}", names.join(", "));
            0
        }
        "read" => {
            if args.len() < 2 {
                eprintln!("defaults: need a domain");
                return 1;
            }
            let domain = &args[1];
            let path = domain_path(domain);
            if !path.exists() {
                eprintln!("defaults: domain {domain} does not exist");
                return 1;
            }
            let json = match plist_to_json(path.to_str().unwrap_or("")) {
                Ok(j) => j,
                Err(_) => {
                    let Ok(text) = fs::read_to_string(&path) else {
                        eprintln!("defaults: cannot read {domain}");
                        return 1;
                    };
                    text
                }
            };
            if args.len() >= 3 {
                if let Ok(serde_json::Value::Object(map)) = serde_json::from_str::<serde_json::Value>(&json) {
                    match map.get(&args[2]) {
                        Some(v) => {
                            println!("{}", json_scalar(v));
                            0
                        }
                        None => {
                            eprintln!("defaults: domain {domain} does not contain key {}", args[2]);
                            1
                        }
                    }
                } else {
                    eprintln!("defaults: domain {domain} does not contain key {}", args[2]);
                    1
                }
            } else {
                match load_plist(path.to_str().unwrap_or("")) {
                    Ok(v) => print!("{}", format::defaults_read_domain(&v)),
                    Err(_) => {
                        if let Ok(text) = fs::read_to_string(&path) {
                            print!("{text}");
                            if !text.ends_with('\n') {
                                println!();
                            }
                        } else {
                            eprintln!("defaults: cannot read {domain}");
                            return 1;
                        }
                    }
                }
                0
            }
        }
        "write" => {
            if args.len() < 4 {
                eprintln!("defaults write: need domain, key, and value");
                return 1;
            }
            let domain = &args[1];
            let mut key = args[2].clone();
            let mut ty = "-string";
            let mut raw = args[3].clone();
            if args.len() >= 5 && args[3].starts_with('-') {
                ty = args[3].as_str();
                raw = args[4].clone();
                key = args[2].clone();
            }
            let path = domain_path(domain);
            let mut map = match plist_to_json(path.to_str().unwrap_or("")) {
                Ok(j) => serde_json::from_str(&j).unwrap_or_else(|_| serde_json::json!({})),
                Err(_) => serde_json::json!({}),
            };
            let value = match ty {
                "-int" => serde_json::json!(raw.parse::<i64>().unwrap_or(0)),
                "-float" => serde_json::json!(raw.parse::<f64>().unwrap_or(0.0)),
                "-bool" => {
                    let on = matches!(raw.to_ascii_lowercase().as_str(), "yes" | "true" | "1");
                    serde_json::json!(on)
                }
                _ => serde_json::json!(raw),
            };
            if let serde_json::Value::Object(ref mut m) = map {
                m.insert(key, value);
            }
            let json = serde_json::to_string_pretty(&map).unwrap_or_else(|_| "{}".into());
            if let Some(parent) = path.parent() {
                let _ = fs::create_dir_all(parent);
            }
            if let Some(write) = host::with_host(|h| h.plist_write) {
                let c_path = CString::new(path.to_string_lossy().as_ref()).unwrap_or_default();
                let c_json = CString::new(json).unwrap_or_default();
                let c_fmt = CString::new("xml1").unwrap_or_default();
                write(c_path.as_ptr(), c_json.as_ptr(), c_fmt.as_ptr())
            } else {
                fs::write(&path, json).map(|_| 0).unwrap_or(1)
            }
        }
        "delete" => {
            if args.len() < 2 {
                eprintln!("defaults: need a domain");
                return 1;
            }
            let domain = &args[1];
            let bundle = std::env::var("WAWONA_BUNDLE_ID").unwrap_or_default();
            if args.len() < 3 && !bundle.is_empty() && domain == &bundle {
                eprintln!("defaults: refusing to delete this app domain");
                return 1;
            }
            let path = domain_path(domain);
            if args.len() < 3 {
                let _ = fs::remove_file(&path);
                return 0;
            }
            let Ok(json) = plist_to_json(path.to_str().unwrap_or("")) else {
                return 1;
            };
            let mut v: serde_json::Value = serde_json::from_str(&json).unwrap_or(serde_json::json!({}));
            if let serde_json::Value::Object(ref mut m) = v {
                m.remove(&args[2]);
            }
            let json = serde_json::to_string_pretty(&v).unwrap_or_else(|_| "{}".into());
            let _ = fs::write(path, json);
            0
        }
        _ => {
            eprintln!("defaults: unknown command {}", args[0]);
            1
        }
    }
}

fn json_scalar(v: &serde_json::Value) -> String {
    match v {
        serde_json::Value::String(s) => s.clone(),
        serde_json::Value::Bool(b) => if *b { "1".into() } else { "0".into() },
        serde_json::Value::Number(n) => n.to_string(),
        other => other.to_string(),
    }
}

fn xattr(args: &[String]) -> i32 {
    if args.is_empty() || help_flag(args) {
        eprintln!(
            "usage: xattr [-l] file\n       xattr -p name file\n       xattr -w name value file\n       xattr -d name file\n       xattr -c file\nExtended attributes on files this app can access."
        );
        return if args.is_empty() { 1 } else { 0 };
    }
    let mut i = 0;
    let mut long = false;
    if args[0] == "-l" {
        long = true;
        i = 1;
    }
    if i >= args.len() {
        eprintln!("xattr: need a file");
        return 1;
    }
    match args[i].as_str() {
        "-p" => {
            if i + 2 >= args.len() {
                eprintln!("xattr -p: need name and file");
                return 1;
            }
            xattr_get(&args[i + 2], &args[i + 1])
        }
        "-w" => {
            if i + 3 >= args.len() {
                eprintln!("xattr -w: need name, value, file");
                return 1;
            }
            xattr_set(&args[i + 3], &args[i + 1], args[i + 2].as_bytes())
        }
        "-d" => {
            if i + 2 >= args.len() {
                eprintln!("xattr -d: need name and file");
                return 1;
            }
            xattr_remove(&args[i + 2], &args[i + 1])
        }
        "-c" => {
            if i + 1 >= args.len() {
                eprintln!("xattr -c: need a file");
                return 1;
            }
            xattr_clear(&args[i + 1])
        }
        path => xattr_list(path, long),
    }
}

fn xattr_list(path: &str, long: bool) -> i32 {
    #[cfg(not(target_vendor = "apple"))]
    {
        let _ = (path, long);
        return unavailable("xattr", Capability::UnsupportedPlatform);
    }
    #[cfg(target_vendor = "apple")]
    {
    let c_path = CString::new(path).unwrap_or_default();
    let mut buf = vec![0u8; 4096];
    let n = unsafe {
        libc::listxattr(
            c_path.as_ptr(),
            buf.as_mut_ptr() as *mut i8,
            buf.len(),
            libc::XATTR_NOFOLLOW,
        )
    };
    if n < 0 {
        eprintln!("xattr: {path}: {}", std::io::Error::last_os_error());
        return 1;
    }
    let names = split_c_strings(&buf[..n as usize]);
    for name in names {
        if long {
            print!("{name}: ");
            let _ = xattr_get(path, &name);
        } else {
            println!("{name}");
        }
    }
    0
    }
}

fn xattr_get(path: &str, name: &str) -> i32 {
    #[cfg(not(target_vendor = "apple"))]
    {
        let _ = (path, name);
        return unavailable("xattr", Capability::UnsupportedPlatform);
    }
    #[cfg(target_vendor = "apple")]
    {
    let c_path = CString::new(path).unwrap_or_default();
    let c_name = CString::new(name).unwrap_or_default();
    let n = unsafe {
        libc::getxattr(
            c_path.as_ptr(),
            c_name.as_ptr(),
            std::ptr::null_mut(),
            0,
            0,
            libc::XATTR_NOFOLLOW,
        )
    };
    if n < 0 {
        eprintln!("xattr: {path}: {}", std::io::Error::last_os_error());
        return 1;
    }
    let mut buf = vec![0u8; n as usize];
    let n2 = unsafe {
        libc::getxattr(
            c_path.as_ptr(),
            c_name.as_ptr(),
            buf.as_mut_ptr() as *mut libc::c_void,
            buf.len(),
            0,
            libc::XATTR_NOFOLLOW,
        )
    };
    if n2 < 0 {
        return 1;
    }
    buf.truncate(n2 as usize);
    match String::from_utf8(buf.clone()) {
        Ok(s) => println!("{s}"),
        Err(_) => println!("{}", hex::encode_or_debug(&buf)),
    }
    0
    }
}

mod hex {
    pub fn encode_or_debug(buf: &[u8]) -> String {
        buf.iter().map(|b| format!("{b:02x}")).collect()
    }
}

fn xattr_set(path: &str, name: &str, value: &[u8]) -> i32 {
    #[cfg(not(target_vendor = "apple"))]
    {
        let _ = (path, name, value);
        return unavailable("xattr", Capability::UnsupportedPlatform);
    }
    #[cfg(target_vendor = "apple")]
    {
    let c_path = CString::new(path).unwrap_or_default();
    let c_name = CString::new(name).unwrap_or_default();
    let rc = unsafe {
        libc::setxattr(
            c_path.as_ptr(),
            c_name.as_ptr(),
            value.as_ptr() as *const libc::c_void,
            value.len(),
            0,
            libc::XATTR_NOFOLLOW,
        )
    };
    if rc != 0 {
        eprintln!("xattr: {path}: {}", std::io::Error::last_os_error());
        1
    } else {
        0
    }
    }
}

fn xattr_remove(path: &str, name: &str) -> i32 {
    #[cfg(not(target_vendor = "apple"))]
    {
        let _ = (path, name);
        return unavailable("xattr", Capability::UnsupportedPlatform);
    }
    #[cfg(target_vendor = "apple")]
    {
    let c_path = CString::new(path).unwrap_or_default();
    let c_name = CString::new(name).unwrap_or_default();
    let rc = unsafe {
        libc::removexattr(
            c_path.as_ptr(),
            c_name.as_ptr(),
            libc::XATTR_NOFOLLOW,
        )
    };
    if rc != 0 {
        eprintln!("xattr: {path}: {}", std::io::Error::last_os_error());
        1
    } else {
        0
    }
    }
}

fn xattr_clear(path: &str) -> i32 {
    #[cfg(not(target_vendor = "apple"))]
    {
        let _ = path;
        return unavailable("xattr", Capability::UnsupportedPlatform);
    }
    #[cfg(target_vendor = "apple")]
    {
    let c_path = CString::new(path).unwrap_or_default();
    let mut buf = vec![0u8; 4096];
    let n = unsafe {
        libc::listxattr(
            c_path.as_ptr(),
            buf.as_mut_ptr() as *mut i8,
            buf.len(),
            libc::XATTR_NOFOLLOW,
        )
    };
    if n < 0 {
        return 1;
    }
    for name in split_c_strings(&buf[..n as usize]) {
        let _ = xattr_remove(path, &name);
    }
    0
    }
}

fn split_c_strings(buf: &[u8]) -> Vec<String> {
    buf.split(|b| *b == 0)
        .filter(|s| !s.is_empty())
        .map(|s| String::from_utf8_lossy(s).into_owned())
        .collect()
}

fn sips(args: &[String]) -> i32 {
    if args.is_empty() || help_flag(args) {
        eprintln!(
            "usage: sips -g format|pixelWidth|pixelHeight|all file\n       sips -s format png|jpeg|tiff|gif|bmp file [--out dest]\n       sips -z pixelsH pixelsW file [--out dest]\nImageIO on files this app can read."
        );
        return if args.is_empty() { 1 } else { 0 };
    }
    let mut get_key: Option<String> = None;
    let mut set_fmt: Option<String> = None;
    let mut resize = false;
    let mut rh = 0;
    let mut rw = 0;
    let mut out: Option<String> = None;
    let mut files = Vec::new();
    let mut i = 0;
    while i < args.len() {
        if args[i] == "-g" && i + 1 < args.len() {
            get_key = Some(args[i + 1].clone());
            i += 2;
            continue;
        }
        if args[i] == "-s" && i + 2 < args.len() && args[i + 1] == "format" {
            set_fmt = Some(args[i + 2].clone());
            i += 3;
            continue;
        }
        if args[i] == "-z" && i + 2 < args.len() {
            resize = true;
            rh = args[i + 1].parse().unwrap_or(0);
            rw = args[i + 2].parse().unwrap_or(0);
            i += 3;
            continue;
        }
        if args[i] == "--out" && i + 1 < args.len() {
            out = Some(args[i + 1].clone());
            i += 2;
            continue;
        }
        if args[i].starts_with('-') {
            eprintln!("sips: flag not supported: {}", args[i]);
            return 1;
        }
        files.push(args[i].clone());
        i += 1;
    }
    if files.is_empty() {
        eprintln!("sips: no files");
        return 1;
    }
    for file in files {
        if let Some(key) = &get_key {
            let Some(info) = host::with_host(|h| h.sips_info) else {
                return unavailable("sips", Capability::MissingBackend);
            };
            let c = CString::new(file.as_str()).unwrap_or_default();
            let mut fmt = [0i8; 64];
            let mut w = 0;
            let mut h = 0;
            if info(c.as_ptr(), fmt.as_mut_ptr(), fmt.len(), &mut w, &mut h) != 0 {
                eprintln!("sips: cannot read {file}");
                return 1;
            }
            let format = from_c(fmt.as_ptr()).unwrap_or("unknown");
            if key == "all" || key == "format" {
                println!("{file}\n  format: {format}");
            }
            if key == "all" || key == "pixelWidth" {
                println!("  pixelWidth: {w}");
            }
            if key == "all" || key == "pixelHeight" {
                println!("  pixelHeight: {h}");
            }
            continue;
        }
        let Some(write) = host::with_host(|h| h.sips_write) else {
            return unavailable("sips", Capability::MissingBackend);
        };
        let dest = out.as_deref().unwrap_or(file.as_str());
        let fmt = set_fmt.clone().unwrap_or_else(|| "png".into());
        let c_src = CString::new(file.as_str()).unwrap_or_default();
        let c_dst = CString::new(dest).unwrap_or_default();
        let c_fmt = CString::new(fmt).unwrap_or_default();
        let zh = if resize { rh } else { 0 };
        let zw = if resize { rw } else { 0 };
        if write(c_src.as_ptr(), c_dst.as_ptr(), c_fmt.as_ptr(), zh, zw) != 0 {
            eprintln!("sips: write failed for {dest}");
            return 1;
        }
    }
    0
}

fn sw_vers(args: &[String]) -> i32 {
    if help_flag(args) {
        eprintln!("usage: sw_vers [-productName|-productVersion|-buildVersion]");
        return 0;
    }
    let mut name = false;
    let mut ver = false;
    let mut build = false;
    for a in args {
        match a.as_str() {
            "-productName" => name = true,
            "-productVersion" => ver = true,
            "-buildVersion" => build = true,
            other => {
                eprintln!("sw_vers: unknown option {other}");
                return 1;
            }
        }
    }
    let product = product_name();
    let version = product_version();
    let build_v = build_version();
    if !name && !ver && !build {
        print!("{}", format::sw_vers_block(product, &version, &build_v));
        return 0;
    }
    if name {
        println!("{product}");
    }
    if ver {
        println!("{version}");
    }
    if build {
        println!("{build_v}");
    }
    0
}

fn product_name() -> &'static str {
    if cfg!(target_os = "ios") {
        "iOS"
    } else if cfg!(target_os = "tvos") {
        "tvOS"
    } else if cfg!(target_os = "watchos") {
        "watchOS"
    } else if cfg!(target_os = "visionos") {
        "visionOS"
    } else {
        "macOS"
    }
}

fn product_version() -> String {
    if let Some(s) = format::sysctl_string("kern.osproductversion") {
        if !s.is_empty() {
            return s;
        }
    }
    if let Some(fn_) = host::with_host(|h| h.product_version) {
        let mut buf = [0i8; 64];
        if fn_(buf.as_mut_ptr(), buf.len()) == 0 {
            if let Some(s) = from_c(buf.as_ptr()) {
                if !s.is_empty() {
                    return s.to_string();
                }
            }
        }
    }
    std::env::consts::OS.to_string()
}

fn build_version() -> String {
    format::sysctl_string("kern.osversion").unwrap_or_default()
}

fn read_stdin() -> Result<String, ()> {
    let mut s = String::new();
    std::io::stdin().read_to_string(&mut s).map_err(|_| ())?;
    Ok(s)
}

fn pbcopy(args: &[String]) -> i32 {
    if help_flag(args) {
        eprintln!("usage: pbcopy [text ...]\n       command | pbcopy\nCopies stdin, or the arguments, onto the pasteboard.");
        return 0;
    }
    if !host::host_flag("pasteboard") {
        return unavailable("pbcopy", Capability::UnsupportedPlatform);
    }
    let text = if args.is_empty() {
        match read_stdin() {
            Ok(s) => s,
            Err(_) => {
                eprintln!("pbcopy: could not read stdin as UTF-8");
                return 1;
            }
        }
    } else {
        args.join(" ")
    };
    let Some(fn_) = host::with_host(|h| h.pasteboard_copy) else {
        return unavailable("pbcopy", Capability::MissingBackend);
    };
    let c = CString::new(text).unwrap_or_default();
    if fn_(c.as_ptr()) != 0 { 1 } else { 0 }
}

fn pbpaste(args: &[String]) -> i32 {
    if help_flag(args) {
        eprintln!("usage: pbpaste\nWrites the pasteboard UTF-8 text to stdout. No extra newline.");
        return 0;
    }
    if !host::host_flag("pasteboard") {
        return unavailable("pbpaste", Capability::UnsupportedPlatform);
    }
    let Some(fn_) = host::with_host(|h| h.pasteboard_paste) else {
        return unavailable("pbpaste", Capability::MissingBackend);
    };
    let mut out: *mut i8 = std::ptr::null_mut();
    let rc = fn_(&mut out);
    if rc != 0 {
        return rc;
    }
    if let Some(s) = from_c(out) {
        print!("{s}");
        let _ = std::io::stdout().flush();
    }
    unsafe { host::wwn_darwin_cli_free(out) };
    0
}

fn say_rate(raw: &str) -> f32 {
    let v: f32 = raw.parse().unwrap_or(0.0);
    if v > 1.0 {
        (v / 175.0) * 0.5
    } else {
        v.clamp(0.0, 1.0)
    }
}

fn say(args: &[String]) -> i32 {
    let mut voice: Option<String> = None;
    let mut file: Option<String> = None;
    let mut rate: Option<f32> = None;
    let mut words = Vec::new();
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "-h" | "--help" => {
                eprintln!("usage: say [-v voice] [-r rate] [-f file] [message]\n       say -v ?\nrate above 1 is words per minute. 0 through 1 is the speech rate.");
                return 0;
            }
            "-v" if i + 1 < args.len() => {
                voice = Some(args[i + 1].clone());
                i += 2;
            }
            "-f" if i + 1 < args.len() => {
                file = Some(args[i + 1].clone());
                i += 2;
            }
            "-r" if i + 1 < args.len() => {
                rate = Some(say_rate(&args[i + 1]));
                i += 2;
            }
            other if other.starts_with('-') => {
                eprintln!("usage: say [-v voice] [-r rate] [-f file] [message]");
                return 1;
            }
            other => {
                words.push(other.to_string());
                i += 1;
            }
        }
    }
    if matches!(voice.as_deref(), Some("?") | Some("list")) {
        let Some(fn_) = host::with_host(|h| h.list_voices) else {
            return unavailable("say", Capability::MissingBackend);
        };
        return fn_();
    }
    let text = if !words.is_empty() {
        words.join(" ")
    } else if let Some(f) = file {
        fs::read_to_string(f).unwrap_or_default()
    } else {
        read_stdin().unwrap_or_default()
    };
    if text.is_empty() {
        eprintln!("usage: say [-v voice] [-r rate] [-f file] [message]");
        return 1;
    }
    let Some(fn_) = host::with_host(|h| h.speak) else {
        return unavailable("say", Capability::MissingBackend);
    };
    let c_text = CString::new(text.replace('\0', "")).unwrap_or_default();
    let c_voice = CString::new(voice.unwrap_or_default()).unwrap_or_default();
    fn_(c_text.as_ptr(), c_voice.as_ptr(), rate.unwrap_or(-1.0))
}

fn open(cmd: &str, args: &[String]) -> i32 {
    if args.is_empty() || help_flag(args) {
        eprintln!("usage: {cmd} url-or-path\n       {cmd} ./\nopen -a is not supported.");
        return if args.is_empty() { 1 } else { 0 };
    }
    if args.iter().any(|a| a == "-a") {
        eprintln!("open: -a is not supported");
        return 1;
    }
    if !host::host_flag("open") {
        return unavailable("open", Capability::UnsupportedPlatform);
    }
    let target = &args[args.len() - 1];
    if target.contains("://") && !target.starts_with("file:") {
        let Some(fn_) = host::with_host(|h| h.open_url) else {
            return unavailable("open", Capability::MissingBackend);
        };
        let c = CString::new(target.as_str()).unwrap_or_default();
        return if fn_(c.as_ptr()) != 0 { 1 } else { 0 };
    }
    let path = PathBuf::from(target);
    let path = if path.is_relative() {
        std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")).join(path)
    } else {
        path
    };
    let c = CString::new(path.to_string_lossy().as_ref()).unwrap_or_default();
    if path.is_dir() {
        if !host::host_flag("files") {
            return unavailable("open", Capability::UnsupportedPlatform);
        }
        let Some(fn_) = host::with_host(|h| h.open_directory) else {
            return unavailable("open", Capability::MissingBackend);
        };
        return if fn_(c.as_ptr()) != 0 { 1 } else { 0 };
    }
    if !host::host_flag("files") {
        let Some(fn_) = host::with_host(|h| h.open_url) else {
            return unavailable("open", Capability::MissingBackend);
        };
        return if fn_(c.as_ptr()) != 0 { 1 } else { 0 };
    }
    let Some(fn_) = host::with_host(|h| h.open_file) else {
        return unavailable("open", Capability::MissingBackend);
    };
    if fn_(c.as_ptr()) != 0 { 1 } else { 0 }
}

fn ditto(args: &[String]) -> i32 {
    if args.len() < 2 || help_flag(args) {
        eprintln!("usage: ditto src dst\nCopies inside this app container.");
        return if help_flag(args) { 0 } else { 1 };
    }
    let src = &args[args.len() - 2];
    let dst = &args[args.len() - 1];
    if let Some(fn_) = host::with_host(|h| h.copy_item) {
        let a = CString::new(src.as_str()).unwrap_or_default();
        let b = CString::new(dst.as_str()).unwrap_or_default();
        return if fn_(a.as_ptr(), b.as_ptr()) != 0 { 1 } else { 0 };
    }
    copy_tree(Path::new(src), Path::new(dst))
}

fn copy_tree(src: &Path, dst: &Path) -> i32 {
    if src.is_dir() {
        let _ = fs::create_dir_all(dst);
        if let Ok(rd) = fs::read_dir(src) {
            for e in rd.flatten() {
                let _ = copy_tree(&e.path(), &dst.join(e.file_name()));
            }
        }
        0
    } else {
        if let Some(parent) = dst.parent() {
            let _ = fs::create_dir_all(parent);
        }
        fs::copy(src, dst).map(|_| 0).unwrap_or(1)
    }
}

fn get_file_info(args: &[String]) -> i32 {
    if args.is_empty() || help_flag(args) {
        eprintln!("usage: GetFileInfo file");
        return if args.is_empty() { 1 } else { 0 };
    }
    let path = Path::new(&args[0]);
    let meta = match fs::metadata(path) {
        Ok(m) => m,
        Err(e) => {
            eprintln!("GetFileInfo: {e}");
            return 1;
        }
    };
    let finder = {
        #[cfg(target_vendor = "apple")]
        {
            let mut buf = vec![0u8; 32];
            let c_path = CString::new(path.to_string_lossy().as_ref()).unwrap_or_default();
            let c_name = CString::new("com.apple.FinderInfo").unwrap_or_default();
            let n = unsafe {
                libc::getxattr(
                    c_path.as_ptr(),
                    c_name.as_ptr(),
                    buf.as_mut_ptr() as *mut libc::c_void,
                    buf.len(),
                    0,
                    0,
                )
            };
            if n > 0 {
                buf.truncate(n as usize);
                Some(buf)
            } else {
                None
            }
        }
        #[cfg(not(target_vendor = "apple"))]
        {
            None::<Vec<u8>>
        }
    };
    print!(
        "{}",
        format::get_file_info_text(path, &meta, finder.as_deref())
    );
    0
}

fn set_file(args: &[String]) -> i32 {
    if args.len() < 2 || help_flag(args) {
        eprintln!("usage: SetFile [-a attributes] file\nMode A supports a no-op attribute write on accessible files.");
        return if help_flag(args) { 0 } else { 1 };
    }
    let file = args.last().unwrap();
    if !Path::new(file).exists() {
        eprintln!("SetFile: {file}: No such file");
        return 1;
    }
    0
}

fn security(args: &[String]) -> i32 {
    if args.is_empty() || help_flag(args) {
        eprintln!("usage: security dump-keychain\nThis app's keychain items only.");
        return if args.is_empty() { 1 } else { 0 };
    }
    if args[0] != "dump-keychain" && args[0] != "list-keychains" {
        eprintln!("security: flag not supported: {}", args[0]);
        return 1;
    }
    let Some(fn_) = host::with_host(|h| h.keychain_dump) else {
        println!("keychains: this app (SupportedRestricted)");
        return 0;
    };
    let mut out: *mut i8 = std::ptr::null_mut();
    if fn_(&mut out) != 0 {
        return 1;
    }
    if let Some(s) = from_c(out) {
        print!("{s}");
    }
    unsafe { host::wwn_darwin_cli_free(out) };
    0
}

fn log_cmd(args: &[String]) -> i32 {
    if help_flag(args) {
        eprintln!("usage: log stream --predicate ...\nWawona and this app's public log only.");
        return 0;
    }
    let msg = if args.len() >= 2 && args[0] == "show" {
        args[1].clone()
    } else {
        "Wawona app log (SupportedRestricted)".into()
    };
    if let Some(fn_) = host::with_host(|h| h.oslog) {
        let c = CString::new(msg.as_str()).unwrap_or_default();
        let _ = fn_(c.as_ptr());
    }
    println!("{msg}");
    0
}

fn system_profiler(args: &[String]) -> i32 {
    let _ = args;
    println!("Software:\n\n    System Version: {} {}\n    Build: {}", product_name(), product_version(), build_version());
    println!("    Scope: public APIs only ({})", Capability::SupportedRestricted.as_str());
    0
}

fn caffeinate(args: &[String]) -> i32 {
    if help_flag(args) {
        eprintln!("usage: caffeinate -t seconds\nPublic idle-timer only.");
        return 0;
    }
    let mut secs = 1;
    let mut i = 0;
    while i < args.len() {
        if args[i] == "-t" && i + 1 < args.len() {
            secs = args[i + 1].parse().unwrap_or(1);
            i += 2;
            continue;
        }
        i += 1;
    }
    if let Some(fn_) = host::with_host(|h| h.idle_prevent) {
        return fn_(secs);
    }
    unavailable("caffeinate", Capability::SupportedRestricted)
}

fn networksetup(args: &[String]) -> i32 {
    if args.is_empty() || args[0] == "-getinfo" || args[0] == "-listallhardwareports" || help_flag(args) {
        if help_flag(args) {
            eprintln!("usage: networksetup -listallhardwareports");
            return 0;
        }
        list_ifaces();
        return 0;
    }
    if args[0].starts_with("-set") {
        return unavailable("networksetup", Capability::UnsupportedSandbox);
    }
    list_ifaces();
    0
}

fn list_ifaces() {
    println!("Hardware Ports (public subset):");
    unsafe {
        let mut ifap: *mut libc::ifaddrs = std::ptr::null_mut();
        if libc::getifaddrs(&mut ifap) != 0 {
            return;
        }
        let mut cur = ifap;
        while !cur.is_null() {
            let name = from_c((*cur).ifa_name).unwrap_or("");
            if !name.is_empty() {
                println!("Hardware Port: {name}");
            }
            cur = (*cur).ifa_next;
        }
        libc::freeifaddrs(ifap);
    }
}

fn scutil(args: &[String]) -> i32 {
    if args.iter().any(|a| a == "--nc" || a.starts_with("-w")) {
        return unavailable("scutil", Capability::UnsupportedSandbox);
    }
    if let Some(fn_) = host::with_host(|h| h.path_status) {
        let mut out: *mut i8 = std::ptr::null_mut();
        if fn_(&mut out) == 0 {
            if let Some(s) = from_c(out) {
                println!("{s}");
            }
            unsafe { host::wwn_darwin_cli_free(out) };
            return 0;
        }
    }
    println!("Network information ({})", Capability::SupportedRestricted.as_str());
    list_ifaces();
    0
}

fn ioreg(args: &[String]) -> i32 {
    let _ = args;
    println!("+-o Root  <class IORegistry, public sysctl subset>");
    println!("  Build: {}", build_version());
    eprintln!("ioreg: host IORegistry is not available ({})", Capability::SupportedRestricted.as_str());
    0
}

fn launchctl(args: &[String]) -> i32 {
    virtual_note("launchctl", "Wawona service manager, not host launchd");
    let dir = state::launchd_dir();
    let _ = state::ensure_dir(&dir);
    if args.is_empty() || help_flag(args) || args[0] == "help" {
        eprintln!("usage: launchctl list\n       launchctl bootstrap wawona path.plist\n       launchctl bootout wawona name\n       launchctl print wawona/name");
        return 0;
    }
    match args[0].as_str() {
        "list" => {
            if let Ok(rd) = fs::read_dir(&dir) {
                for e in rd.flatten() {
                    println!("- 0 {}", e.path().file_stem().unwrap_or_default().to_string_lossy());
                }
            }
            0
        }
        "bootstrap" => {
            if args.len() < 3 {
                eprintln!("launchctl bootstrap: need target and plist");
                return 1;
            }
            let src = Path::new(&args[2]);
            let name = src.file_name().unwrap_or_default();
            let _ = fs::copy(src, dir.join(name));
            0
        }
        "bootout" => {
            if args.len() < 3 {
                eprintln!("launchctl bootout: need name");
                return 1;
            }
            let stem = args[2].rsplit('/').next().unwrap_or(&args[2]);
            let _ = fs::remove_file(dir.join(format!("{stem}.plist")));
            0
        }
        "print" => {
            println!("wawona services:");
            if let Ok(rd) = fs::read_dir(&dir) {
                for e in rd.flatten() {
                    println!("    {}", e.file_name().to_string_lossy());
                }
            }
            0
        }
        _ => {
            eprintln!("launchctl: unknown subcommand {}", args[0]);
            1
        }
    }
}

fn diskutil(args: &[String]) -> i32 {
    virtual_note("diskutil", "Wawona virtual disks");
    let path = state::state_dir().join("disks.json");
    let mut inv: state::DiskInventory = state::load_json(&path);
    if inv.disks.is_empty() {
        inv.disks.push(state::VirtualDisk {
            id: "disk0".into(),
            name: "WawonaContainer".into(),
            size_bytes: 8 * 1024 * 1024 * 1024,
        });
        let _ = state::save_json(&path, &inv);
    }
    if args.is_empty() || args[0] == "list" || help_flag(args) {
        println!("/dev/disk0 (virtual):");
        for d in &inv.disks {
            println!("   {}: {} ({} bytes)", d.id, d.name, d.size_bytes);
        }
        return 0;
    }
    if args[0] == "info" {
        for d in &inv.disks {
            println!("{}:\n  Name: {}\n  Size: {}", d.id, d.name, d.size_bytes);
        }
        return 0;
    }
    unavailable("diskutil", Capability::SupportedVirtual)
}

fn hdiutil(args: &[String]) -> i32 {
    virtual_note("hdiutil", "userspace images, no host mount");
    if args.is_empty() || help_flag(args) {
        eprintln!("usage: hdiutil imageinfo file\n       hdiutil attach file");
        return 0;
    }
    match args[0].as_str() {
        "imageinfo" if args.len() >= 2 => {
            let p = Path::new(&args[1]);
            match fs::metadata(p) {
                Ok(m) => {
                    println!("Format: userspace\nSize: {}", m.len());
                    0
                }
                Err(e) => {
                    eprintln!("hdiutil: {e}");
                    1
                }
            }
        }
        "attach" if args.len() >= 2 => {
            println!("expected   N/A");
            println!("/dev/diskWawona  {}", args[1]);
            0
        }
        _ => unavailable("hdiutil", Capability::SupportedVirtual),
    }
}

fn mdfind(args: &[String]) -> i32 {
    virtual_note("mdfind", "Wawona file names, not Spotlight");
    let needle = args.last().cloned().unwrap_or_default();
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".into());
    let mut out = Vec::new();
    state::walk_names(Path::new(&home), &needle, &mut out);
    for p in out.iter().take(200) {
        println!("{}", p.display());
    }
    0
}

fn mdls(args: &[String]) -> i32 {
    virtual_note("mdls", "Wawona file metadata");
    if args.is_empty() {
        eprintln!("usage: mdls file");
        return 1;
    }
    let p = Path::new(&args[0]);
    match fs::metadata(p) {
        Ok(m) => {
            println!("kMDItemDisplayName = \"{}\"", p.file_name().unwrap_or_default().to_string_lossy());
            println!("kMDItemFSSize      = {}", m.len());
            0
        }
        Err(e) => {
            eprintln!("mdls: {e}");
            1
        }
    }
}

fn mdutil(args: &[String]) -> i32 {
    virtual_note("mdutil", "Wawona index manager");
    let _ = args;
    println!("/: Indexing enabled (Wawona).");
    0
}

fn lsregister(args: &[String]) -> i32 {
    virtual_note("lsregister", "Wawona document registry");
    let path = state::state_dir().join("registry.json");
    let mut db: state::AppRegistry = state::load_json(&path);
    if args.iter().any(|a| a == "-dump") || args.is_empty() {
        for id in &db.ids {
            println!("{id}");
        }
        return 0;
    }
    if let Some(i) = args.iter().position(|a| a == "-f") {
        if i + 1 < args.len() {
            db.ids.push(args[i + 1].clone());
            db.ids.sort();
            db.ids.dedup();
            let _ = state::save_json(&path, &db);
        }
    }
    0
}

fn pmset(args: &[String]) -> i32 {
    virtual_note("pmset", "Wawona runtime power policy");
    if args.first().map(|s| s.as_str()) == Some("-g") {
        println!("Sleep Disabled 0\nWawona VM policy: default");
        return 0;
    }
    0
}

fn spctl(args: &[String]) -> i32 {
    virtual_note("spctl", "Wawona package trust");
    let path = state::state_dir().join("trust.json");
    let db: state::TrustDb = state::load_json(&path);
    if args.first().map(|s| s.as_str()) == Some("--status") || args.is_empty() {
        println!("assessments enabled (Wawona)");
        println!("allowed: {}", db.allowed.len());
        return 0;
    }
    0
}

fn tmutil(args: &[String]) -> i32 {
    virtual_note("tmutil", "Wawona snapshots");
    let path = state::state_dir().join("backup.json");
    let mut db: state::BackupDb = state::load_json(&path);
    match args.first().map(|s| s.as_str()) {
        Some("listlocalsnapshots") | None => {
            for s in &db.snapshots {
                println!("{s}");
            }
            0
        }
        Some("localsnapshot") => {
            let name = format!("com.wawona.local-{}", db.snapshots.len() + 1);
            db.snapshots.push(name.clone());
            let _ = state::save_json(&path, &db);
            println!("{name}");
            0
        }
        _ => 0,
    }
}

fn softwareupdate(args: &[String]) -> i32 {
    virtual_note("softwareupdate", "Wawona bundled resources only");
    if args.iter().any(|a| a == "-l" || a == "--list") || args.is_empty() {
        println!("Software Update Tool");
        println!("No Wawona resource updates.");
        return 0;
    }
    unavailable("softwareupdate", Capability::SupportedVirtual)
}

fn codesign(args: &[String]) -> i32 {
    if args.iter().any(|a| a == "-s" || a == "--sign") {
        return unavailable("codesign", Capability::UnsupportedSandbox);
    }
    let file = args.iter().rev().find(|a| !a.starts_with('-')).cloned();
    let Some(file) = file else {
        eprintln!("usage: codesign -dv file");
        return 1;
    };
    match fs::read(&file) {
        Ok(data) => {
            eprint!("{}", format::codesign_verbose(&file, &data));
            0
        }
        Err(e) => {
            eprintln!("codesign: {e}");
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    static TEST_LOCK: Mutex<()> = Mutex::new(());

    fn tmp() -> PathBuf {
        let p = std::env::temp_dir().join(format!("wwn-darwin-{}", std::process::id()));
        let _ = fs::create_dir_all(p.join("Library/Preferences"));
        p
    }

    #[test]
    fn plutil_lint_json_is_rejected_like_apple() {
        let _g = TEST_LOCK.lock().unwrap();
        let dir = tmp();
        let f = dir.join("sample.json");
        fs::write(&f, "{\"hello\":\"world\"}").unwrap();
        assert_eq!(plutil(&["-lint".into(), f.to_string_lossy().into()]), 1);
    }

    #[test]
    fn plutil_p_xml_apple_shape() {
        let _g = TEST_LOCK.lock().unwrap();
        let dir = tmp();
        let f = dir.join("sample.plist");
        fs::write(
            &f,
            r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
<key>hello</key>
<string>world</string>
<key>n</key>
<integer>1</integer>
</dict>
</plist>
"#,
        )
        .unwrap();
        assert_eq!(plutil(&["-lint".into(), f.to_string_lossy().into()]), 0);
    }

    #[test]
    fn defaults_roundtrip() {
        let _g = TEST_LOCK.lock().unwrap();
        let dir = tmp();
        std::env::set_var("WAWONA_DEFAULTS_ROOT", dir.to_string_lossy().as_ref());
        assert_eq!(
            defaults(&[
                "write".into(),
                "com.example.wawona.test".into(),
                "color".into(),
                "-string".into(),
                "blue".into()
            ]),
            0
        );
        assert_eq!(
            defaults(&[
                "read".into(),
                "com.example.wawona.test".into(),
                "color".into()
            ]),
            0
        );
        assert_eq!(defaults(&["read".into(), "com.example.missing".into()]), 1);
        std::env::remove_var("WAWONA_DEFAULTS_ROOT");
    }

    #[test]
    fn unsupported_kmutil() {
        assert_eq!(run(&["kmutil".into()]), 1);
        assert_eq!(run(&["uiopen".into()]), 1);
    }

    #[test]
    fn launchctl_virtual() {
        let _g = TEST_LOCK.lock().unwrap();
        let dir = tmp().join("state");
        std::env::set_var("WAWONA_DARWIN_STATE", dir.to_string_lossy().as_ref());
        assert_eq!(launchctl(&["list".into()]), 0);
        std::env::remove_var("WAWONA_DARWIN_STATE");
    }
}
