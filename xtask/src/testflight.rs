//! Imports TestFlight feedback (App Store Connect API beta feedback
//! screenshot and crash submissions) into GitHub issues. Tester identity and
//! other personal data are stripped, and screenshots are re-encoded so no
//! EXIF or GPS survives. An HTML comment in the issue body dedupes runs.
//! https://developer.apple.com/documentation/appstoreconnectapi/beta-feedback-screenshot-submissions
//!
//! Auth: APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID and
//! APP_STORE_CONNECT_API_KEY (the base64 .p8 Ship: beta uses).

use std::collections::{HashMap, HashSet};
use std::sync::LazyLock;

use anyhow::{bail, Context, Result};
use base64::Engine;
use regex::Regex;
use serde_json::{json, Value};

use crate::util::{cmd, output};

const ASC: &str = "https://api.appstoreconnect.apple.com";
const BUNDLE_PREFIX: &str = "com.aspauldingcode.Wawona";
const MARKER: &str = "testflight-id";
const SKIP_ATTRS: &[&str] = &[
    "email",
    "firstName",
    "lastName",
    "fullName",
    "udid",
    "serialNumber",
    "deviceName",
    "carrier",
    "timeZone",
    "location",
    "advertisingIdentifier",
    "vendorIdentifier",
    "ipAddress",
    "phoneNumber",
    "appleId",
    "accountName",
];

#[derive(clap::Args)]
pub struct Args {
    /// List new submissions without opening issues.
    #[arg(long)]
    dry_run: bool,
}

static REDACTIONS: LazyLock<Vec<(Regex, &'static str)>> = LazyLock::new(|| {
    [
        (r"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", "[redacted-email]"),
        (r"(?i)(password|passwd|secret|token|authorization|api[_-]?key)\s*[:=]\s*\S+", "${1}=[redacted]"),
        (r"/Users/[^/\s]+", "/Users/[redacted]"),
        (r"(?i)(?:/home/|C:\\Users\\)[^\s\\/]+", "[redacted-home]"),
        (r"(?i)\b[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\b", "[redacted-udid]"),
        (r"\b(?:\d{1,3}\.){3}\d{1,3}\b", "[redacted-ip]"),
        (r"(?i)\b(?:[0-9a-f]{0,4}:){2,7}[0-9a-f]{0,4}\b", "[redacted-ip]"),
    ]
    .into_iter()
    .map(|(re, to)| (Regex::new(re).unwrap(), to))
    .collect()
});

fn redact(text: &str) -> String {
    let mut out = text.to_string();
    for (re, to) in REDACTIONS.iter() {
        out = re.replace_all(&out, *to).into_owned();
    }
    out.trim().to_string()
}

fn keep_attr(key: &str) -> bool {
    if SKIP_ATTRS.contains(&key) {
        return false;
    }
    let k = key.to_lowercase();
    if !["email", "name", "udid", "serial", "token"].iter().any(|p| k.contains(p)) {
        return true;
    }
    if ["model", "version", "platform"].iter().any(|p| k.contains(p)) {
        return true;
    }
    !(k.contains("email") || k.contains("udid") || k.contains("serial") || k.ends_with("name"))
}

/// Scalar attributes that may leave App Store Connect, redacted.
fn sanitize(attrs: &Value) -> HashMap<String, String> {
    let Some(map) = attrs.as_object() else { return HashMap::new() };
    map.iter()
        .filter(|(k, _)| keep_attr(k))
        .filter_map(|(k, v)| {
            let text = match v {
                Value::String(s) => s.clone(),
                Value::Number(n) => n.to_string(),
                Value::Bool(b) => b.to_string(),
                _ => return None,
            };
            Some((k.clone(), redact(&text))).filter(|(_, t)| !t.is_empty())
        })
        .collect()
}

fn env_any(names: &[&str]) -> Option<String> {
    names.iter().find_map(|n| std::env::var(n).ok()).map(|v| v.trim().to_string()).filter(|v| !v.is_empty())
}

