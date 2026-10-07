//! Optional Apple-framework callbacks registered by Swift.

use std::ffi::{c_char, CStr, CString};
use std::os::raw::c_int;
use std::sync::Mutex;

#[derive(Default)]
pub struct AppleHost {
    pub pasteboard_copy: Option<extern "C" fn(*const c_char) -> c_int>,
    pub pasteboard_paste: Option<extern "C" fn(*mut *mut c_char) -> c_int>,
    pub speak: Option<extern "C" fn(*const c_char, *const c_char, f32) -> c_int>,
    pub list_voices: Option<extern "C" fn() -> c_int>,
    pub open_url: Option<extern "C" fn(*const c_char) -> c_int>,
    pub open_directory: Option<extern "C" fn(*const c_char) -> c_int>,
    pub open_file: Option<extern "C" fn(*const c_char) -> c_int>,
    pub sips_info: Option<extern "C" fn(*const c_char, *mut c_char, usize, *mut c_int, *mut c_int) -> c_int>,
    pub sips_write: Option<extern "C" fn(*const c_char, *const c_char, *const c_char, c_int, c_int) -> c_int>,
    pub product_version: Option<extern "C" fn(*mut c_char, usize) -> c_int>,
    pub idle_prevent: Option<extern "C" fn(c_int) -> c_int>,
    pub plist_read_json: Option<extern "C" fn(*const c_char, *mut *mut c_char) -> c_int>,
    pub plist_write: Option<extern "C" fn(*const c_char, *const c_char, *const c_char) -> c_int>,
    pub copy_item: Option<extern "C" fn(*const c_char, *const c_char) -> c_int>,
    pub keychain_dump: Option<extern "C" fn(*mut *mut c_char) -> c_int>,
    pub oslog: Option<extern "C" fn(*const c_char) -> c_int>,
    pub path_status: Option<extern "C" fn(*mut *mut c_char) -> c_int>,
    pub host_flag: Option<extern "C" fn(*const c_char) -> c_int>,
}

static HOST: Mutex<AppleHost> = Mutex::new(AppleHost {
    pasteboard_copy: None,
    pasteboard_paste: None,
    speak: None,
    list_voices: None,
    open_url: None,
    open_directory: None,
    open_file: None,
    sips_info: None,
    sips_write: None,
    product_version: None,
    idle_prevent: None,
    plist_read_json: None,
    plist_write: None,
    copy_item: None,
    keychain_dump: None,
    oslog: None,
    path_status: None,
    host_flag: None,
});

pub fn with_host<R>(f: impl FnOnce(&AppleHost) -> R) -> R {
    let guard = HOST.lock().expect("darwin host mutex");
    f(&guard)
}

#[allow(dead_code)]
unsafe fn set_fn<T>(slot: &mut Option<T>, value: Option<T>) {
    *slot = value;
}

#[no_mangle]
pub extern "C" fn wwn_darwin_cli_set_pasteboard_copy(fn_: Option<extern "C" fn(*const c_char) -> c_int>) {
    let mut h = HOST.lock().expect("darwin host mutex");
    unsafe { set_fn(&mut h.pasteboard_copy, fn_) };
}

#[no_mangle]
pub extern "C" fn wwn_darwin_cli_set_pasteboard_paste(fn_: Option<extern "C" fn(*mut *mut c_char) -> c_int>) {
    HOST.lock().expect("m").pasteboard_paste = fn_;
}

#[no_mangle]
pub extern "C" fn wwn_darwin_cli_set_speak(fn_: Option<extern "C" fn(*const c_char, *const c_char, f32) -> c_int>) {
    HOST.lock().expect("m").speak = fn_;
}

#[no_mangle]
pub extern "C" fn wwn_darwin_cli_set_list_voices(fn_: Option<extern "C" fn() -> c_int>) {
    HOST.lock().expect("m").list_voices = fn_;
}

#[no_mangle]
pub extern "C" fn wwn_darwin_cli_set_open_url(fn_: Option<extern "C" fn(*const c_char) -> c_int>) {
    HOST.lock().expect("m").open_url = fn_;
}

