//! The bundled and optional Wayland clients the lanes start, and the prefs
//! that make one the Default Machine without driving the Edit sheet.
//!
//! The keep-set ships in the app (Native Shell, Relay wasm). The move-set
//! (weston, niri, foot, demos, cubes) installs as deb or wasm, so its matrix
//! cells skip unless WAWONA_TEST_OPTIONAL_CLIENTS=1 (wawona-optional-software).

use super::ad::*;
use crate::util::*;
use anyhow::{bail, Result};
use serde_json::{json, Value};

/// Matrix cells by default.
pub const KEEP: &[&str] = &["wawona-shell", "wawona-wasm"];

const KEYS: &[(&str, &str)] = &[
    ("wawona-shell", "WawonaShellEnabled"),
    ("wawona-wasm", "WawonaWasmEnabled"),
    ("weston-terminal", "WestonTerminalEnabled"),
    ("weston-simple-shm", "WestonSimpleSHMEnabled"),
    ("weston", "WestonEnabled"),
    ("niri", "NiriEnabled"),
    ("foot", "FootEnabled"),
    ("weston-flower", "WestonFlowerEnabled"),
    ("kmscube", "KmscubeEnabled"),
    ("gbm-es2-demo", "GbmEs2DemoEnabled"),
    ("opengl-cube", "OpenglCubeEnabled"),
    ("vkcube", "VkcubeEnabled"),
    ("weston-simple-egl", "WestonSimpleEglEnabled"),
    ("weston-smoke", "WestonSmokeEnabled"),
    ("weston-clickdot", "WestonClickdotEnabled"),
    ("weston-eventdemo", "WestonEventdemoEnabled"),
    ("weston-resizor", "WestonResizorEnabled"),
    ("weston-cliptest", "WestonCliptestEnabled"),
    ("weston-transformed", "WestonTransformedEnabled"),
    ("weston-stacking", "WestonStackingEnabled"),
    ("weston-dnd", "WestonDndEnabled"),
    ("weston-image", "WestonImageEnabled"),
    ("weston-scaler", "WestonScalerEnabled"),
    ("weston-editor", "WestonEditorEnabled"),
    ("weston-constraints", "WestonConstraintsEnabled"),
];

const GPU: &[&str] = &["kmscube", "gbm-es2-demo", "opengl-cube", "vkcube", "weston-simple-egl"];

pub fn prefs_key(client: &str) -> Result<&'static str> {
    match KEYS.iter().find(|(c, _)| *c == client) {
        Some((_, k)) => Ok(k),
        None => bail!("FAIL: unknown client '{client}'"),
    }
}

/// Why a matrix cell does not run, or None when it does.
pub fn skip_reason(platform: &str, client: &str) -> Option<String> {
    // weston-simple-egl is a Wayland-EGL client (wl_egl_window + ANGLE), not KMS.
    if matches!(platform, "tvos" | "watchos") && GPU.contains(&client) {
        return Some(format!("platform-targets: no Vulkan/OpenGL/ANGLE on {platform}"));
    }
    if !KEEP.contains(&client) && !env_flag("WAWONA_TEST_OPTIONAL_CLIENTS") {
        return Some(
            "optional-software: install via deb/wasm (WAWONA_TEST_OPTIONAL_CLIENTS=1 for legacy in-process)".into(),
        );
    }
    None
}

/// Seconds a cell holds the client: nested compositors settle longer.
pub fn hold_secs(client: &str) -> u64 {
    let (var, default) = match client {
        "weston" | "niri" => ("WAWONA_MATRIX_NESTED_HOLD_SEC", "20"),
        _ => ("WAWONA_MATRIX_CLIENT_HOLD_SEC", "12"),
    };
    env_or(var, default).parse().unwrap_or(12)
}

/// Any of these in the log fails a cell even while the process is alive.
pub const FAIL_PATTERNS: &[&str] = &[
    "niri_main: panicked",
    "niri_main: fatal error",
    "niri_main not linked",
    "weston_compositor_main not linked",
    "Unknown bundled client id",
    "WWNNativeClientLaunchFailed",
    "LaunchFailedNotification",
    "SIGABRT",
    "panic_cannot_unwind",
    "Fatal error:",
    "EXC_BAD_ACCESS",
    "terminated due to signal",
];

