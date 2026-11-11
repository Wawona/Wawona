//! `cargo xtask secrets <verb>`: release secrets from SecretSpec (the private
//! pass store on a maintainer's machine, the environment on CI) into Fastlane,
//! GitHub Environment secrets and fastlane match. docs/maintainers/secrets.md.
//!
//! Values travel only in a child's environment or on its stdin, never in
//! argv, and are never printed.

use crate::util::*;
use anyhow::{bail, Context, Result};
use base64::Engine;
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::{Command, Stdio};

const MATCH_GIT_URL: &str = "git@github.com:aspauldingcode/apple-signing.git";
const SIGNING_REPO: &str = "aspauldingcode/apple-signing";
const APPLE: [&str; 9] = [
    "APPLE_ID",
    "TEAM_ID",
    "MATCH_PASSWORD",
    "APPLE_SIGNING_PAT",
    "ASC_KEY_ID",
    "ASC_ISSUER_ID",
    "ASC_P8",
    "DEVELOPER_ID_APPLICATION_P12_BASE64",
    "DEVELOPER_ID_INSTALLER_P12_BASE64",
];
const ANDROID: [&str; 5] = [
    "ANDROID_KEYSTORE_BASE64",
    "ANDROID_KEYSTORE_PASSWORD",
    "ANDROID_KEY_ALIAS",
    "ANDROID_KEY_PASSWORD",
    "PLAY_STORE_JSON_KEY",
];

#[derive(clap::Subcommand)]
pub enum Cmd {
    /// Check the local profile against the pass store.
    Check,
    /// Run a command with the release secrets (profile from SECRETSPEC_PROFILE:
    /// local, sync or ci). local also derives Fastlane's names.
    Run {
        #[arg(trailing_var_arg = true, allow_hyphen_values = true, required = true)]
        command: Vec<String>,
    },
    /// Copy the secrets into the release GitHub Environment.
    Sync {
        /// Skip the Android and Play secrets.
        #[arg(long)]
        apple_only: bool,
    },
    /// Create the match repository when missing and populate it.
    BootstrapSigning,
    /// Require "Verification report" on the development branch.
    Ruleset {
        #[arg(default_value = "Wawona/Wawona")]
        repo: String,
    },
    /// The local profile's derivation step, inside `secretspec run`.
    #[command(hide = true)]
    Derive {
        #[arg(trailing_var_arg = true, allow_hyphen_values = true, required = true)]
        command: Vec<String>,
    },
}

pub fn main(c: Cmd) -> Result<()> {
    std::env::set_current_dir(root())?;
    std::env::set_var(
        "SECRETSPEC_FILE",
        env_or("SECRETSPEC_FILE", &root().join("secretspec.toml").display().to_string()),
    );
    std::env::set_var(
        "PASSWORD_STORE_DIR",
        env_or("PASSWORD_STORE_DIR", &format!("{}/.password-store", env_or("HOME", ""))),
    );
    match c {
        Cmd::Check => check(),
        Cmd::Run { command } => run_with(&command),
        Cmd::Sync { apple_only } => sync(apple_only),
        Cmd::BootstrapSigning => bootstrap(),
        Cmd::Ruleset { repo } => ruleset(&repo),
        Cmd::Derive { command } => {
            for (k, v) in fastlane_names(&|k| std::env::var(k).ok().filter(|v| !v.is_empty())) {
                if std::env::var_os(&k).is_none() {
                    std::env::set_var(k, v);
                }
            }
            Err(Command::new(&command[0]).args(&command[1..]).exec().into())
        }
    }
}

fn b64(s: &str) -> String {
    base64::engine::general_purpose::STANDARD.encode(s)
}

