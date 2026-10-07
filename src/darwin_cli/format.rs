//! Apple-shaped printers for public Darwin CLI output.
//!
//! Match host `plutil -p`, `defaults read`, `sw_vers`, and `GetFileInfo`
//! layout. Do not invent host IOKit, keychain, or launchd data.

use serde_json::{Map, Value};
use std::ffi::CString;
use std::fmt::Write;
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

pub fn sysctl_string(name: &str) -> Option<String> {
    // sysctlbyname is Darwin/BSD. Linux libc has no such symbol.
    #[cfg(any(
        target_os = "macos",
        target_os = "ios",
        target_os = "tvos",
        target_os = "watchos",
        target_os = "visionos"
    ))]
    {
        let c_name = CString::new(name).ok()?;
        let mut buf = [0u8; 256];
        let mut len = buf.len();
        let rc = unsafe {
            libc::sysctlbyname(
                c_name.as_ptr(),
                buf.as_mut_ptr() as *mut libc::c_void,
                &mut len,
                std::ptr::null_mut(),
                0,
            )
        };
        if rc != 0 || len == 0 {
            return None;
        }
        let end = if buf[len.saturating_sub(1)] == 0 {
            len - 1
        } else {
            len
        };
        Some(String::from_utf8_lossy(&buf[..end]).into_owned())
    }
    #[cfg(not(any(
        target_os = "macos",
        target_os = "ios",
        target_os = "tvos",
        target_os = "watchos",
        target_os = "visionos"
    )))]
    {
        let _ = name;
        None
    }
}

pub fn sw_vers_block(product: &str, version: &str, build: &str) -> String {
    format!("ProductName:\t\t{product}\nProductVersion:\t\t{version}\nBuildVersion:\t\t{build}\n")
}

pub fn load_plist_value(path: &str, data: &[u8], json_from_host: Option<String>) -> Result<Value, String> {
    if let Some(j) = json_from_host {
        return serde_json::from_str(&j).map_err(|e| e.to_string());
    }
    if data.starts_with(b"bplist") {
        return Err("binary plist needs the host PropertyList reader".into());
    }
    if let Ok(text) = std::str::from_utf8(data) {
        let trimmed = text.trim_start();
        if trimmed.starts_with("<?xml") || trimmed.contains("<plist") {
            return parse_xml_plist(text);
        }
        if trimmed.starts_with('{') || trimmed.starts_with('[') {
            if Path::new(path)
                .extension()
                .and_then(|e| e.to_str())
                .is_some_and(|e| e.eq_ignore_ascii_case("json"))
            {
                return Err("Unexpected character { at line 1".into());
            }
            if let Ok(v) = serde_json::from_str::<Value>(text) {
                return Ok(v);
            }
        }
    }
    Err("not a property list".into())
}

pub fn plutil_lint_error(path: &str, err: &str) -> String {
    if err.contains("Unexpected character") {
        format!("{path}: (Unexpected character {{ at line 1)\n")
    } else {
        format!("{path}: ({err})\n")
    }
}

pub fn plutil_p(value: &Value) -> String {
    let mut out = String::new();
    write_plutil_p(&mut out, value, 0);
    out.push('\n');
    out
}

fn write_plutil_p(out: &mut String, value: &Value, indent: usize) {
    let pad = "  ".repeat(indent);
    match value {
        Value::Object(map) => {
            out.push('{');
            if map.is_empty() {
                out.push('}');
                return;
            }
            out.push('\n');
            let mut keys: Vec<&String> = map.keys().collect();
            keys.sort();
            for k in keys {
                out.push_str(&pad);
                out.push_str("  ");
                out.push_str(&json_quoted(k));
                out.push_str(" => ");
                write_plutil_p(out, &map[k], indent + 1);
                out.push('\n');
            }
            out.push_str(&pad);
            out.push('}');
        }
        Value::Array(arr) => {
            out.push('[');
            if arr.is_empty() {
                out.push(']');
                return;
            }
            out.push('\n');
            for (i, v) in arr.iter().enumerate() {
                out.push_str(&pad);
                out.push_str("  ");
                out.push_str(&i.to_string());
                out.push_str(" => ");
                write_plutil_p(out, v, indent + 1);
                out.push('\n');
            }
            out.push_str(&pad);
            out.push(']');
        }
        Value::String(s) => out.push_str(&json_quoted(s)),
        Value::Number(n) => out.push_str(&n.to_string()),
        Value::Bool(true) => out.push_str("true"),
        Value::Bool(false) => out.push_str("false"),
        Value::Null => out.push_str("0"),
    }
}

