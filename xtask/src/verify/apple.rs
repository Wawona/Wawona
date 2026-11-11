use super::android::flake_outputs;
use super::{files_under, line_count, Check, Opts};
use crate::util::*;
use anyhow::Result;
use regex::Regex;

const WORKFLOWS: &str = ".github/workflows";

/// Apple jobs select the pinned Xcode (select-xcode.sh, directly or through
/// setup-xtask) and warm the platform SDKs so xcodebuild skips -downloadPlatform.
pub fn sdk_warm(c: &mut Check, _: &Opts) -> Result<String> {
    let warm = ".github/scripts/warm-ios-simulator-sdk.sh";
    let select = ".github/scripts/select-xcode.sh";
    for s in [warm, select] {
        if !c.path(s).is_file() {
            c.fail(format!("missing {s}"));
        } else if try_output(cmd("bash").arg("-n").arg(c.path(s))).is_none() {
            c.fail(format!("{s}: bash -n failed"));
        }
    }
    let newest = Regex::new(r"sort\s+-V\s*\|\s*tail\s+-1")?;
    if let Some(t) = c.text(select) {
        for n in ["DEFAULT_XCODE_APP=", "Pinned Xcode not found"] {
            if !t.contains(n) {
                c.fail(format!("select-xcode.sh: missing {n:?} (the fail-closed pin)"));
            }
        }
        if newest.is_match(&t) {
            c.fail("select-xcode.sh: reintroduced newest-Xcode selection");
        }
    }
    let action = c.text(".github/actions/setup-xtask/action.yml").unwrap_or_default();
    if !action.contains(select) {
        c.fail("setup-xtask must run select-xcode.sh");
    }
    for wf in ["product-ios-sim.yml", "product-apple-family.yml", "device-e2e-ios.yml"] {
        c.need(&format!("{WORKFLOWS}/{wf}"), &[warm], "warm the simulator SDKs");
    }
    if let Some(t) = c.text(&format!("{WORKFLOWS}/product-apple-family.yml")) {
        if !t.contains("warm-ios-simulator-sdk.sh all") {
            for p in ["ipados", "tvos", "watchos", "visionos"] {
                if !Regex::new(&format!(r"warm-ios-simulator-sdk\.sh[^\n]*\b{p}\b"))?.is_match(&t) {
                    c.fail(format!("product-apple-family.yml: the warm script must be passed {p} or all"));
                }
            }
        }
    }
    let pinned = [
        "product-ios-sim.yml",
        "product-apple-family.yml",
        "product-macos-app.yml",
        "product-ios-modeb.yml",
        "device-e2e-ios.yml",
        "nix.yml",
        "release-beta.yml",
    ];
    for p in files_under(&c.root, WORKFLOWS, ".yml") {
        let (name, t) = (p.file_name().unwrap().to_string_lossy().into_owned(), read(&p)?);
        if newest.is_match(&t) {
            c.fail(format!("{name}: reintroduced newest-Xcode selection (sort -V | tail -1)"));
        }
        if pinned.contains(&name.as_str()) && !t.contains(select) && !t.contains("./.github/actions/setup-xtask") {
            c.fail(format!("{name}: must select the pinned Xcode (setup-xtask or select-xcode.sh)"));
        }
    }
    Ok("pinned Xcode, warmed SDKs".into())
}

/// The in-process shell commands in the store app stay on public APIs. Mode B
/// tools (Procursus, private LaunchServices) are repo.wawona.io debs.
pub fn darwin_cli_mode_a(c: &mut Check, _: &Opts) -> Result<String> {
    let mut files: Vec<String> = files_under(&c.root, "src/darwin_cli", ".rs").iter().map(|p| c.rel(p)).collect();
    files.extend([
        "Sources/WawonaApple/Shell/DarwinCli.swift".into(),
        "Sources/WawonaApple/Shell/DarwinCli+HostB.swift".into(),
    ]);
    for f in &files {
        c.forbid(
            f,
            &[
                "LSApplicationWorkspace",
                "FrontBoardServices",
                "BackBoardServices",
                "MobileGestalt",
                "libroot",
                "/var/jb",
                "jbroot",
                "_CFCopySystemVersionDictionary",
                "objc_getClass",
                "dlopen(",
                "SpringBoard",
                "IOMobileFramebuffer",
                "procursus",
            ],
            "Mode B token in a Mode A CLI source",
        );
    }
    for dir in ["src/platform/ios", "Sources/WawonaApple"] {
        for p in files_under(&c.root, dir, "") {
            if p.file_name().unwrap().to_string_lossy().to_lowercase().contains("jailbreak") {
                c.fail(format!("jailbreak source must not live in the app target: {}", c.rel(&p)));
            }
        }
    }
    Ok(format!("{} sources, public APIs only", files.len()))
}