/// Fastlane's and match's names for the SecretSpec values.
fn fastlane_names(get: &dyn Fn(&str) -> Option<String>) -> Vec<(String, String)> {
    let mut v = Vec::new();
    if let Some(id) = get("ASC_KEY_ID") {
        v.push(("APP_STORE_CONNECT_KEY_ID".into(), id));
    }
    if let Some(id) = get("ASC_ISSUER_ID") {
        v.push(("APP_STORE_CONNECT_ISSUER_ID".into(), id));
    }
    if let Some(p8) = get("ASC_P8") {
        v.push(("APP_STORE_CONNECT_API_KEY".into(), b64(&p8)));
    }
    if let Some(pat) = get("APPLE_SIGNING_PAT") {
        v.push(("MATCH_GIT_BASIC_AUTHORIZATION".into(), b64(&format!("x-access-token:{pat}"))));
    }
    v.push(("MATCH_GIT_URL".into(), get("MATCH_GIT_URL").unwrap_or_else(|| MATCH_GIT_URL.into())));
    v
}

/// The release shell's secretspec: an older global one lacks the project providers.
fn secretspec() -> Result<Command> {
    if std::env::var_os("IN_NIX_SHELL").is_some() && have("secretspec") {
        return Ok(cmd("secretspec"));
    }
    if !have("nix") {
        bail!("secretspec needs the release shell: nix develop .#release");
    }
    let mut n = cmd("nix");
    n.args(["develop", &format!("{}#release", root().display()), "--command", "secretspec"]);
    Ok(n)
}

fn check() -> Result<()> {
    let store = PathBuf::from(std::env::var("PASSWORD_STORE_DIR")?).join("secretspec/wawona");
    if !store.is_dir() {
        bail!("{} is missing: clone the private pass store first (docs/maintainers/secrets.md)", store.display());
    }
    run(secretspec()?.args(["check", "-P", "local"]))?;
    eprintln!("secretspec check -P local: OK");
    Ok(())
}

fn run_with(command: &[String]) -> Result<()> {
    let profile = env_or("SECRETSPEC_PROFILE", "local");
    let mut c = secretspec()?;
    match profile.as_str() {
        "ci" | "ci-apple" | "ci-android" => {
            c.env("SECRETSPEC_PROVIDER", env_or("SECRETSPEC_PROVIDER", "env"))
                .args(["run", "-P", &profile, "--"])
                .args(command);
        }
        "sync" => {
            c.args(["run", "-P", "sync", "--"]).args(command);
        }
        "local" | "development" => {
            c.args(["run", "-P", "local", "--"])
                .arg(std::env::current_exe()?)
                .args(["secrets", "derive", "--"])
                .args(command);
        }
        p => bail!("unknown SECRETSPEC_PROFILE={p} (local, sync or ci)"),
    }
    Err(c.exec().into())
}

/// One value from SecretSpec, read without echoing it.
fn get(profile: &str, key: &str) -> Result<String> {
    let o = secretspec()?.args(["get", "-P", profile, key]).stderr(Stdio::null()).output()?;
    let v = String::from_utf8(o.stdout)?.trim_end_matches('\n').to_string();
    if !o.status.success() || v.is_empty() {
        bail!("{key} is missing from the pass store (profile {profile}); see docs/maintainers/secrets.md");
    }
    Ok(v)
}

fn sync(apple_only: bool) -> Result<()> {
    let repo = env_or("GITHUB_REPO", "Wawona/Wawona");
    let env = env_or("WAWONA_RELEASE_ENVIRONMENT", "release-beta");
    let profile = env_or("SECRETSPEC_PROFILE", "sync");
    output(cmd("gh").args(["auth", "status"]))?;
    let keys: Vec<&str> = APPLE.iter().chain(if apple_only { &[][..] } else { &ANDROID[..] }).copied().collect();
    let mut values = Vec::new();
    for k in &keys {
        values.push((k.to_string(), get(&profile, k)?));
    }
    let lookup = |k: &str| values.iter().find(|(n, _)| n == k).map(|(_, v)| v.clone());
    let mut set: Vec<(String, String)> =
        values.iter().filter(|(k, _)| !k.starts_with("ASC_") && k != "APPLE_SIGNING_PAT").cloned().collect();
    set.extend(fastlane_names(&lookup).into_iter().filter(|(k, _)| k != "MATCH_GIT_URL"));
    output(cmd("gh").args(["api", "--method", "PUT", &format!("repos/{repo}/environments/{env}")]))?;
    for (name, value) in set {
        let mut gh =
            cmd("gh").args(["secret", "set", &name, "--env", &env, "--repo", &repo]).stdin(Stdio::piped()).spawn()?;
        gh.stdin.take().context("gh stdin")?.write_all(value.as_bytes())?;
        if !gh.wait()?.success() {
            bail!("gh secret set {name} failed");
        }
        eprintln!("set {name}");
    }
    if apple_only {
        eprintln!("skipped the Android and Play secrets (--apple-only)");
    }
    eprintln!("verify: gh secret list --env {env} --repo {repo}");
    Ok(())
}