/// Default Machine = `client` in the simulator's defaults, Welcome done,
/// Multi-Touch input (wawona-agent-device-multitouch).
pub fn set_ios(client: &str, device: &str, bundle: &str) -> Result<()> {
    let key = prefs_key(client)?;
    let Some(udid) = sim_udid(device) else { bail!("FAIL: could not resolve simulator for '{device}'") };
    let id = format!("e2e-{client}-default");
    let profile = json!([{
        "id": id,
        "name": "Default Machine",
        "type": "native",
        "sshHost": "",
        "sshUser": "",
        "sshPort": 22,
        "sshPassword": "",
        "remoteCommand": "",
        "launchers": [],
        "favorite": false,
        "runtimeOverrides": {"bundledAppID": client},
        "settingsOverrides": {"NativeClientId": client, key: true},
        "nativeLauncher": client,
    }]);
    let spawn = |args: &[&str]| try_output(cmd("xcrun").args(["simctl", "spawn", &udid, "defaults"]).args(args));
    let _ = try_output(cmd("xcrun").args(["simctl", "terminate", &udid, bundle]));
    // load() prefers data(forKey:) to the string form; drop the data payload first.
    spawn(&["delete", bundle, "wawona.machineProfiles.v1"]);
    let writes: &[&[&str]] = &[
        &["wawona.machineProfiles.v1", "-string", &profile.to_string()],
        &["wawona.activeMachineId.v1", "-string", &id],
        &[key, "-bool", "YES"],
        &["TouchInputType", "-string", "Multi-Touch"],
        &["hasSeenWelcome", "-bool", "YES"],
        &["wawona.pref.hasCompletedWelcome", "-bool", "YES"],
    ];
    for w in writes {
        let mut args = vec!["write", bundle];
        args.extend_from_slice(w);
        if spawn(&args).is_none() {
            bail!("simctl defaults write {} failed", w[0]);
        }
    }
    eprintln!("== iOS prefs: bundledAppID={client} udid={udid} bundle={bundle} ==");
    Ok(())
}

fn android_profile(client: &str, key: &str, now: u64) -> Value {
    json!({
        "id": format!("e2e-{client}-default"),
        "name": "Default Machine",
        "type": "native",
        "sshEnabled": false,
        "sshHost": "",
        "sshPort": 22,
        "sshUser": "",
        "sshPassword": "",
        "sshBinary": "ssh",
        "sshAuthMethod": "password",
        "sshKeyPath": "",
        "sshKeyPassphrase": "",
        "nativeLauncher": client,
        "remoteCommand": "",
        "customScript": "",
        "waypipeCompress": "lz4",
        "waypipeThreads": "0",
        "waypipeVideo": "none",
        "waypipeDebug": false,
        "waypipeOneshot": false,
        "waypipeDisableGpu": false,
        "waypipeLoginShell": false,
        "waypipeTitlePrefix": "",
        "waypipeSecCtx": "",
        "settingsOverrides": {"NativeClientId": client, key: true},
        "runtimeOverrides": {"bundledAppID": client},
        "favorite": false,
        "createdAtMs": now,
        "updatedAtMs": now,
        "vmSettings": {"provider": "utm-se", "vmIdentifier": "", "vsockPort": "", "notes": ""},
        "containerSettings": {"runtime": "docker", "containerRef": "", "entryCommand": "", "notes": ""},
    })
}

fn xml_escape(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;").replace('"', "&quot;").replace('\'', "&#x27;")
}

fn xml_unescape(s: &str) -> String {
    s.replace("&quot;", "\"")
        .replace("&#x27;", "'")
        .replace("&#39;", "'")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&amp;", "&")
}

fn upsert(xml: &str, pattern: &str, repl: &str) -> String {
    let re = regex::Regex::new(pattern).unwrap();
    if re.is_match(xml) {
        return re.replacen(xml, 1, regex::NoExpand(repl)).into_owned();
    }
    let end = regex::Regex::new(r"</map>\s*$").unwrap();
    end.replace(xml, regex::NoExpand(&format!("{repl}\n</map>\n"))).into_owned()
}

