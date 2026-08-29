//! GitHub `bug.yml` issue-form URL for Settings → About → Report a Bug.
//!
//! GitHub prefills issue-form fields from query params whose names match the
//! YAML `id`s. Dropdowns are ignored, so `platform` and `install_channel` in
//! `.github/ISSUE_TEMPLATE/bug.yml` are text inputs.

use std::ffi::{CStr, CString, c_char};

const BUG_FORM: &str =
    "https://github.com/Wawona/Wawona/issues/new?template=bug.yml";
/// Stay under GitHub 414 and iOS `openURL` practical limits.
const MAX_URL_BYTES: usize = 7800;
const TRUNCATED_NOTE: &str = "(truncated; full report is on the clipboard)\n\n";

fn percent_encode(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(b as char);
            }
            b' ' => out.push('+'),
            _ => out.push_str(&format!("%{b:02X}")),
        }
    }
    out
}

fn utf8_suffix(s: &str, max_bytes: usize) -> &str {
    if s.len() <= max_bytes {
        return s;
    }
    let mut i = s.len().saturating_sub(max_bytes);
    while i < s.len() && !s.is_char_boundary(i) {
        i += 1;
    }
    &s[i..]
}

fn assemble(
    platform: &str,
    install_channel: &str,
    wawona_version: &str,
    host_os: &str,
    logs: &str,
) -> String {
    format!(
        "{BUG_FORM}&platform={}&install_channel={}&wawona_version={}&host_os={}&logs={}",
        percent_encode(platform),
        percent_encode(install_channel),
        percent_encode(wawona_version),
        percent_encode(host_os),
        percent_encode(logs),
    )
}

/// Canonical install-channel string for `bug.yml` `install_channel`.
pub fn canonical_install_channel(raw: &str) -> &'static str {
    match raw.trim() {
        "TestFlight" | "TestFlight (Beta)" => "TestFlight (Beta)",
        "App Store" | "App Store (Release)" => "App Store (Release)",
        "Play Store (Beta)" | "com.android.vending" => "Play Store (Beta)",
        "Play Store (Release)" => "Play Store (Release)",
        "Sideload" | "Sideload IPA"
        | "Sideload IPA (Xcode, AltStore, TrollStore, Sileo or similar)" => {
            "Sideload IPA (Xcode, AltStore, TrollStore, Sileo or similar)"
        }
        "Sideload APK" => "Sideload APK",
        "Simulator" => "Simulator",
        "macOS" | "nix" | "nix / local build (not a prebuilt installation)" => {
            "nix / local build (not a prebuilt installation)"
        }
        "AppImage" => "Other",
        _ => "Other",
    }
}

/// Issue-form URL with platform, install channel, version, host OS, and logs.
pub fn github_bug_form_url(
    platform: &str,
    install_channel: &str,
    wawona_version: &str,
    host_os: &str,
    logs: &str,
) -> String {
    let channel = canonical_install_channel(install_channel);
    let full = assemble(platform, channel, wawona_version, host_os, logs);
    if full.len() <= MAX_URL_BYTES {
        return full;
    }
    let mut lo = 0usize;
    let mut hi = logs.len();
    let mut best = assemble(
        platform,
        channel,
        wawona_version,
        host_os,
        TRUNCATED_NOTE,
    );
    while lo < hi {
        let mid = (lo + hi + 1) / 2;
        let body = format!("{}{}", TRUNCATED_NOTE, utf8_suffix(logs, mid));
        let candidate = assemble(platform, channel, wawona_version, host_os, &body);
        if candidate.len() <= MAX_URL_BYTES {
            best = candidate;
            lo = mid;
        } else {
            hi = mid - 1;
        }
    }
    best
}

fn cstr<'a>(p: *const c_char) -> &'a str {
    if p.is_null() {
        return "";
    }
    unsafe { CStr::from_ptr(p) }.to_str().unwrap_or("")
}

/// Caller frees with `WWNStringFree`.
#[no_mangle]
pub extern "C" fn wwn_github_bug_report_url(
    platform: *const c_char,
    install_channel: *const c_char,
    wawona_version: *const c_char,
    host_os: *const c_char,
    logs: *const c_char,
) -> *mut c_char {
    let url = github_bug_form_url(
        cstr(platform),
        cstr(install_channel),
        cstr(wawona_version),
        cstr(host_os),
        cstr(logs),
    );
    CString::new(url.replace('\0', ""))
        .map(|s| s.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fills_bug_yml_and_platform() {
        let url = github_bug_form_url(
            "iOS",
            "TestFlight",
            "26.8.22",
            "iOS 26.6 (iPhone18,4)",
            "log line",
        );
        assert!(url.contains("template=bug.yml"));
        assert!(url.contains("platform=iOS"));
        assert!(url.contains("install_channel=TestFlight+%28Beta%29"));
        assert!(url.contains("wawona_version=26.8.22"));
        assert!(url.contains("logs=log+line"));
    }

    #[test]
    fn truncates_long_logs() {
        let logs = "x".repeat(50_000);
        let url = github_bug_form_url("macOS", "nix", "26.8.22", "macOS 26", &logs);
        assert!(url.len() <= MAX_URL_BYTES);
        assert!(url.contains("truncated"));
        assert!(url.contains("platform=macOS"));
    }
}