#[no_mangle]
pub extern "C" fn wwn_darwin_cli_set_open_directory(fn_: Option<extern "C" fn(*const c_char) -> c_int>) {
    HOST.lock().expect("m").open_directory = fn_;
}

#[no_mangle]
pub extern "C" fn wwn_darwin_cli_set_open_file(fn_: Option<extern "C" fn(*const c_char) -> c_int>) {
    HOST.lock().expect("m").open_file = fn_;
}

#[no_mangle]
pub extern "C" fn wwn_darwin_cli_set_sips_info(
    fn_: Option<extern "C" fn(*const c_char, *mut c_char, usize, *mut c_int, *mut c_int) -> c_int>,
) {
    HOST.lock().expect("m").sips_info = fn_;
}

#[no_mangle]
pub extern "C" fn wwn_darwin_cli_set_sips_write(
    fn_: Option<extern "C" fn(*const c_char, *const c_char, *const c_char, c_int, c_int) -> c_int>,
) {
    HOST.lock().expect("m").sips_write = fn_;
}

#[no_mangle]
pub extern "C" fn wwn_darwin_cli_set_product_version(fn_: Option<extern "C" fn(*mut c_char, usize) -> c_int>) {
    HOST.lock().expect("m").product_version = fn_;
}

#[no_mangle]
pub extern "C" fn wwn_darwin_cli_set_idle_prevent(fn_: Option<extern "C" fn(c_int) -> c_int>) {
    HOST.lock().expect("m").idle_prevent = fn_;
}

#[no_mangle]
pub extern "C" fn wwn_darwin_cli_set_plist_read_json(
    fn_: Option<extern "C" fn(*const c_char, *mut *mut c_char) -> c_int>,
) {
    HOST.lock().expect("m").plist_read_json = fn_;
}

#[no_mangle]
pub extern "C" fn wwn_darwin_cli_set_plist_write(
    fn_: Option<extern "C" fn(*const c_char, *const c_char, *const c_char) -> c_int>,
) {
    HOST.lock().expect("m").plist_write = fn_;
}

#[no_mangle]
pub extern "C" fn wwn_darwin_cli_set_copy_item(
    fn_: Option<extern "C" fn(*const c_char, *const c_char) -> c_int>,
) {
    HOST.lock().expect("m").copy_item = fn_;
}

#[no_mangle]
pub extern "C" fn wwn_darwin_cli_set_keychain_dump(fn_: Option<extern "C" fn(*mut *mut c_char) -> c_int>) {
    HOST.lock().expect("m").keychain_dump = fn_;
}

#[no_mangle]
pub extern "C" fn wwn_darwin_cli_set_oslog(fn_: Option<extern "C" fn(*const c_char) -> c_int>) {
    HOST.lock().expect("m").oslog = fn_;
}

#[no_mangle]
pub extern "C" fn wwn_darwin_cli_set_path_status(fn_: Option<extern "C" fn(*mut *mut c_char) -> c_int>) {
    HOST.lock().expect("m").path_status = fn_;
}

#[no_mangle]
pub extern "C" fn wwn_darwin_cli_set_host_flag(fn_: Option<extern "C" fn(*const c_char) -> c_int>) {
    HOST.lock().expect("m").host_flag = fn_;
}

#[no_mangle]
pub unsafe extern "C" fn wwn_darwin_cli_free(p: *mut c_char) {
    if !p.is_null() {
        drop(CString::from_raw(p));
    }
}

#[allow(dead_code)]
pub fn c_string(s: &str) -> *mut c_char {
    CString::new(s).unwrap_or_else(|_| CString::new("").unwrap()).into_raw()
}

pub fn from_c<'a>(p: *const c_char) -> Option<&'a str> {
    if p.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(p) }.to_str().ok()
}

pub fn host_flag(name: &str) -> bool {
    with_host(|h| {
        if let Some(fn_) = h.host_flag {
            let c = CString::new(name).unwrap_or_default();
            fn_(c.as_ptr()) != 0
        } else {
            true
        }
    })
}