fn b64url(bytes: &[u8]) -> String {
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes)
}

/// An App Store Connect API token: an ES256 JWT, valid for 19 minutes.
/// https://developer.apple.com/documentation/appstoreconnectapi/generating-tokens-for-api-requests
fn token() -> Result<String> {
    use p256::ecdsa::{signature::Signer, Signature, SigningKey};
    use p256::pkcs8::DecodePrivateKey;
    let raw = env_any(&["APP_STORE_CONNECT_API_KEY", "ASC_P8"]).context("missing APP_STORE_CONNECT_API_KEY")?;
    let pem = if raw.contains("BEGIN PRIVATE KEY") {
        raw
    } else {
        let bytes = base64::engine::general_purpose::STANDARD
            .decode(raw.trim_end_matches('='))
            .or_else(|_| base64::engine::general_purpose::STANDARD_NO_PAD.decode(raw.trim_end_matches('=')))
            .context("APP_STORE_CONNECT_API_KEY is not base64")?;
        String::from_utf8(bytes).context("APP_STORE_CONNECT_API_KEY is not a base64 .p8")?
    };
    let kid = env_any(&["APP_STORE_CONNECT_KEY_ID", "ASC_KEY_ID"]).context("missing APP_STORE_CONNECT_KEY_ID")?;
    let iss = env_any(&["APP_STORE_CONNECT_ISSUER_ID", "ASC_ISSUER_ID"]).context("missing ISSUER_ID")?;
    let key = SigningKey::from_pkcs8_pem(&pem).context("APP_STORE_CONNECT_API_KEY is not a .p8 key")?;
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH)?.as_secs();
    let head = b64url(json!({ "alg": "ES256", "kid": kid, "typ": "JWT" }).to_string().as_bytes());
    let claims = json!({ "iss": iss, "iat": now, "exp": now + 19 * 60, "aud": "appstoreconnect-v1" });
    let input = format!("{head}.{}", b64url(claims.to_string().as_bytes()));
    let sig: Signature = key.sign(input.as_bytes());
    Ok(format!("{input}.{}", b64url(&sig.to_bytes())))
}

fn get(url: &str, bearer: Option<&str>) -> Result<Vec<u8>> {
    let mut req = ureq::get(url).header("User-Agent", "Wawona-testflight-import");
    if let Some(t) = bearer {
        req = req.header("Authorization", &format!("Bearer {t}")).header("Accept", "application/json");
    }
    let mut res = req.config().http_status_as_error(false).build().call().with_context(|| format!("GET {url}"))?;
    let body = res.body_mut().with_config().limit(64 << 20).read_to_vec()?;
    if !res.status().is_success() {
        let detail = String::from_utf8_lossy(&body);
        bail!("{} {url}: {}", res.status(), detail.chars().take(800).collect::<String>());
    }
    Ok(body)
}

fn get_json(url: &str, t: &str) -> Result<Value> {
    let body = get(url, Some(t))?;
    Ok(if body.is_empty() { json!({}) } else { serde_json::from_slice(&body)? })
}

/// Every page of a collection: its `data` rows and `included` resources.
fn paginate(t: &str, path: &str, query: &str) -> Result<(Vec<Value>, Vec<Value>)> {
    let (mut data, mut included) = (Vec::new(), Vec::new());
    let mut url = format!("{ASC}{path}?{query}");
    while !url.is_empty() {
        let page = get_json(&url, t)?;
        data.extend(page["data"].as_array().cloned().unwrap_or_default());
        included.extend(page["included"].as_array().cloned().unwrap_or_default());
        url = page["links"]["next"].as_str().unwrap_or_default().to_string();
    }
    Ok((data, included))
}

fn feedback_path(app_id: &str, resource: &str) -> String {
    let id: String = app_id
        .bytes()
        .map(|b| match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => (b as char).to_string(),
            _ => format!("%{b:02X}"),
        })
        .collect();
    format!("/v1/apps/{id}/{resource}")
}

