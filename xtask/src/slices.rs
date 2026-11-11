//! Build slices: an Xcode PLATFORM_NAME, `iphoneos-modeb`, `android` or `linux`.

use anyhow::{bail, Result};

pub struct Slice {
    pub name: &'static str,
    pub triple: &'static str,
    /// clang target prefix and Xcode SDK name; `None` off Apple.
    pub apple: Option<Apple>,
    pub min_os: &'static str,
    pub features: &'static [&'static str],
    /// A cdylib needs every framework the app links, so Apple-mobile builds
    /// make only the static archive Xcode links.
    pub cdylib: bool,
}

pub struct Apple {
    pub clang: &'static str,
    pub sdk: &'static str,
    pub deploy_var: &'static str,
    pub simulator: bool,
}

/// waypipe-ssh: in-process waypipe over libssh2, never OpenSSH.
const MOBILE: &[&str] = &["waypipe-ssh", "smithay-protocols", "coreutils"];
const MODE_B: &[&str] = &["waypipe-ssh", "smithay-protocols", "coreutils", "profile-ios-mode-b"];
/// desktop-protocols: DRM, session lock, capture and XWayland globals. Mode B
/// gates compile in; the slice bundles its dylib separately.
const MACOS: &[&str] =
    &["smithay-protocols", "desktop-protocols", "profile-desktop-host", "iland-baremetal", "nix-ghostty-vt"];

const fn apple(clang: &'static str, sdk: &'static str, deploy_var: &'static str, simulator: bool) -> Option<Apple> {
    Some(Apple { clang, sdk, deploy_var, simulator })
}

pub const SLICES: &[Slice] = &[
    Slice { name: "macosx", triple: "aarch64-apple-darwin", apple: apple("arm64-apple-macos", "macosx", "MACOSX_DEPLOYMENT_TARGET", false), min_os: "14.0", features: MACOS, cdylib: true },
    Slice { name: "iphoneos", triple: "aarch64-apple-ios", apple: apple("arm64-apple-ios", "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET", false), min_os: "13.0", features: MOBILE, cdylib: false },
    Slice { name: "iphoneos-modeb", triple: "aarch64-apple-ios", apple: apple("arm64-apple-ios", "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET", false), min_os: "13.0", features: MODE_B, cdylib: false },
    Slice { name: "iphonesimulator", triple: "aarch64-apple-ios-sim", apple: apple("arm64-apple-ios", "iphonesimulator", "IPHONEOS_DEPLOYMENT_TARGET", true), min_os: "13.0", features: MOBILE, cdylib: false },
    Slice { name: "appletvos", triple: "aarch64-apple-tvos", apple: apple("arm64-apple-tvos", "appletvos", "TVOS_DEPLOYMENT_TARGET", false), min_os: "17.0", features: MOBILE, cdylib: false },
    Slice { name: "appletvsimulator", triple: "aarch64-apple-tvos-sim", apple: apple("arm64-apple-tvos", "appletvsimulator", "TVOS_DEPLOYMENT_TARGET", true), min_os: "17.0", features: MOBILE, cdylib: false },
    Slice { name: "xros", triple: "aarch64-apple-visionos", apple: apple("arm64-apple-xros", "xros", "XROS_DEPLOYMENT_TARGET", false), min_os: "26.0", features: MOBILE, cdylib: false },
    Slice { name: "xrsimulator", triple: "aarch64-apple-visionos-sim", apple: apple("arm64-apple-xros", "xrsimulator", "XROS_DEPLOYMENT_TARGET", true), min_os: "26.0", features: MOBILE, cdylib: false },
    Slice { name: "watchos", triple: "aarch64-apple-watchos", apple: apple("arm64-apple-watchos", "watchos", "WATCHOS_DEPLOYMENT_TARGET", false), min_os: "10.0", features: MOBILE, cdylib: false },
    Slice { name: "watchsimulator", triple: "aarch64-apple-watchos-sim", apple: apple("arm64-apple-watchos", "watchsimulator", "WATCHOS_DEPLOYMENT_TARGET", true), min_os: "10.0", features: MOBILE, cdylib: false },
    Slice { name: "android", triple: "aarch64-linux-android", apple: None, min_os: "24", features: &["waypipe", "smithay-protocols", "coreutils"], cdylib: true },
    Slice { name: "linux", triple: "", apple: None, min_os: "", features: &["smithay-protocols", "desktop-protocols", "nix-ghostty-vt"], cdylib: true },
];

pub fn get(name: &str) -> Result<&'static Slice> {
    match SLICES.iter().find(|s| s.name == name) {
        Some(s) => Ok(s),
        None => bail!(
            "unknown slice {name}; one of: {}",
            SLICES.iter().map(|s| s.name).collect::<Vec<_>>().join(" ")
        ),
    }
}

/// The slice whose prebuilt dependencies a build slice reads.
pub fn deps_name(name: &str) -> &str {
    if name == "iphoneos-modeb" { "iphoneos" } else { name }
}