fn json_quoted(s: &str) -> String {
    serde_json::to_string(s).unwrap_or_else(|_| format!("\"{s}\""))
}

pub fn defaults_read_domain(value: &Value) -> String {
    let mut out = String::new();
    write_next( &mut out, value, 0);
    if !out.ends_with('\n') {
        out.push('\n');
    }
    out
}

fn write_next(out: &mut String, value: &Value, indent: usize) {
    let pad = "    ".repeat(indent);
    match value {
        Value::Object(map) => {
            out.push_str("{\n");
            let mut keys: Vec<&String> = map.keys().collect();
            keys.sort();
            for k in keys {
                out.push_str(&"    ".repeat(indent + 1));
                out.push_str(&next_key(k));
                out.push_str(" = ");
                write_next(out, &map[k], indent + 1);
                if !out.ends_with('\n') {
                    out.push_str(";\n");
                }
            }
            out.push_str(&pad);
            out.push('}');
        }
        Value::Array(arr) => {
            out.push_str("(\n");
            for (i, v) in arr.iter().enumerate() {
                out.push_str(&"    ".repeat(indent + 1));
                write_next(out, v, indent + 1);
                if i + 1 != arr.len() {
                    out.push(',');
                }
                out.push('\n');
            }
            out.push_str(&pad);
            out.push(')');
        }
        Value::String(s) => out.push_str(&next_string(s)),
        Value::Number(n) => out.push_str(&n.to_string()),
        Value::Bool(true) => out.push('1'),
        Value::Bool(false) => out.push('0'),
        Value::Null => out.push_str("\"\""),
    }
}

fn next_key(s: &str) -> String {
    if is_unquoted_atom(s) {
        s.to_string()
    } else {
        json_quoted(s)
    }
}

fn next_string(s: &str) -> String {
    if is_unquoted_atom(s) {
        s.to_string()
    } else {
        json_quoted(s)
    }
}

fn is_unquoted_atom(s: &str) -> bool {
    !s.is_empty()
        && s.chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '.' || c == '-' || c == '$')
}

pub fn parse_xml_plist(xml: &str) -> Result<Value, String> {
    let mut p = Xml::new(xml);
    p.skip_to_plist_value()
}

struct Xml<'a> {
    s: &'a str,
    i: usize,
}

impl<'a> Xml<'a> {
    fn new(s: &'a str) -> Self {
        Self { s, i: 0 }
    }