fn upsert_string(xml: &str, name: &str, value: &str) -> String {
    upsert(
        xml,
        &format!(r#"(?s)<string name="{}">.*?</string>"#, regex::escape(name)),
        &format!(r#"<string name="{name}">{value}</string>"#),
    )
}

fn upsert_bool(xml: &str, name: &str, value: bool) -> String {
    upsert(
        xml,
        &format!(r#"<boolean name="{}"[^/]*/>"#, regex::escape(name)),
        &format!(r#"<boolean name="{name}" value="{value}" />"#),
    )
}

/// The SharedPreferences rewrite: the native Default Machine launches `client`,
/// Welcome done, Touchpad Mode off.
pub fn android_prefs(xml: &str, client: &str, key: &str, now: u64) -> String {
    let re = regex::Regex::new(r#"(?s)<string name="wawona\.machineProfiles\.v1">(.*?)</string>"#).unwrap();
    let mut profiles: Vec<Value> =
        re.captures(xml).and_then(|c| serde_json::from_str(&xml_unescape(&c[1])).ok()).unwrap_or_default();
    match profiles.iter().position(|p| p["type"] == "native" || p["name"] == "Default Machine") {
        Some(i) => {
            let p = &mut profiles[i];
            p["nativeLauncher"] = json!(client);
            for (field, k) in [("runtimeOverrides", "bundledAppID"), ("settingsOverrides", "NativeClientId")] {
                if !p[field].is_object() {
                    p[field] = json!({});
                }
                p[field][k] = json!(client);
            }
            p["settingsOverrides"][key] = json!(true);
            p["updatedAtMs"] = json!(now);
        }
        None if profiles.is_empty() => profiles.push(android_profile(client, key, now)),
        None => profiles[0] = android_profile(client, key, now),
    }
    let active = profiles[0]["id"].as_str().unwrap_or_default().to_string();
    let mut out = upsert_string(xml, "nativeLauncher", client);
    out = upsert_string(&out, "wawona.machineProfiles.v1", &xml_escape(&Value::Array(profiles).to_string()));
    out = upsert_string(&out, "wawona.activeMachineId.v1", &active);
    for (name, v) in [
        ("hasSeenWelcome", true),
        ("wawona.machineProfilesMigrated.v1", true),
        ("waypipeSSHEnabled", false),
        ("touchpadMode", false),
    ] {
        out = upsert_bool(&out, name, v);
    }
    out
}

pub fn set_android(client: &str, adb: &Adb) -> Result<()> {
    let key = prefs_key(client)?;
    let prefs = "shared_prefs/wawona_prefs.xml";
    adb.quiet(&format!("am force-stop {ANDROID_ID}"));
    if !adb.quiet(&format!("run-as {ANDROID_ID} mkdir -p shared_prefs")) {
        bail!("run-as {ANDROID_ID} failed (install a debuggable build first)");
    }
    let current = adb
        .shell(&format!("run-as {ANDROID_ID} cat {prefs}"))
        .filter(|s| s.contains("<map"))
        .unwrap_or_else(|| "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n<map>\n</map>\n".into());
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH)?.as_millis() as u64;
    let body = android_prefs(&current, client, key, now);
    let mut c = adb.command();
    c.args(["shell", &format!("run-as {ANDROID_ID} sh -c 'cat > {prefs}'")]).stdin(std::process::Stdio::piped());
    let mut child = c.spawn()?;
    std::io::Write::write_all(child.stdin.as_mut().unwrap(), body.as_bytes())?;
    if !child.wait()?.success() {
        bail!("writing {prefs} failed");
    }
    eprintln!("== Android prefs: nativeLauncher={client} ({}) ==", adb.serial);
    Ok(())
}

#[cfg(test)]
mod tests {
    #[test]
    fn android_prefs_rewrites_the_native_machine() {
        let xml = "<?xml version='1.0' ?>\n<map>\n<string name=\"wawona.machineProfiles.v1\">[{&quot;id&quot;:&quot;a&quot;,&quot;type&quot;:&quot;native&quot;}]</string>\n<boolean name=\"touchpadMode\" value=\"true\" />\n</map>\n";
        let out = super::android_prefs(xml, "niri", "NiriEnabled", 7);
        assert!(out.contains(r#"<string name="wawona.activeMachineId.v1">a</string>"#));
        assert!(out.contains(r#"<boolean name="touchpadMode" value="false" />"#));
        assert!(out.contains("&quot;nativeLauncher&quot;:&quot;niri&quot;"));
        assert!(out.contains("&quot;NiriEnabled&quot;:true"));
        assert!(out.trim_end().ends_with("</map>"));
    }

    #[test]
    fn optional_clients_skip_by_default() {
        assert!(super::skip_reason("ios", "wawona-shell").is_none());
        assert!(super::skip_reason("tvos", "vkcube").unwrap().contains("platform-targets"));
    }
}