fn rel_ids(r: &Value, name: &str) -> Vec<String> {
    let data = &r["relationships"][name]["data"];
    let rows = data.as_array().cloned().unwrap_or_else(|| vec![data.clone()]);
    rows.iter().filter_map(|row| row["id"].as_str().map(String::from)).collect()
}

fn screenshot_urls(shot: &Value, included: &HashMap<(String, String), Value>) -> Vec<String> {
    let mut urls = Vec::new();
    for id in rel_ids(shot, "screenshots").into_iter().chain(rel_ids(shot, "screenshot")) {
        let row =
            ["betaFeedbackScreenshot", "screenshot"].iter().find_map(|t| included.get(&(t.to_string(), id.clone())));
        let Some(a) = row.map(|r| &r["attributes"]) else { continue };
        urls.extend(["url", "imageUrl", "fileUrl"].iter().filter_map(|k| a[k].as_str().map(String::from)));
        let assets = if a["imageAssets"].is_null() { &a["asset"] } else { &a["imageAssets"] };
        let assets = assets.as_array().cloned().unwrap_or_else(|| vec![assets.clone()]);
        urls.extend(assets.iter().filter_map(|x| x["url"].as_str().map(String::from)));
        if let Some(t) = a["templateUrl"].as_str().or(a["urlTemplate"].as_str()).filter(|t| t.contains("{w}")) {
            urls.push(t.replace("{w}", "1280").replace("{h}", "1280").replace("{f}", "jpg"));
        }
    }
    let mut seen = HashSet::new();
    urls.retain(|u| seen.insert(u.clone()));
    urls
}

/// The image as a JPEG of at most 1280 px a side, with no metadata.
fn strip_image(data: &[u8]) -> Option<Vec<u8>> {
    let img = image::load_from_memory(data).ok()?.thumbnail(1280, 1280).into_rgb8();
    let mut out = Vec::new();
    image::codecs::jpeg::JpegEncoder::new_with_quality(&mut out, 82).encode_image(&img).ok()?;
    Some(out)
}

fn gh(args: &[&str]) -> Result<String> {
    output(cmd("gh").args(args))
}

fn existing_markers(repo: &str) -> HashSet<String> {
    let re = Regex::new(&format!(r"<!-- {MARKER}: ([A-Za-z0-9:_-]+) -->")).unwrap();
    let args = ["issue", "list", "--repo", repo, "--label", "testflight", "--state", "all", "--limit", "200"];
    match gh(&[&args[..], &["--json", "body"]].concat()) {
        Ok(raw) => serde_json::from_str::<Vec<Value>>(&raw)
            .unwrap_or_default()
            .iter()
            .flat_map(|i| {
                let body = i["body"].as_str().unwrap_or_default().to_string();
                re.captures_iter(&body).map(|c| c[1].to_string()).collect::<Vec<_>>()
            })
            .collect(),
        Err(e) => {
            eprintln!("warn: could not list issues: {e}");
            HashSet::new()
        }
    }
}

fn ensure_labels(repo: &str) {
    for (name, color, desc) in [
        ("testflight", "0E8A16", "Imported from App Store Connect TestFlight feedback"),
        ("bug", "D73A4A", "Something did nothing, crashed, or looked wrong"),
    ] {
        let _ = cmd("gh")
            .args(["label", "create", name, "--repo", repo, "--color", color, "--description", desc, "--force"])
            .output();
    }
}

fn upload_image(repo: &str, issue: &str, jpeg: &[u8], name: &str) -> Option<String> {
    let token = env_any(&["GITHUB_TOKEN", "GH_TOKEN"]).unwrap_or_default();
    let url = format!("https://uploads.github.com/repos/{repo}/issues/{issue}/images?name={name}");
    let mut res = ureq::post(&url)
        .header("Authorization", &format!("Bearer {token}"))
        .header("Accept", "application/vnd.github+json")
        .header("Content-Type", "image/jpeg")
        .header("X-GitHub-Api-Version", "2022-11-28")
        .send(jpeg)
        .ok()?;
    let v: Value = serde_json::from_str(&res.body_mut().read_to_string().ok()?).ok()?;
    v["url"].as_str().or(v["browser_url"].as_str()).map(String::from)
}