    fn rest(&self) -> &'a str {
        &self.s[self.i..]
    }

    fn skip_ws_and_comments(&mut self) {
        loop {
            let r = self.rest().trim_start();
            self.i = self.s.len() - r.len();
            if r.starts_with("<?") {
                if let Some(e) = r.find("?>") {
                    self.i += e + 2;
                    continue;
                }
            }
            if r.starts_with("<!--") {
                if let Some(e) = r.find("-->") {
                    self.i += e + 3;
                    continue;
                }
            }
            if r.starts_with("<!DOCTYPE") {
                if let Some(e) = r.find('>') {
                    self.i += e + 1;
                    continue;
                }
            }
            break;
        }
    }

    fn skip_to_plist_value(&mut self) -> Result<Value, String> {
        self.skip_ws_and_comments();
        if self.rest().starts_with("<plist") {
            self.skip_tag()?;
        }
        self.skip_ws_and_comments();
        self.parse_value()
    }

    fn skip_tag(&mut self) -> Result<String, String> {
        self.skip_ws_and_comments();
        let r = self.rest();
        if !r.starts_with('<') {
            return Err("expected tag".into());
        }
        let end = r.find('>').ok_or("truncated tag")?;
        let tag = &r[1..end];
        self.i += end + 1;
        Ok(tag.trim().to_string())
    }

    fn parse_value(&mut self) -> Result<Value, String> {
        self.skip_ws_and_comments();
        let tag = self.skip_tag()?;
        let name = tag.trim_end_matches('/').split_whitespace().next().unwrap_or("");
        if tag.ends_with('/') || name == "true" || name == "false" {
            return match name {
                "true" => Ok(Value::Bool(true)),
                "false" => Ok(Value::Bool(false)),
                "dict" => Ok(Value::Object(Map::new())),
                "array" => Ok(Value::Array(vec![])),
                _ => Ok(Value::Null),
            };
        }
        match name {
            "dict" => self.parse_dict(),
            "array" => self.parse_array(),
            "string" | "integer" | "real" | "data" | "date" | "key" => {
                let (text, _) = self.read_until_end(name)?;
                match name {
                    "integer" => {
                        let n: i64 = text.trim().parse().unwrap_or(0);
                        Ok(Value::Number(n.into()))
                    }
                    "real" => {
                        let n: f64 = text.trim().parse().unwrap_or(0.0);
                        Ok(serde_json::Number::from_f64(n)
                            .map(Value::Number)
                            .unwrap_or(Value::from(0)))
                    }
                    _ => Ok(Value::String(unescape_xml(&text))),
                }
            }
            "true" => Ok(Value::Bool(true)),
            "false" => Ok(Value::Bool(false)),
            other => Err(format!("unknown plist tag {other}")),
        }
    }

    fn parse_dict(&mut self) -> Result<Value, String> {
        let mut map = Map::new();
        loop {
            self.skip_ws_and_comments();
            if self.rest().starts_with("</dict>") {
                self.i += 7;
                break;
            }
            let tag = self.skip_tag()?;
            if !tag.starts_with("key") {
                return Err("dict expected <key>".into());
            }
            let (key, _) = self.read_until_end("key")?;
            let val = self.parse_value()?;
            map.insert(unescape_xml(&key), val);
        }
        Ok(Value::Object(map))
    }

    fn parse_array(&mut self) -> Result<Value, String> {
        let mut arr = Vec::new();
        loop {
            self.skip_ws_and_comments();
            if self.rest().starts_with("</array>") {
                self.i += 8;
                break;
            }
            arr.push(self.parse_value()?);
        }
        Ok(Value::Array(arr))
    }

    fn read_until_end(&mut self, name: &str) -> Result<(String, ()), String> {
        let close = format!("</{name}>");
        let r = self.rest();
        let at = r.find(&close).ok_or_else(|| format!("missing {close}"))?;
        let text = r[..at].to_string();
        self.i += at + close.len();
        Ok((text, ()))
    }
}

fn unescape_xml(s: &str) -> String {
    s.replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&amp;", "&")
        .replace("&quot;", "\"")
        .replace("&apos;", "'")
}

pub fn finder_time(t: SystemTime) -> String {
    let secs = t.duration_since(UNIX_EPOCH).unwrap_or_default().as_secs() as libc::time_t;
    unsafe {
        let mut tm = std::mem::zeroed::<libc::tm>();
        if libc::localtime_r(&secs, &mut tm).is_null() {
            return "01/01/1970 00:00:00".into();
        }
        let mut buf = [0u8; 32];
        let n = libc::strftime(
            buf.as_mut_ptr() as *mut libc::c_char,
            buf.len(),
            b"%m/%d/%Y %H:%M:%S\0".as_ptr() as *const libc::c_char,
            &tm,
        );
        String::from_utf8_lossy(&buf[..n as usize]).into_owned()
    }
}

pub fn ostype_display(bytes: &[u8; 4]) -> String {
    let mut s = String::from("\"");
    for b in bytes {
        if *b == 0 {
            s.push_str("\\0");
        } else if (0x20..0x7f).contains(b) {
            s.push(*b as char);
        } else {
            s.push('\\');
            s.push_str(&format!("{b:o}"));
        }
    }
    s.push('"');
    s
}

