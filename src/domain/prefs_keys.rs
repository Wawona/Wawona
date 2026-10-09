//! Global preference key names and defaults. Host I/O stays in Swift
//! UserDefaults; schema ownership is Rust.

/// UserDefaults / SharedPreferences key for a product pref.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PrefKey {
    pub key: &'static str,
    pub default_bool: Option<bool>,
    pub default_string: Option<&'static str>,
}

pub const FORCE_SSD: PrefKey = PrefKey {
    key: "ForceServerSideDecorations",
    default_bool: Some(false),
    default_string: None,
};

pub const RESPECT_SAFE_AREA: PrefKey = PrefKey {
    key: "RespectSafeArea",
    default_bool: Some(true),
    default_string: None,
};

pub const COLOR_OPERATIONS: PrefKey = PrefKey {
    key: "ColorOperations",
    default_bool: Some(true),
    default_string: None,
};

pub const NESTED_COMPOSITORS: PrefKey = PrefKey {
    key: "NestedCompositorsSupport",
    default_bool: Some(true),
    default_string: None,
};

pub const SHOW_VIRTUAL_CURSOR: PrefKey = PrefKey {
    key: "ShowVirtualCursor",
    default_bool: Some(false),
    default_string: None,
};

pub const TOUCH_INPUT_TYPE: PrefKey = PrefKey {
    key: "TouchInputType",
    default_bool: None,
    default_string: Some("Touchpad"),
};

pub const COMPOSITOR_BACKEND: PrefKey = PrefKey {
    key: "CompositorBackend",
    default_bool: None,
    default_string: Some("auto"),
};

pub const OPENGL_DRIVER: PrefKey = PrefKey {
    key: "OpenGLDriver",
    default_bool: None,
    default_string: Some("angle"),
};

pub const DESKTOP_REPLACEMENT_ENABLED: PrefKey = PrefKey {
    key: "DesktopReplacementEnabled",
    default_bool: Some(false),
    default_string: None,
};

pub const DESKTOP_REPLACEMENT_MACHINE_ID: PrefKey = PrefKey {
    key: "DesktopReplacementMachineId",
    default_bool: None,
    default_string: Some(""),
};

pub const LOCKSCREEN_REPLACEMENT_ENABLED: PrefKey = PrefKey {
    key: "LockscreenReplacementEnabled",
    default_bool: Some(false),
    default_string: None,
};

/// JSON object of known keys → default (bool as true/false, string quoted).
pub fn defaults_json() -> String {
    let pairs: &[(&str, &str)] = &[
        (FORCE_SSD.key, "false"),
        (RESPECT_SAFE_AREA.key, "true"),
        (COLOR_OPERATIONS.key, "true"),
        (NESTED_COMPOSITORS.key, "true"),
        (SHOW_VIRTUAL_CURSOR.key, "false"),
        (TOUCH_INPUT_TYPE.key, "\"Touchpad\""),
        (COMPOSITOR_BACKEND.key, "\"auto\""),
        (OPENGL_DRIVER.key, "\"angle\""),
        (DESKTOP_REPLACEMENT_ENABLED.key, "false"),
        (DESKTOP_REPLACEMENT_MACHINE_ID.key, "\"\""),
        (LOCKSCREEN_REPLACEMENT_ENABLED.key, "false"),
    ];
    let body = pairs
        .iter()
        .map(|(k, v)| format!("\"{k}\":{v}"))
        .collect::<Vec<_>>()
        .join(",");
    format!("{{{body}}}")
}

/// Comma-separated key list for hosts that sync a suite.
pub fn all_keys_csv() -> String {
    [
        FORCE_SSD.key,
        RESPECT_SAFE_AREA.key,
        COLOR_OPERATIONS.key,
        NESTED_COMPOSITORS.key,
        SHOW_VIRTUAL_CURSOR.key,
        TOUCH_INPUT_TYPE.key,
        COMPOSITOR_BACKEND.key,
        OPENGL_DRIVER.key,
        DESKTOP_REPLACEMENT_ENABLED.key,
        DESKTOP_REPLACEMENT_MACHINE_ID.key,
        LOCKSCREEN_REPLACEMENT_ENABLED.key,
    ]
    .join(",")
}