/// Apple mobile SSH is libssh2 ssh-cli, never OpenSSH; the uutils features
/// match wwn-uutils-rs's safe-subset.txt; no shell backend moves into Swift.
pub fn ios_shell_tools(c: &mut Check, _: &Opts) -> Result<String> {
    flake_outputs(
        c,
        &[
            "zsh-ios",
            "zsh-ios-sim",
            "zsh-android",
            "fastfetch-ios",
            "fastfetch-ios-device",
            "fastfetch-android",
            "phoon-ios",
            "phoon-ios-sim",
            "phoon-ios-device",
            "phoon-tvos",
            "phoon-watchos",
            "phoon-visionos",
            "phoon-android",
            "phoon-macos",
            "phoon",
            "wawona-pty-ios",
            "wawona-pty-ios-sim",
            "wawona-rootfs-ios",
            "wawona-rootfs-ios-sim",
        ],
    );
    let flake = c.text("flake.nix").unwrap_or_default();
    for key in ["openssh-ios", "openssh-ios-sim"] {
        if Regex::new(&format!(r#"(?m)^\s*"?{}"?\s*="#, regex::escape(key)))?.is_match(&flake) {
            c.fail(format!("flake.nix must not expose product output: {key}"));
        }
    }
    let deps = "dependencies/wawona/deps.nix";
    c.need(deps, &["libwawona-zsh.a", "libfastfetch.a", "libwwn-ssh-cli.a"], "shell-tool wiring");
    c.forbid(deps, &["libssh-inprocess.a"], "Apple mobile never links OpenSSH");
    let mobile = "dependencies/wawona/mobile-platform-deps.nix";
    if let Some(t) = c.text(mobile) {
        if !t.contains("buildFn \"ssh-cli\"") && !t.contains("\"ssh-cli\" = buildFn") {
            c.fail(format!("{mobile} must build ssh-cli (\"ssh-cli\" = buildFn \"ssh-cli\" {{ ... }})"));
        }
        if t.contains("openssh = buildFn \"openssh\"") {
            c.fail(format!("{mobile} must not build openssh on Apple mobile (ssh-cli and libssh2 only)"));
        }
    }
    let prebuild = "xtask/src/xcode.rs";
    c.need(prebuild, &["libwawona-zsh.a", "libfastfetch.a"], "the prebuild privatizes the keep-set mains");
    c.forbid(prebuild, &["libphoon_rs.a"], "pure Rust phoon is force-loaded, not privatized");
    fastfetch_lock(c, &flake)?;
    no_strong_ssh_stubs(c);
    coreutils_subset(c, &flake)?;
    for dir in ["Sources/WawonaApple", "Sources/WawonaUI", "Darwin"] {
        for p in files_under(&c.root, dir, ".swift") {
            let t = read(&p)?;
            for bad in ["import NIOSSH", "import IOSSystem", "ios_system/", "NIOSSHHandler"] {
                if t.contains(bad) {
                    c.fail(format!("{}: forbidden Swift shell backend ({bad})", c.rel(&p)));
                }
            }
        }
    }
    Ok("libssh2 ssh-cli; catalog fastfetch; uutils safe subset; no Swift shell backends".into())
}

/// The keep-set fastfetch comes from the repo.wawona.io in-app catalog.
fn fastfetch_lock(c: &mut Check, flake: &str) -> Result<()> {
    const MARKER: &str = "catalog/deb/cli/fastfetch/in-app";
    let Some(lock) = c.text("flake.lock") else { return Ok(()) };
    let lock: serde_json::Value = serde_json::from_str(&lock)?;
    let nodes = &lock["nodes"];
    if !nodes["wwn-fastfetch"].is_null() {
        c.fail(format!("flake.lock must not pin the deleted wwn-fastfetch; use repo-wawona-io {MARKER}"));
    }
    match nodes["repo-wawona-io"]["locked"]["lastModified"].as_i64() {
        None => c.fail("flake.lock missing the repo-wawona-io input (hosts the in-app fastfetch)"),
        Some(m) if m < 1_782_867_491 => c.fail(format!("repo-wawona-io lock too old (lastModified {m})")),
        _ => {}
    }
    if !flake.contains(MARKER) {
        c.fail(format!("flake.nix missing the in-app fastfetch path ({MARKER})"));
    }
    if flake.contains("wwn-fastfetch.url") || flake.contains("inputs.wwn-fastfetch") {
        c.fail("flake.nix must not re-add the wwn-fastfetch input");
    }
    Ok(())
}

/// A strong `ssh_main` stub would shadow libwwn-ssh-cli.a.
fn no_strong_ssh_stubs(c: &mut Check) {
    for rel in ["src/platform/ios/WWNAppleMobileOptionalStubs.c", "src/platform/watchos/WWNWatchStubs.c"] {
        let Ok(t) = std::fs::read_to_string(c.path(rel)) else { continue };
        let lines: Vec<&str> = t.lines().collect();
        for sym in ["ssh_main", "ssh_keygen_main", "scp_main"] {
            let re = Regex::new(&format!(r"\bint\s+{sym}\s*\(")).unwrap();
            for (i, l) in lines.iter().enumerate() {
                if re.is_match(l) && !(i > 0 && lines[i - 1].contains("__attribute__((weak))")) {
                    c.fail(format!("{rel} defines a strong {sym} stub; link libwwn-ssh-cli.a"));
                }
            }
        }
    }
}

/// wwn-uutils-rs owns safe-subset.txt: a sibling checkout, WWN_UUTILS_RS, or
/// the flake input.
fn coreutils_subset(c: &mut Check, flake: &str) -> Result<()> {
    const REL: &str = "dependencies/libs/coreutils/safe-subset.txt";
    let mut dirs: Vec<std::path::PathBuf> = ["WWN_COREUTILS", "WWN_UUTILS_RS"]
        .iter()
        .filter_map(|k| std::env::var(k).ok().filter(|v| !v.is_empty()).map(Into::into))
        .collect();
    dirs.extend(["wwn-uutils-rs", "wwn-coreutils"].map(|r| c.root.parent().unwrap().join(r)));
    let mut subset = dirs.iter().map(|d| d.join(REL)).find(|p| p.is_file());
    if subset.is_none() {
        let flake_ref = format!("(builtins.getFlake \"{}\").inputs.wwn-uutils-rs.outPath", c.root.display());
        subset = try_output(cmd("nix").args(["eval", "--raw", "--impure", "--expr", &flake_ref]))
            .map(|o| std::path::Path::new(&o).join(REL))
            .filter(|p| p.is_file());
    }
    let Some(subset) = subset else {
        c.fail("cannot find wwn-uutils-rs safe-subset.txt (set WWN_UUTILS_RS or check it out beside this one)");
        return Ok(());
    };
    let authority: Vec<String> = read(&subset)?
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .map(Into::into)
        .collect();
    let cargo = c.text("Cargo.toml").unwrap_or_default();
    let feats = Regex::new(r#"(?ms)^coreutils\s*=\s*\{[^}]*features\s*=\s*\[([^\]]*)\]"#)?.captures(&cargo).map(|m| {
        Regex::new(r#""([a-z][a-z0-9-]*)""#).unwrap().captures_iter(&m[1]).map(|f| f[1].to_string()).collect::<Vec<_>>()
    });
    match feats {
        None => c.fail("Cargo.toml: missing the optional coreutils features = [...]"),
        Some(f) if f != authority => c.fail(format!(
            "Cargo.toml coreutils features must match {}: cargo={f:?} authority={authority:?}",
            subset.display()
        )),
        _ => {}
    }
    if Regex::new(r"coreutils-src\s*=\s*[^\n]*fetchFromGitHub")?.is_match(flake) {
        c.fail("flake.nix must take coreutils-src from wwn-uutils-rs.lib.coreutilsSrc, not fetchFromGitHub");
    }
    if !flake.contains("wwn-uutils-rs.lib.coreutilsSrc") && !flake.contains("wwn-coreutils.lib.coreutilsSrc") {
        c.fail("flake.nix missing wwn-uutils-rs.lib.coreutilsSrc for coreutils-src");
    }
    Ok(())
}

/// Wawona's Apple code is Rust plus Swift: no ObjC classes anywhere in this
/// checkout or the sibling repos that ship in the app, no Swift under
/// src/platform, and Sources/WawonaApple files under 400 lines.
pub fn no_objc_glue(c: &mut Check, _: &Opts) -> Result<String> {
    let ws = c.root.parent().unwrap().to_path_buf();
    let mut roots: Vec<std::path::PathBuf> =
        ["src", "scripts", "dependencies/clients", "dependencies/tools"].iter().map(|d| c.root.join(d)).collect();
    roots.extend(
        [
            "iLand",
            "wwn-iomfb-rs",
            "wwn-igetty",
            "Wawona-Swinging-Bridge",
            "doorman",
            "wwn-vphone/patches",
            "agent-device/apple-runner",
            "wwn-vms",
        ]
        .map(|d| ws.join(d)),
    );
    let ignored = |p: &std::path::Path| {
        p.components().any(|c| {
            let s = c.as_os_str().to_string_lossy();
            matches!(
                s.as_ref(),
                ".git"
                    | "node_modules"
                    | "target"
                    | "build"
                    | "vendor-research"
                    | "inspirational_projects"
                    | ".cache"
                    | "chess-for-linux"
            ) || s.starts_with(".derivedData")
        }) || p.to_string_lossy().contains("data/corpus")
    };
    let show = |p: &std::path::Path| p.strip_prefix(&ws).unwrap_or(p).display().to_string();
    let mut scanned = 0;
    for r in roots.iter().filter(|r| r.is_dir()) {
        for e in walkdir::WalkDir::new(r).into_iter().filter_entry(|e| !ignored(e.path())).filter_map(|e| e.ok()) {
            let p = e.path();
            let ext = p.extension().map(|x| x.to_string_lossy().into_owned()).unwrap_or_default();
            if !e.file_type().is_file() || !["c", "cc", "cpp", "h", "hpp", "swift", "m", "mm"].contains(&ext.as_str()) {
                continue;
            }
            if ext == "m" || ext == "mm" {
                scanned += 1;
                c.fail(format!("Objective-C source: {} ({} lines)", show(p), line_count(p)));
                continue;
            }
            let t = String::from_utf8_lossy(&std::fs::read(p)?).into_owned();
            if let Some(i) = t.lines().position(|l| l.contains("@implementation")) {
                c.fail(format!("@implementation in {}:{}", show(p), i + 1));
            }
        }
    }
    for plat in ["macos", "ios", "watchos"] {
        for p in files_under(&c.root, &format!("src/platform/{plat}"), ".swift") {
            c.fail(format!("Swift under src/platform/{plat} is forbidden; use Sources/WawonaApple: {}", c.rel(&p)));
        }
    }
    for p in files_under(&c.root, "Sources/WawonaApple", ".swift") {
        let n = line_count(&p);
        if n > 400 {
            c.fail(format!("Sources/WawonaApple file over 400 lines: {} ({n})", c.rel(&p)));
        }
    }
    for ghost in
        ["wwn-vms/dependencies/vms/utm/sources/UTMProcess.m", "wwn-vms/dependencies/vms/utm/sources/UTMQemuSystem.m"]
    {
        if ws.join(ghost).is_file() {
            c.fail(format!("dead UTM ObjC must stay deleted: {ghost}"));
        }
    }
    Ok(format!("{} roots, {scanned} ObjC files", roots.iter().filter(|r| r.is_dir()).count()))
}

/// One Global Settings host per platform, inside the app.
pub fn settings_in_app(c: &mut Check, _: &Opts) -> Result<String> {
    for p in [
        "src/resources/Settings.bundle",
        "src/resources/Settings-Watch.bundle",
        "Sources/WawonaApple/Lifecycle/WawonaPrefPaneRootView.swift",
        "Sources/WawonaApple/Lifecycle/WawonaSystemPreferencePane.swift",
        "Sources/WawonaApple/Lifecycle/PrefPaneEnvironmentVariablesView.swift",
        "Sources/WawonaApple/Lifecycle/WawonaPrefPaneStubs.swift",
        "src/platform/macos/ui/Settings/PrefPane",
    ] {
        c.must_not_exist(p, "retired OS Settings host");
    }
    c.forbid(
        "Wawona.xcodeproj/project.xcproj",
        &["Wawona-PrefPane", "Settings.bundle", "Settings-Watch.bundle", "WWN_PREFPANE", "Bundle Preference Pane"],
        "retired OS Settings host",
    );
    for f in [
        "Sources/WawonaUI/Settings/PlatformGlobalSettings.swift",
        "Sources/WawonaUI/Settings/WawonaSystemSettings.swift",
        "Sources/WawonaApple/Settings/WWNPreferences.swift",
        "Sources/WawonaApple/Lifecycle/WawonaMenuBarController.swift",
        "Sources/WawonaApple/Lifecycle/WawonaSystemSettingsBridge.swift",
        "Darwin/Sources/Main.swift",
        "android/app/src/main/AndroidManifest.xml",
    ] {
        c.forbid(
            f,
            &[
                "x-apple.systempreferences:com.aspauldingcode.Wawona.prefPane",
                "UIApplication.openSettingsURLString",
                "ACTION_APPLICATION_PREFERENCES",
                "WWN_PREFPANE",
            ],
            "opens an OS Settings host",
        );
    }
    let main = "Sources/WawonaUI/WawonaMainWindowView.swift";
    c.need(main, &["GlobalSettingsCatalog.visibleSections"], "the in-app Global Settings catalog");
    if Regex::new(r"(?s)catalogSections:.*appSidebarSections")?.is_match(&c.text(main).unwrap_or_default()) {
        c.fail(format!("{main}: catalogSections must not use appSidebarSections"));
    }
    let watch = c.text("Sources/WawonaWatch/WatchKitGlobalSettings.swift").unwrap_or_default();
    if watch.contains("iPhone Watch app") && !watch.contains("Toggle(") {
        c.fail("WatchKitGlobalSettings.swift must host an in-app catalog, not a redirect");
    }
    Ok("in-app Global Settings only".into())
}

pub fn ssh_backends(c: &mut Check, _: &Opts) -> Result<String> {
    let deps = "dependencies/wawona/deps.nix";
    c.need(deps, &["libwwn-ssh-cli.a", "ssh-cli"], "Apple mobile SSH is libssh2 ssh-cli");
    c.forbid(deps, &["libssh-inprocess.a"], "never OpenSSH on Apple mobile");
    c.need(
        "dependencies/wawona/mobile-platform-deps.nix",
        &["\"ssh-cli\"", "libssh2", "Never OpenSSH"],
        "Apple mobile SSH is libssh2 ssh-cli",
    );
    c.need("src/platform/android/android_jni.c", &["StrictHostKeyChecking", "libssh_bin.so"], "Android runs OpenSSH");
    c.forbid("src/platform/android/android_jni.c", &["dropbearconvert"], "no Dropbear");
    no_strong_ssh_stubs(c);
    for g in [
        "src/platform/macos/WWNSSHClient.m",
        "src/platform/macos/WWNSSHClient.h",
        "src/platform/macos/ssh/WWNSSHClient.m",
        "src/platform/macos/ssh/WWNSSHClient.h",
    ] {
        c.must_not_exist(g, "the ObjC SSH client is retired");
    }
    Ok("Apple libssh2 ssh-cli; Android OpenSSH".into())
}

/// waypipe exec()s the remote command, so a bare `VAR=val cmd` prefix makes
/// `VAR=val` argv[0] (issue #54); the sway fallback must start with env(1).
pub fn waypipe_sway_env(c: &mut Check, _: &Opts) -> Result<String> {
    let rel = "Sources/WawonaApple/Runners/WaypipeRunner.swift";
    let Some(t) = c.text(rel) else { return Ok(String::new()) };
    if !Regex::new(r#"String\(format:\s*"env %@ %@""#)?.is_match(&t) {
        c.fail(format!("{rel}: the remote sway fallback must build `env %@ %@` (issue #54)"));
    }
    if Regex::new(r#"String\(format:\s*"%@ %@"[\s\S]{0,200}WLR_RENDERER"#)?.is_match(&t) {
        c.fail(format!("{rel}: the remote sway fallback still emits a bare `VAR=val cmd` prefix"));
    }
    c.need(rel, &["WLR_RENDERER=pixman", "WLR_NO_HARDWARE_CURSORS=1"], "the remote sway software-render fallback");
    Ok("issue #54 guard".into())
}

/// Relay (wwn-relay) owns Mode A WASI; wawona-wasm links on every product
/// target, watchOS included. The runtime smoke is Gate: wasm-wayland.
pub fn wasm(c: &mut Check, _: &Opts) -> Result<String> {
    c.need(
        "flake.nix",
        &[
            "wwn-relay.url",
            "wawona-wasm-ios",
            "wawona-wasm-macos",
            "wawona-wasm-android",
            "wawona-wasm-watchos",
            "wawona-wasm-watchos-sim",
        ],
        "Relay wasm on every target",
    );
    if let Some(lock) = c.text("flake.lock") {
        let lock: serde_json::Value = serde_json::from_str(&lock)?;
        match lock["nodes"]["wwn-relay"]["locked"]["type"].as_str() {
            None => c.fail("flake.lock missing the wwn-relay input (owns Mode A WASI)"),
            Some(t) if !["github", "tarball", "indirect"].contains(&t) => {
                c.fail(format!("wwn-relay lock type unexpected: {t}"))
            }
            _ => {}
        }
    }
    let deps = "dependencies/wawona/deps.nix";
    c.need(deps, &["-lwawona_wasm", "\"wawona_wasm_run\""], "Relay wasm links into the app");
    c.need(
        deps,
        &["++ wasm d ++ lib.optionals (!watch) (relay d)"],
        "wawona-wasm on every mobile slice, watchOS included",
    );
    let mobile = c.text("dependencies/wawona/mobile-platform-deps.nix").unwrap_or_default();
    if !mobile.contains("buildFn \"wawona-wasm\"") && !mobile.contains("\"wawona-wasm\" = buildFn") {
        c.fail("mobile-platform-deps.nix must build \"wawona-wasm\" on mobile, tv, watch and vision");
    }
    if !mobile.contains("variant == \"watch\"") {
        c.fail("mobile-platform-deps.nix must include watch in the wawona-wasm optionalAttrs");
    }
    c.need("docs/wwn-repo-dag.md", &["wwn-relay"], "the DAG names Relay");
    c.text("docs/wasm-wasi.md");
    let launch = c.text("Sources/WawonaModel/ClientLauncher.swift").unwrap_or_default();
    if !launch.contains("allowsWasmRuntime") {
        c.fail("ClientLauncher must gate wawona-wasm with allowsWasmRuntime");
    }
    if launch.contains("#if os(watchOS)") && launch.contains("wawona-wasm") {
        c.fail("ClientLauncher must not special-case watchOS off for wasm");
    }
    c.need(
        "Sources/WawonaApple/Watch/WatchCompositorBridge.swift",
        &["launchWasmModuleAtPath", "wawona_wasm_run"],
        "the watch compositor runs wasm through Relay Pulley",
    );
    Ok("Relay wawona-wasm wiring".into())
}