pub fn get_file_info_text(path: &Path, meta: &std::fs::Metadata, finder: Option<&[u8]>) -> String {
    let shown = path
        .canonicalize()
        .unwrap_or_else(|_| path.to_path_buf());
    let mut ty = [0u8; 4];
    let mut cr = [0u8; 4];
    if let Some(buf) = finder {
        if buf.len() >= 8 {
            ty.copy_from_slice(&buf[0..4]);
            cr.copy_from_slice(&buf[4..8]);
        }
    }
    let created = meta.created().ok().map(finder_time).unwrap_or_default();
    let modified = meta.modified().ok().map(finder_time).unwrap_or_default();
    format!(
        "file: \"{}\"\ntype: {}\ncreator: {}\nattributes: avbstclinmedz\ncreated: {created}\nmodified: {modified}\n",
        shown.display(),
        ostype_display(&ty),
        ostype_display(&cr),
    )
}

pub fn codesign_verbose(path: &str, data: &[u8]) -> String {
    let mut out = String::new();
    let _ = writeln!(out, "Executable={path}");
    match parse_code_sign(data) {
        Ok(info) => {
            let _ = writeln!(out, "Identifier={}", info.ident);
            let _ = writeln!(out, "Format={}", info.format);
            if let Some(cd) = info.cd_line {
                let _ = writeln!(out, "{cd}");
            }
            if let Some(p) = info.platform {
                if p != 0 {
                    let _ = writeln!(out, "Platform identifier={p}");
                }
            }
            if let Some(n) = info.sig_size {
                let _ = writeln!(out, "Signature size={n}");
            }
            let _ = writeln!(out, "Info.plist=not bound");
            let _ = writeln!(out, "TeamIdentifier={}", info.team.unwrap_or_else(|| "not set".into()));
            let _ = writeln!(out, "Sealed Resources=none");
            if let Some(r) = info.req_line {
                let _ = writeln!(out, "{r}");
            }
        }
        Err(_) => {
            let _ = writeln!(out, "Identifier=unknown");
            let _ = writeln!(out, "Format=Mach-O inspect only");
            let _ = writeln!(out, "Size={}", data.len());
        }
    }
    out
}

struct CsInfo {
    ident: String,
    format: String,
    cd_line: Option<String>,
    sig_size: Option<usize>,
    team: Option<String>,
    platform: Option<u8>,
    req_line: Option<String>,
}

fn parse_code_sign(data: &[u8]) -> Result<CsInfo, ()> {
    if data.len() < 8 {
        return Err(());
    }
    let magic = u32::from_be_bytes(data[0..4].try_into().unwrap());
    if magic == 0xcafebabe || magic == 0xbebafeca || magic == 0xcafebabf {
        return parse_fat(data);
    }
    parse_thin(data, None)
}

fn parse_fat(data: &[u8]) -> Result<CsInfo, ()> {
    let magic = u32::from_be_bytes(data[0..4].try_into().unwrap());
    let swapped = magic == 0xbebafeca;
    let narch = rd32(data, 4, swapped)? as usize;
    let mut arches = Vec::new();
    let mut scored: Vec<(i32, CsInfo, usize, u32, u32)> = Vec::new();
    for i in 0..narch {
        let off = 8 + i * 20;
        if data.len() < off + 20 {
            break;
        }
        let cputype = rd32(data, off, swapped)?;
        let subtype = rd32(data, off + 4, swapped)?;
        let offset = rd32(data, off + 8, swapped)? as usize;
        let size = rd32(data, off + 12, swapped)? as usize;
        arches.push(cpu_name(cputype, subtype));
        if offset.saturating_add(size) <= data.len() {
            if let Ok(info) = parse_thin(&data[offset..offset + size], None) {
                scored.push((arch_score(cputype, subtype), info, i, cputype, subtype));
            }
        }
    }
    scored.sort_by_key(|(s, _, i, _, _)| (-s, *i as i32));
    let mut info = scored.into_iter().next().ok_or(())?.1;
    info.format = format!("Mach-O universal ({})", arches.join(" "));
    Ok(info)
}

fn arch_score(cputype: u32, subtype: u32) -> i32 {
    let sub = subtype & 0x00ff_ffff;
    let native_arm = cfg!(target_arch = "aarch64");
    let native_x64 = cfg!(target_arch = "x86_64");
    if native_arm && cputype == 0x0100_000c {
        if sub == 2 {
            30
        } else {
            20
        }
    } else if native_x64 && cputype == 0x0100_0007 {
        20
    } else {
        1
    }
}

