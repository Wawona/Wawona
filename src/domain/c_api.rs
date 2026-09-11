//! Thin C trampoline for hosts that do not yet import generated UniFFI Swift.
//! Policy lives in `domain`. This is not `WWNCore*`.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use super::machine_profile::MachineProfile;
use super::profile_store::ProfileDocument;
use super::validation::{
    normalize_ssh_port, sanitize_ssh_host, validate_editor, validate_profile, EditorStateView,
};

fn cstr_to_str<'a>(ptr: *const c_char) -> Option<&'a str> {
    if ptr.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(ptr) }.to_str().ok()
}

fn to_cstring(s: String) -> *mut c_char {
    CString::new(s).map(|c| c.into_raw()).unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub extern "C" fn wawona_domain_string_free(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            drop(CString::from_raw(s));
        }
    }
}

/// Decode a `wawona.machineProfiles.v1` JSON array. Returns a JSON array
/// (igetty rows dropped) or null on error.
#[no_mangle]
pub extern "C" fn wawona_profiles_v1_decode(json: *const c_char) -> *mut c_char {
    let Some(text) = cstr_to_str(json) else {
        return std::ptr::null_mut();
    };
    match ProfileDocument::from_json(text).and_then(|d| d.to_json()) {
        Ok(out) => to_cstring(out),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Insert or replace one profile in a v1 array. Returns the new array JSON,
/// or null on validation / JSON error (igetty is dropped, not inserted).
#[no_mangle]
pub extern "C" fn wawona_profiles_v1_put(
    list_json: *const c_char,
    profile_json: *const c_char,
) -> *mut c_char {
    let Some(list) = cstr_to_str(list_json) else {
        return std::ptr::null_mut();
    };
    let Some(profile_text) = cstr_to_str(profile_json) else {
        return std::ptr::null_mut();
    };
    let mut doc = match ProfileDocument::from_json(list) {
        Ok(d) => d,
        Err(_) => return std::ptr::null_mut(),
    };
    let profile: MachineProfile = match serde_json::from_str(profile_text) {
        Ok(p) => p,
        Err(_) => return std::ptr::null_mut(),
    };
    if doc.put(profile).is_err() {
        return std::ptr::null_mut();
    }
    match doc.to_json() {
        Ok(out) => to_cstring(out),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn wawona_profiles_v1_delete(
    list_json: *const c_char,
    id: *const c_char,
) -> *mut c_char {
    let Some(list) = cstr_to_str(list_json) else {
        return std::ptr::null_mut();
    };
    let Some(id) = cstr_to_str(id) else {
        return std::ptr::null_mut();
    };
    let mut doc = match ProfileDocument::from_json(list) {
        Ok(d) => d,
        Err(_) => return std::ptr::null_mut(),
    };
    doc.delete(id);
    match doc.to_json() {
        Ok(out) => to_cstring(out),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Empty string means ok. Non-empty is an error token. Null is a bad pointer.
#[no_mangle]
pub extern "C" fn wawona_profiles_v1_validate(profile_json: *const c_char) -> *mut c_char {
    let Some(text) = cstr_to_str(profile_json) else {
        return std::ptr::null_mut();
    };
    let profile: MachineProfile = match serde_json::from_str(text) {
        Ok(p) => p,
        Err(e) => return to_cstring(e.to_string()),
    };
    match validate_profile(&profile) {
        Ok(()) => to_cstring(String::new()),
        Err(msg) => to_cstring(msg),
    }
}

#[no_mangle]
pub extern "C" fn wawona_editor_sanitize_ssh_host(raw: *const c_char) -> *mut c_char {
    let Some(text) = cstr_to_str(raw) else {
        return to_cstring(String::new());
    };
    to_cstring(sanitize_ssh_host(text))
}

#[no_mangle]
pub extern "C" fn wawona_editor_normalize_ssh_port(raw: *const c_char, fallback: i32) -> i32 {
    let Some(text) = cstr_to_str(raw) else {
        return fallback;
    };
    normalize_ssh_port(text, fallback)
}

/// JSON array of issue raw values (`missingName`, …).
#[no_mangle]
pub extern "C" fn wawona_editor_validate(
    name: *const c_char,
    type_raw: *const c_char,
    ssh_host: *const c_char,
    ssh_user: *const c_char,
    ssh_port_text: *const c_char,
) -> *mut c_char {
    let name = cstr_to_str(name).unwrap_or("");
    let type_raw = cstr_to_str(type_raw).unwrap_or("native");
    let ssh_host = cstr_to_str(ssh_host).unwrap_or("");
    let ssh_user = cstr_to_str(ssh_user).unwrap_or("");
    let ssh_port_text = cstr_to_str(ssh_port_text).unwrap_or("");
    let issues = validate_editor(EditorStateView {
        name,
        type_raw,
        ssh_host,
        ssh_user,
        ssh_port_text,
    });
    let tokens: Vec<&str> = issues.iter().map(|i| i.as_str()).collect();
    match serde_json::to_string(&tokens) {
        Ok(out) => to_cstring(out),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Comma-separated settings sidebar slugs for `host` (`macos`, `ios`, …).
/// Caller frees with `wawona_domain_string_free`. Empty string if unknown host.
#[no_mangle]
pub extern "C" fn wawona_settings_visible_sections(host: *const c_char) -> *mut c_char {
    let Some(slug) = cstr_to_str(host) else {
        return to_cstring(String::new());
    };
    let Some(parsed) = super::settings_catalog::host_from_slug(slug) else {
        return to_cstring(String::new());
    };
    let joined = super::settings_catalog::visible_sections(parsed)
        .into_iter()
        .map(|s| s.slug())
        .collect::<Vec<_>>()
        .join(",");
    to_cstring(joined)
}

/// Four-state gate: `available`, `planned`, `blocked`, or `forbidden`.
/// Caller frees with `wawona_domain_string_free`.
#[no_mangle]
pub extern "C" fn wawona_capability_gate(
    platform: *const c_char,
    feature: *const c_char,
) -> *mut c_char {
    let Some(platform) = cstr_to_str(platform) else {
        return to_cstring(String::from("forbidden"));
    };
    let Some(feature) = cstr_to_str(feature) else {
        return to_cstring(String::from("forbidden"));
    };
    to_cstring(super::capabilities::gate(platform, feature).to_string())
}

/// 1 if this client / bundled id is forbidden as a Machines profile.
#[no_mangle]
pub extern "C" fn wawona_session_is_forbidden_client_id(id: *const c_char) -> i32 {
    let Some(id) = cstr_to_str(id) else {
        return 0;
    };
    i32::from(super::validation::is_forbidden_machines_client_id(id))
}