fn title(kind: &str, attrs: &HashMap<String, String>, comment: &str) -> String {
    let pick = |a: &str, b: &str| attrs.get(a).or(attrs.get(b)).cloned().unwrap_or_default();
    let mut t = [
        "[testflight]".to_string(),
        kind.to_string(),
        pick("deviceModel", "device"),
        pick("osVersion", "deviceOsVersion"),
    ]
    .into_iter()
    .filter(|p| !p.is_empty())
    .collect::<Vec<_>>()
    .join(" ");
    let snippet: String = comment.lines().next().unwrap_or_default().chars().take(48).collect();
    if !snippet.is_empty() && snippet != kind {
        t = format!("{t}: {snippet}");
    }
    t.chars().take(90).collect()
}

fn body(marker: &str, kind: &str, attrs: &HashMap<String, String>, comment: &str, crash: &str, run: &str) -> String {
    let mut l = vec![
        format!("<!-- {MARKER}: {marker} -->"),
        "Imported from App Store Connect TestFlight feedback.".into(),
        "Tester identity, emails, IPs, UDIDs, and screenshot EXIF were stripped.".into(),
        String::new(),
        format!("**Kind:** {kind}"),
        String::new(),
        "| Field | Value |".into(),
        "|-------|-------|".into(),
    ];
    let preferred =
        ["deviceModel", "osVersion", "appPlatform", "architecture", "connectionType", "screenWidth", "screenHeight"];
    let mut rest: Vec<_> = attrs.keys().filter(|k| !preferred.contains(&k.as_str()) && *k != "comment").collect();
    rest.sort();
    for k in preferred.iter().copied().filter(|k| attrs.contains_key(*k)).chain(rest.into_iter().map(String::as_str)) {
        l.push(format!("| `{k}` | {} |", attrs[k]));
    }
    l.extend(["".into(), "## Tester comment".into(), "".into()]);
    l.push(if comment.is_empty() { "_No comment._".into() } else { comment.into() });
    if !crash.is_empty() {
        let log: String = crash.chars().take(24000).collect();
        l.extend(["".into(), "## Crash log (redacted)".into(), "".into(), "```text".into(), log, "```".into()]);
    }
    l.extend([
        String::new(),
        "## Notes".into(),
        String::new(),
        "This is not a substitute for **Settings > About > Copy Recent Logs**.".into(),
        "If you have a workflow artifact from this import, it is on the Actions run.".into(),
    ]);
    if !run.is_empty() {
        l.push(format!("Run: {run}"));
    }
    l.join("\n") + "\n"
}

fn crash_log(t: &str, r: &Value) -> String {
    let rel = &r["relationships"];
    let Some(url) = rel["crashLog"]["links"]["related"].as_str().or(rel["crashLogs"]["links"]["related"].as_str())
    else {
        return String::new();
    };
    let Ok(page) = get_json(url, t) else { return String::new() };
    let a = &page["data"]["attributes"];
    if page["data"].is_object() {
        if let Some(text) = ["log", "crashLog", "text", "file"].iter().find_map(|k| a[k].as_str()) {
            return redact(text);
        }
        if let Some(dl) = a["url"].as_str() {
            return get(dl, Some(t)).map(|b| redact(&String::from_utf8_lossy(&b))).unwrap_or_default();
        }
    }
    redact(&page.to_string().chars().take(4000).collect::<String>())
}

fn write_artifact(marker: &str, jpeg: Option<&Vec<u8>>, crash: &str) -> Result<()> {
    let root = std::env::var("GITHUB_WORKSPACE").unwrap_or_else(|_| ".".into());
    let dest = std::path::Path::new(&root).join("testflight-inbox").join(marker.replace(':', "_"));
    std::fs::create_dir_all(&dest)?;
    if let Some(j) = jpeg {
        std::fs::write(dest.join("screenshot.jpg"), j)?;
    }
    if !crash.is_empty() {
        std::fs::write(dest.join("crash.txt"), crash)?;
    }
    Ok(())
}

