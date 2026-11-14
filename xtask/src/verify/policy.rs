//! Repository-wide language policy.

use super::{Check, Opts};
use crate::util::{cmd, output, read};
use anyhow::Result;
use regex::Regex;

const CALL: &str = r"(^|[^\w./-])(python[23]?(\.\d+)?|pip[23]?|pytest|pipx|uvx)([^\w-]|$)|setup-(python|uv)\b";

/// #67 profile schema lift: hosts must call rust store when linked; mirrors
/// stay adapters, not owners.
pub fn profile_schema_lift(c: &mut Check, _: &Opts) -> Result<String> {
    c.need(
        "src/domain/machine_profile.rs",
        &["hostUiBlob", "uniffi::Record", "wawona.machineProfiles.v1"],
        "rust owns the profile schema + hostUiBlob for Android UI bag",
    );
    c.need(
        "src/domain/c_api.rs",
        &[
            "wawona_profiles_v1_decode",
            "wawona_profiles_v1_put",
            "wawona_profiles_v1_delete",
        ],
        "C trampolines for hosts without generated UniFFI",
    );
    c.need(
        "Sources/WawonaModel/MachineProfile.swift",
        &["MachineProfileDomain.rustAvailable", "MachineProfileDomain.put"],
        "Apple store fails closed when rust is linked",
    );
    c.need(
        "Sources/WawonaModel/MachineProfileDomain.swift",
        &["wawona_profiles_v1_decode", "wawona_profiles_v1_put"],
        "Apple domain bridge",
    );
    // Product Compose host under android/app is deleted (Exact Android host).
    // Legacy Kotlin mirrors may still exist under quarantine; require JNI C.
    for (path, needles, why) in [
        (
            "android/app/src/main/java/com/aspauldingcode/wawona/WawonaNative.kt",
            &["nativeProfilesV1Decode", "nativeProfilesV1Put", "nativeProfilesV1Delete"][..],
            "Android JNI profile store",
        ),
        (
            "android/app/src/main/java/com/aspauldingcode/wawona/MachineProfiles.kt",
            &["nativeProfilesV1Decode", "nativeProfilesV1Put", "serializeCanonical", "hostUiBlob"][..],
            "Android store routes through rust + canonical JSON",
        ),
    ] {
        if c.root.join(path).is_file() {
            c.need(path, needles, why);
        }
    }
    c.need(
        "src/platform/android/android_jni.c",
        &["nativeProfilesV1Decode", "wawona_profiles_v1_put"],
        "JNI wires rust profile trampolines",
    );
    Ok("apple+android profile store → rust (Exact Android host)".into())
}

/// Python as a file, shebang, CI action or command anywhere Wawona's build,
/// CI, tests or tools execute. Prose (docs, comments, UI strings) may name it,
/// and so may system packages a third-party driver pulls in (`python3-*`).
pub fn no_python(c: &mut Check, _: &Opts) -> Result<String> {
    let tracked =
        output(cmd("git").current_dir(&c.root).args(["ls-files", "--cached", "--others", "--exclude-standard"]))?;
    let call = Regex::new(CALL)?;
    let banned_name = Regex::new(
        r"(\.py[iwc]?|\.ipynb|(^|/)(requirements[\w-]*\.txt|pyproject\.toml|setup\.cfg|Pipfile(\.lock)?|tox\.ini))$",
    )?;
    let executes = Regex::new(
        r"(^\.github/|^fastlane/|\.nix$|\.sh$|\.rs$|\.kts$|\.gradle$|\.pbxproj$|\.xcconfig$|(^|/)Makefile$|(^|/)Fastfile$|\.ad$)",
    )?;
    let mut n = 0;
    for rel in tracked.lines() {
        if rel.starts_with("xtask/src/verify/policy.rs") || !c.root.join(rel).is_file() {
            continue;
        }
        if banned_name.is_match(rel) {
            c.fail(format!("{rel}: Python source or packaging; port it to cargo xtask"));
            continue;
        }
        if !executes.is_match(rel) && !rel.starts_with("scripts/") {
            continue;
        }
        let Ok(text) = read(c.root.join(rel)) else { continue };
        n += 1;
        for (i, line) in text.lines().enumerate() {
            let code = line.trim_start();
            if i == 0 && code.starts_with("#!") && code.contains("python") {
                c.fail(format!("{rel}:1: Python shebang"));
            }
            if code.starts_with('#') || code.starts_with("//") || code.starts_with("///") {
                continue;
            }
            if call.is_match(line) {
                c.fail(format!("{rel}:{}: {}", i + 1, code));
            }
        }
    }
    Ok(format!("{n} build, CI and tool files"))
}

#[cfg(test)]
mod tests {
    use super::CALL;
    use regex::Regex;

    #[test]
    fn matches_commands_not_packages() {
        let call = Regex::new(CALL).unwrap();
        for hit in [
            "python3 x.py",
            "run: pytest -q",
            "uses: actions/setup-python@v5",
            "uses: astral-sh/setup-uv@v6",
            "uvx zizmor",
            "  pip install x",
            "python3.12 -c",
        ] {
            assert!(call.is_match(hit), "{hit}");
        }
        for miss in ["apt-get install python3-pyatspi", "pythonPackages", "mypython", "docker.io/library/python3-slim"]
        {
            assert!(!call.is_match(miss), "{miss}");
        }
    }
}