/// A file only this user can read, removed when dropped.
struct Secret(PathBuf);

impl Secret {
    fn new(name: &str, body: &str) -> Result<Secret> {
        let p = std::env::temp_dir().join(format!("wawona-{}-{name}", std::process::id()));
        let mut f = std::fs::OpenOptions::new().write(true).create_new(true).mode(0o600).open(&p)?;
        f.write_all(body.as_bytes())?;
        Ok(Secret(p))
    }
}

impl Drop for Secret {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.0);
    }
}

fn bootstrap() -> Result<()> {
    let s = |k| get("local", k);
    let (apple_id, team, password) = (s("APPLE_ID")?, s("TEAM_ID")?, s("MATCH_PASSWORD")?);
    let (key_id, issuer, p8) = (s("ASC_KEY_ID")?, s("ASC_ISSUER_ID")?, s("ASC_P8")?);
    let p8_file = Secret::new("asc.p8", &format!("{p8}\n"))?;
    let api_key = serde_json::json!({"key_id": key_id, "issuer_id": issuer, "key": p8, "in_house": false});
    let api_key_file = Secret::new("asc-api-key.json", &api_key.to_string())?;
    if !root().join("fastlane/Matchfile").is_file() {
        bail!("fastlane/Matchfile is missing");
    }

    output(cmd("gh").args(["auth", "status"]))?;
    if try_output(cmd("gh").args(["repo", "view", SIGNING_REPO])).is_none() {
        eprintln!("creating {SIGNING_REPO}");
        let desc = "Encrypted Apple certs/profiles for Wawona (fastlane match)";
        run(cmd("gh").args(["repo", "create", SIGNING_REPO, "--private", "--description", desc]))?;
    }
    if try_output(cmd("gh").args(["api", &format!("repos/{SIGNING_REPO}/contents/README.md")])).is_none() {
        let readme = "# apple-signing\n\nEncrypted Apple certificates and provisioning profiles for Wawona.\n\n\
            Managed by [fastlane match](https://docs.fastlane.tools/actions/match/). Do not edit manually.\n\n\
            Populate with `cargo xtask secrets bootstrap-signing` from the Wawona repository.\n";
        let _ = try_output(cmd("gh").args([
            "api",
            &format!("repos/{SIGNING_REPO}/contents/README.md"),
            "--method",
            "PUT",
            "-f",
            "message=Initialize apple-signing for fastlane match",
            "-f",
            &format!("content={}", b64(readme)),
        ]));
    }

    let fastlane = |args: &[&str]| -> Command {
        let mut c = cmd("nix");
        c.args([
            "develop",
            ".#release",
            "--command",
            "env",
            "DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer",
            "fastlane",
        ])
        .args(args)
        .envs([
            ("LANG", "en_US.UTF-8"),
            ("LC_ALL", "en_US.UTF-8"),
            ("FASTLANE_IS_INTERACTIVE", "false"),
            ("MATCH_GIT_URL", MATCH_GIT_URL),
            ("APPLE_ID", &apple_id),
            ("MATCH_PASSWORD", &password),
            ("TEAM_ID", &team),
            ("SPACESHIP_CONNECT_API_KEY_ID", &key_id),
            ("SPACESHIP_CONNECT_API_KEY_ISSUER_ID", &issuer),
        ])
        .env("SPACESHIP_CONNECT_API_KEY_FILEPATH", &p8_file.0);
        c
    };
    let api = api_key_file.0.display().to_string();
    let matcher = |kind: &str, platform: &str, app: &str, force: bool| -> Result<()> {
        eprintln!("fastlane match {kind} ({platform}) for {app}");
        let mut args = vec![
            "match",
            kind,
            "--platform",
            platform,
            "--app_identifier",
            app,
            "--readonly",
            "false",
            "--api_key_path",
            &api,
        ];
        if force {
            args.push("--force");
        }
        run(&mut fastlane(&args))
    };
    let (main_app, watch_app) = ("com.aspauldingcode.Wawona", "com.aspauldingcode.Wawona.watch");
    let watch = env_or("MATCH_INCLUDE_WATCH", "1") == "1";
    if env_or("MATCH_USE_FASTFILE", "1") == "1" {
        // The lane also enables iCloud on the App ID and regenerates the App Store profiles.
        let mut c = fastlane(&["regenerate_signing"]);
        c.envs([("MATCH_FORCE", "1"), ("MATCH_READONLY", "0"), ("APP_STORE_CONNECT_KEY_ID", &key_id)])
            .envs([("APP_STORE_CONNECT_ISSUER_ID", &issuer), ("APP_STORE_CONNECT_API_KEY", &b64(&format!("{p8}\n")))]);
        run(&mut c)?;
    } else {
        let force = env_or("MATCH_FORCE", "1") == "1";
        matcher("appstore", "ios", main_app, force)?;
        matcher("appstore", "tvos", main_app, force)?;
        if watch {
            matcher("appstore", "ios", watch_app, force)?;
        }
    }
    matcher("development", "ios", main_app, false)?;
    if watch {
        matcher("development", "ios", watch_app, false)?;
    }
    eprintln!("{SIGNING_REPO} is populated; verify with: gh repo view {SIGNING_REPO}");
    Ok(())
}