pub fn main(a: Args) -> Result<()> {
    let repo = std::env::var("GITHUB_REPOSITORY").unwrap_or_else(|_| "Wawona/Wawona".into());
    let t = token()?;
    if !a.dry_run {
        ensure_labels(&repo);
    }
    let mut seen = existing_markers(&repo);
    let run = match (std::env::var("GITHUB_SERVER_URL"), std::env::var("GITHUB_RUN_ID")) {
        (Ok(s), Ok(id)) => format!("{s}/{repo}/actions/runs/{id}"),
        _ => String::new(),
    };
    let (apps, _) = paginate(&t, "/v1/apps", "limit=200")?;
    let app_ids: Vec<_> = apps
        .iter()
        .filter(|a| {
            let b = a["attributes"]["bundleId"].as_str().unwrap_or_default();
            b == BUNDLE_PREFIX || b.starts_with(&format!("{BUNDLE_PREFIX}."))
        })
        .filter_map(|a| a["id"].as_str())
        .collect();
    if app_ids.is_empty() {
        println!("no App Store Connect apps matching {BUNDLE_PREFIX}");
        return Ok(());
    }
    let mut created = 0;
    for app in app_ids {
        for (kind, resource, label, include) in [
            ("SCREENSHOT", "betaFeedbackScreenshotSubmissions", "screenshot", "build,screenshots"),
            ("CRASH", "betaFeedbackCrashSubmissions", "crash", "build"),
        ] {
            let path = feedback_path(app, resource);
            let (rows, inc) = match paginate(&t, &path, &format!("limit=50&include={include}")) {
                Ok(p) => p,
                Err(e) => {
                    println!("warn: {kind} list with include failed, retrying bare: {e}");
                    match paginate(&t, &path, "limit=50") {
                        Ok(p) => p,
                        Err(e) => {
                            println!("warn: {kind} list failed: {e}");
                            continue;
                        }
                    }
                }
            };
            let included: HashMap<_, _> = inc
                .into_iter()
                .map(|r| {
                    ((r["type"].as_str().unwrap_or_default().into(), r["id"].as_str().unwrap_or_default().into()), r)
                })
                .collect();
            for row in rows {
                let id = row["id"].as_str().unwrap_or_default();
                let marker = format!("{kind}:{id}");
                if id.is_empty() || seen.contains(&marker) {
                    continue;
                }
                let comment = redact(row["attributes"]["comment"].as_str().unwrap_or_default());
                let mut attrs = sanitize(&row["attributes"]);
                if let Some(b) = rel_ids(&row, "build").first() {
                    let build =
                        included.get(&("builds".into(), b.clone())).or(included.get(&("build".into(), b.clone())));
                    let battrs = sanitize(&build.map_or(Value::Null, |b| b["attributes"].clone()));
                    for k in ["version", "uploadedDate", "processingState"] {
                        if let Some(v) = battrs.get(k) {
                            attrs.insert(format!("build_{k}"), v.clone());
                        }
                    }
                }
                let crash = if kind == "CRASH" { crash_log(&t, &row) } else { String::new() };
                let jpegs: Vec<_> = screenshot_urls(&row, &included)
                    .iter()
                    .take(3)
                    .filter_map(|u| get(u, Some(&t)).or_else(|_| get(u, None)).ok())
                    .filter_map(|blob| strip_image(&blob))
                    .collect();
                if a.dry_run {
                    let c: String = comment.chars().take(80).collect();
                    println!("dry-run {marker} comment={c:?} shots={}", jpegs.len());
                    seen.insert(marker);
                    continue;
                }
                write_artifact(&marker, jpegs.first(), &crash)?;
                let file = std::env::temp_dir().join(format!("tf-{}.md", marker.replace(':', "_")));
                std::fs::write(&file, body(&marker, label, &attrs, &comment, &crash, &run))?;
                let f = file.to_string_lossy();
                let t_ = title(label, &attrs, &comment);
                let created_url = gh(&[
                    "issue",
                    "create",
                    "--repo",
                    &repo,
                    "--title",
                    &t_,
                    "--label",
                    "bug",
                    "--label",
                    "testflight",
                    "--body-file",
                    &f,
                ]);
                let _ = std::fs::remove_file(&file);
                let url = created_url?;
                let issue = url.trim_end_matches('/').rsplit('/').next().unwrap_or_default().to_string();
                let shots: Vec<_> = jpegs
                    .iter()
                    .enumerate()
                    .filter_map(|(i, j)| upload_image(&repo, &issue, j, &format!("tf-{id}-{i}.jpg")))
                    .map(|u| format!("![TestFlight screenshot]({u})"))
                    .collect();
                if !shots.is_empty() {
                    let b = format!("## Screenshot\n\n{}", shots.join("\n\n"));
                    gh(&["issue", "comment", &issue, "--repo", &repo, "--body", &b])?;
                }
                println!("opened {url} for {marker}");
                seen.insert(marker);
                created += 1;
            }
        }
    }
    println!("imported {created} new TestFlight submissions");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn feedback_list_uses_app_scoped_routes() {
        assert_eq!(
            feedback_path("app/id", "betaFeedbackScreenshotSubmissions"),
            "/v1/apps/app%2Fid/betaFeedbackScreenshotSubmissions"
        );
        assert_eq!(
            feedback_path("app-id", "betaFeedbackCrashSubmissions"),
            "/v1/apps/app-id/betaFeedbackCrashSubmissions"
        );
    }

    #[test]
    fn redacts_email_path_secret_and_ip() {
        let out = redact("hi alex@wawona.io from /Users/alex/code password=hunter2 1.2.3.4");
        for s in ["alex@wawona.io", "/Users/alex", "hunter2", "1.2.3.4"] {
            assert!(!out.contains(s), "{out}");
        }
    }

    #[test]
    fn skips_tester_fields() {
        let c =
            sanitize(&json!({ "email": "a@b.c", "deviceModel": "iPhone17,1", "osVersion": "26.5", "udid": "ABCDEF" }));
        assert_eq!(c.get("deviceModel").map(String::as_str), Some("iPhone17,1"));
        assert!(!c.contains_key("email") && !c.contains_key("udid"));
    }

    #[test]
    fn signs_an_es256_jwt() {
        use p256::pkcs8::EncodePrivateKey;
        let key = p256::ecdsa::SigningKey::random(&mut p256::elliptic_curve::rand_core::OsRng);
        let pem = key.to_pkcs8_pem(Default::default()).unwrap();
        std::env::set_var("ASC_P8", b64(pem.as_bytes()));
        std::env::set_var("ASC_KEY_ID", "K");
        std::env::set_var("ASC_ISSUER_ID", "I");
        let jwt = token().unwrap();
        let parts: Vec<_> = jwt.split('.').collect();
        assert_eq!(parts.len(), 3);
        let sig = base64::engine::general_purpose::URL_SAFE_NO_PAD.decode(parts[2]).unwrap();
        let sig = p256::ecdsa::Signature::from_slice(&sig).unwrap();
        use p256::ecdsa::signature::Verifier;
        key.verifying_key().verify(format!("{}.{}", parts[0], parts[1]).as_bytes(), &sig).unwrap();
    }

    fn b64(b: &[u8]) -> String {
        base64::engine::general_purpose::STANDARD.encode(b)
    }

    #[test]
    fn strips_to_metadata_free_jpeg() {
        let img = image::RgbImage::from_pixel(2000, 100, image::Rgb([9, 9, 9]));
        let mut png = Vec::new();
        img.write_to(&mut std::io::Cursor::new(&mut png), image::ImageFormat::Png).unwrap();
        let out = strip_image(&png).unwrap();
        assert_eq!(&out[..2], &[0xFF, 0xD8]);
        assert!(!out.windows(4).any(|w| w == b"Exif"));
        assert_eq!(image::load_from_memory(&out).unwrap().width(), 1280);
    }
}