fn parse_thin(data: &[u8], format_override: Option<String>) -> Result<CsInfo, ()> {
    if data.len() < 32 {
        return Err(());
    }
    let magic = u32::from_le_bytes(data[0..4].try_into().unwrap());
    let (is64, endian_le) = match magic {
        0xfeedfacf => (true, true),
        0xcffaedfe => (true, false),
        0xfeedface => (false, true),
        0xcefaedfe => (false, false),
        _ => return Err(()),
    };
    let cputype = rd32_end(data, 4, endian_le)?;
    let subtype = rd32_end(data, 8, endian_le)?;
    let ncmds = rd32_end(data, 16, endian_le)? as usize;
    let sizeofcmds = rd32_end(data, 20, endian_le)? as usize;
    let header = if is64 { 32 } else { 28 };
    if data.len() < header + sizeofcmds {
        return Err(());
    }
    let mut off = header;
    let mut ident = "unknown".to_string();
    let mut cd_line = None;
    let mut sig_size = None;
    let mut team = None;
    let mut platform = None;
    let mut req_line = None;
    for _ in 0..ncmds {
        if off + 8 > data.len() {
            break;
        }
        let cmd = rd32_end(data, off, endian_le)?;
        let cmdsize = rd32_end(data, off + 4, endian_le)? as usize;
        if cmdsize < 8 || off + cmdsize > data.len() {
            break;
        }
        // LC_CODE_SIGNATURE
        if cmd == 0x1d && cmdsize >= 16 {
            let dataoff = rd32_end(data, off + 8, endian_le)? as usize;
            let datasize = rd32_end(data, off + 12, endian_le)? as usize;
            sig_size = Some(datasize);
            if dataoff.saturating_add(datasize) <= data.len() {
                if let Some(cd) = parse_superblob(&data[dataoff..dataoff + datasize]) {
                    ident = cd.ident;
                    cd_line = Some(cd.line);
                    team = cd.team;
                    platform = cd.platform;
                    req_line = cd.req_line;
                    if let Some(sz) = cd.cms_size {
                        sig_size = Some(sz);
                    }
                }
            }
        }
        off += cmdsize;
    }
    let fmt = format_override.unwrap_or_else(|| {
        format!("Mach-O thin ({})", cpu_name(cputype, subtype))
    });
    Ok(CsInfo {
        ident,
        format: fmt,
        cd_line,
        sig_size,
        team,
        platform,
        req_line,
    })
}

struct Cd {
    ident: String,
    line: String,
    team: Option<String>,
    platform: Option<u8>,
    req_line: Option<String>,
    cms_size: Option<usize>,
}

fn parse_superblob(blob: &[u8]) -> Option<Cd> {
    if blob.len() < 12 {
        return None;
    }
    let magic = u32::from_be_bytes(blob[0..4].try_into().ok()?);
    if magic != 0xfade0cc0 {
        return parse_codedir(blob);
    }
    let count = u32::from_be_bytes(blob[8..12].try_into().ok()?) as usize;
    let mut cd = None;
    let mut req_line = None;
    let mut cms_size = None;
    for i in 0..count {
        let e = 12 + i * 8;
        if e + 8 > blob.len() {
            break;
        }
        let typ = u32::from_be_bytes(blob[e..e + 4].try_into().ok()?);
        let offset = u32::from_be_bytes(blob[e + 4..e + 8].try_into().ok()?) as usize;
        if offset >= blob.len() {
            continue;
        }
        if typ == 0 {
            cd = parse_codedir(&blob[offset..]);
        } else if typ == 2 && blob.len() >= offset + 12 {
            let req = &blob[offset..];
            let rmagic = u32::from_be_bytes(req[0..4].try_into().ok()?);
            if rmagic == 0xfade0c01 {
                let length = u32::from_be_bytes(req[4..8].try_into().ok()?);
                let nreq = u32::from_be_bytes(req[8..12].try_into().ok()?);
                req_line = Some(format!(
                    "Internal requirements count={nreq} size={length}"
                ));
            }
        } else if typ == 0x10000 && blob.len() >= offset + 8 {
            let cms = &blob[offset..];
            cms_size = Some(
                (u32::from_be_bytes(cms[4..8].try_into().ok()?) as usize).saturating_sub(8),
            );
        }
    }
    let mut cd = cd?;
    cd.req_line = req_line;
    cd.cms_size = cms_size;
    Some(cd)
}

