//! Appium session capabilities, from the WAWONA_* environment.

use std::path::Path;
use std::time::Duration;

use serde_json::{Map, Value};

use crate::util::env_or;

pub fn server() -> String {
    env_or("WAWONA_APPIUM_SERVER", "http://127.0.0.1:4723")
}

fn flag(k: &str, default: &str) -> bool {
    env_or(k, default) == "1"
}

fn number(k: &str, default: u64) -> u64 {
    std::env::var(k).ok().and_then(|v| v.parse().ok()).unwrap_or(default)
}

fn set(m: &mut Map<String, Value>, k: &str, v: impl Into<Value>) {
    m.insert(k.into(), v.into());
}

pub fn capabilities(platform: &str) -> Value {
    let mut m = Map::new();
    let bundle = env_or("WAWONA_BUNDLE_ID", "com.aspauldingcode.Wawona");
    let app = env_or("WAWONA_APP_PATH", "");
    let timeout = number("WAWONA_APPIUM_CMD_TIMEOUT", 120);
    match platform {
        "android" => {
            set(&mut m, "platformName", "Android");
            set(&mut m, "appium:automationName", "UiAutomator2");
            set(&mut m, "appium:app", app);
            set(&mut m, "appium:appPackage", env_or("WAWONA_ANDROID_PACKAGE", "com.aspauldingcode.wawona"));
            set(&mut m, "appium:appActivity", env_or("WAWONA_ANDROID_ACTIVITY", ".MainActivity"));
            set(&mut m, "appium:noReset", flag("WAWONA_APPIUM_NO_RESET", "1"));
            set(&mut m, "appium:newCommandTimeout", timeout);
            set(&mut m, "appium:autoGrantPermissions", true);
        }
        "linux" => {
            set(&mut m, "platformName", "Linux");
            set(&mut m, "appium:automationName", env_or("WAWONA_LINUX_AUTOMATION", "atspi2"));
            let app = env_or("WAWONA_APP_PATH", "Wawona");
            set(&mut m, "appium:appName", env_or("WAWONA_LINUX_APP_NAME", &app));
            set(&mut m, "appium:newCommandTimeout", timeout);
        }
        "macos" => {
            set(&mut m, "platformName", "mac");
            set(&mut m, "appium:automationName", "Mac2");
            // appPath + noReset activates a live tip Wawona rather than cold
            // launching it. WAWONA_MAC2_MANAGE_APP=0 is for desktop-wide probes.
            if flag("WAWONA_MAC2_MANAGE_APP", "1") {
                set(&mut m, "appium:bundleId", bundle);
                if !app.is_empty() && Path::new(&app).is_dir() {
                    set(&mut m, "appium:appPath", app);
                }
            }
            set(&mut m, "appium:showServerLogs", true);
            // WebDriverAgentMac's xcodebuild often needs more than 120 s.
            set(&mut m, "appium:serverStartupTimeout", number("WAWONA_MAC2_SERVER_STARTUP_MS", 300_000));
            if let Some(url) = wda_url() {
                set(&mut m, "appium:webDriverAgentMacUrl", url);
            }
            let bootstrap = env_or("WAWONA_MAC2_BOOTSTRAP_ROOT", "");
            if !bootstrap.is_empty() && Path::new(&bootstrap).is_dir() {
                set(&mut m, "appium:bootstrapRoot", bootstrap);
            }
            set(&mut m, "appium:noReset", flag("WAWONA_APPIUM_NO_RESET", "1"));
            set(&mut m, "appium:skipAppKill", flag("WAWONA_MAC2_SKIP_APP_KILL", "1"));
        }
        _ => {
            let device = match platform {
                "ipados" => "iPad Pro 13-inch (M4)",
                "tvos" => "Apple TV 4K (3rd generation)",
                "visionos" => "Apple Vision Pro",
                // watchos drives the phone side of the pair.
                _ => "iPhone 17 Pro",
            };
            set(&mut m, "platformName", "iOS");
            set(&mut m, "appium:automationName", "XCUITest");
            set(&mut m, "appium:deviceName", env_or("WAWONA_DEVICE_NAME", device));
            if let Ok(v) = std::env::var("WAWONA_PLATFORM_VERSION") {
                set(&mut m, "appium:platformVersion", v);
            }
            if !app.is_empty() {
                set(&mut m, "appium:app", app);
            }
            set(&mut m, "appium:bundleId", bundle);
            set(&mut m, "appium:noReset", flag("WAWONA_APPIUM_NO_RESET", "1"));
            set(&mut m, "appium:newCommandTimeout", timeout);
            set(&mut m, "appium:settings[snapshotMaxDepth]", 60);
        }
    }
    Value::Object(m)
}

/// A pre-warmed WebDriverAgentMac (`cargo xtask appium wda`), named or probed.
fn wda_url() -> Option<String> {
    let named = env_or("WAWONA_MAC2_WDA_URL", "");
    if !named.is_empty() {
        return Some(named);
    }
    let url =
        format!("http://{}:{}", env_or("WAWONA_MAC2_WDA_HOST", "127.0.0.1"), env_or("WAWONA_MAC2_WDA_PORT", "10100"));
    let agent: ureq::Agent =
        ureq::Agent::config_builder().timeout_global(Some(Duration::from_millis(1500))).build().into();
    agent.get(&format!("{url}/status")).call().ok().map(|_| url)
}

#[cfg(test)]
mod tests {
    #[test]
    fn linux_selects_atspi2() {
        std::env::remove_var("WAWONA_LINUX_AUTOMATION");
        std::env::remove_var("WAWONA_LINUX_APP_NAME");
        std::env::set_var("WAWONA_APP_PATH", "/tmp/Wawona.AppImage");
        let c = super::capabilities("linux");
        assert_eq!(c["platformName"], "Linux");
        assert_eq!(c["appium:automationName"], "atspi2");
        assert_eq!(c["appium:appName"], "/tmp/Wawona.AppImage");
        assert!(c.get("appium:app").is_none());
    }
}