fn ruleset(repo: &str) -> Result<()> {
    let name = "Verification report required";
    let body = serde_json::json!({
        "name": name,
        "target": "branch",
        "enforcement": "active",
        "conditions": {"ref_name": {"include": ["refs/heads/development"], "exclude": []}},
        "rules": [{"type": "required_status_checks", "parameters": {
            "strict_required_status_checks_policy": false,
            "do_not_enforce_on_create": true,
            "required_status_checks": [{"context": "Verification report"}]}}],
        "bypass_actors": [{"actor_id": 1, "actor_type": "OrganizationAdmin", "bypass_mode": "always"}],
    });
    let list: Vec<serde_json::Value> =
        serde_json::from_str(&output(cmd("gh").args(["api", &format!("repos/{repo}/rulesets")]))?)?;
    let (method, path) = match list.iter().find(|r| r["name"] == name).and_then(|r| r["id"].as_u64()) {
        Some(id) => ("PUT", format!("repos/{repo}/rulesets/{id}")),
        None => ("POST", format!("repos/{repo}/rulesets")),
    };
    let mut gh = cmd("gh").args(["api", &path, "--method", method, "--input", "-"]).stdin(Stdio::piped()).spawn()?;
    gh.stdin.take().context("gh stdin")?.write_all(body.to_string().as_bytes())?;
    if !gh.wait()?.success() {
        bail!("gh api {method} {path} failed");
    }
    eprintln!("{} the ruleset on {repo}", if method == "PUT" { "updated" } else { "created" });
    Ok(())
}

#[cfg(test)]
mod tests {
    #[test]
    fn fastlane_names_derive_from_secretspec() {
        let get = |k: &str| match k {
            "ASC_KEY_ID" => Some("K".to_string()),
            "ASC_P8" => Some("p8".to_string()),
            "APPLE_SIGNING_PAT" => Some("pat".to_string()),
            _ => None,
        };
        let v = super::fastlane_names(&get);
        let find = |k: &str| v.iter().find(|(n, _)| n == k).map(|(_, x)| x.as_str());
        assert_eq!(find("APP_STORE_CONNECT_KEY_ID"), Some("K"));
        assert_eq!(find("APP_STORE_CONNECT_API_KEY"), Some("cDg="));
        assert_eq!(find("MATCH_GIT_BASIC_AUTHORIZATION"), Some("eC1hY2Nlc3MtdG9rZW46cGF0"));
        assert_eq!(find("MATCH_GIT_URL"), Some(super::MATCH_GIT_URL));
        assert_eq!(find("APP_STORE_CONNECT_ISSUER_ID"), None);
    }
}