fn parse_codedir(blob: &[u8]) -> Option<Cd> {
    if blob.len() < 40 {
        return None;
    }
    let magic = u32::from_be_bytes(blob[0..4].try_into().ok()?);
    if magic != 0xfade0c02 {
        return None;
    }
    let length = u32::from_be_bytes(blob[4..8].try_into().ok()?) as usize;
    let version = u32::from_be_bytes(blob[8..12].try_into().ok()?);
    let flags = u32::from_be_bytes(blob[12..16].try_into().ok()?);
    let hash_offset = u32::from_be_bytes(blob[16..20].try_into().ok()?) as usize;
    let ident_off = u32::from_be_bytes(blob[20..24].try_into().ok()?) as usize;
    let n_special = u32::from_be_bytes(blob[24..28].try_into().ok()?);
    let n_code = u32::from_be_bytes(blob[28..32].try_into().ok()?);
    let ident = cstr_at(blob, ident_off).unwrap_or("unknown");
    let platform = if blob.len() > 38 { blob[38] } else { 0 };
    let mut team = None;
    if version >= 0x20200 && blob.len() >= 48 {
        let team_off = u32::from_be_bytes(blob[44..48].try_into().ok()?) as usize;
        if team_off != 0 {
            team = cstr_at(blob, team_off).map(|s| s.to_string());
        }
    }
    let line = format!(
        "CodeDirectory v={version:x} size={length} flags={flags:#x}(none) hashes={n_code}+{n_special} location=embedded"
    );
    let _ = hash_offset;
    Some(Cd {
        ident: ident.to_string(),
        line,
        team,
        platform: if platform != 0 { Some(platform) } else { None },
        req_line: None,
        cms_size: None,
    })
}

fn cstr_at(buf: &[u8], off: usize) -> Option<&str> {
    if off >= buf.len() {
        return None;
    }
    let end = buf[off..].iter().position(|b| *b == 0)? + off;
    std::str::from_utf8(&buf[off..end]).ok()
}

fn cpu_name(cputype: u32, subtype: u32) -> String {
    let sub = subtype & 0x00ff_ffff;
    match cputype {
        0x0100_0007 => "x86_64".into(),
        0x0100_000c if sub == 2 => "arm64e".into(),
        0x0100_000c => "arm64".into(),
        7 => "i386".into(),
        12 => "arm".into(),
        other => format!("cpu{other:#x}"),
    }
}

fn rd32(data: &[u8], off: usize, swapped: bool) -> Result<u32, ()> {
    let s: [u8; 4] = data.get(off..off + 4).ok_or(())?.try_into().map_err(|_| ())?;
    Ok(if swapped {
        u32::from_le_bytes(s)
    } else {
        u32::from_be_bytes(s)
    })
}

fn rd32_end(data: &[u8], off: usize, le: bool) -> Result<u32, ()> {
    let s: [u8; 4] = data.get(off..off + 4).ok_or(())?.try_into().map_err(|_| ())?;
    Ok(if le {
        u32::from_le_bytes(s)
    } else {
        u32::from_be_bytes(s)
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sw_vers_uses_tabs() {
        let s = sw_vers_block("macOS", "26.5.1", "25F80");
        assert_eq!(s, "ProductName:\t\tmacOS\nProductVersion:\t\t26.5.1\nBuildVersion:\t\t25F80\n");
    }

    #[test]
    fn plutil_p_matches_apple_shape() {
        let v = serde_json::json!({"hello":"world","n":1});
        assert_eq!(plutil_p(&v), "{\n  \"hello\" => \"world\"\n  \"n\" => 1\n}\n");
    }

    #[test]
    fn defaults_domain_matches_apple_shape() {
        let v = serde_json::json!({"color":"blue","n":1});
        assert_eq!(defaults_read_domain(&v), "{\n    color = blue;\n    n = 1;\n}\n");
    }
}
