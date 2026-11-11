//! The OCI distribution API calls `deps` makes against GHCR: anonymous blob
//! pulls, and blob uploads plus a tagged manifest with a GitHub token.
//! https://github.com/opencontainers/distribution-spec/blob/main/spec.md

use super::{REGISTRY, REPOSITORY};
use anyhow::{bail, Context, Result};
use std::io::Read;
use std::path::Path;

const EMPTY: &[u8] = b"{}";
const EMPTY_DIGEST: &str = "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a";
const CHUNK: usize = 32 << 20;

fn token(scope: &str, basic: Option<String>) -> Result<String> {
    let url = format!("https://{REGISTRY}/token?scope=repository:{REPOSITORY}:{scope}&service={REGISTRY}");
    let mut req = ureq::get(&url);
    if let Some(b) = basic {
        req = req.header("Authorization", &format!("Basic {b}"));
    }
    let mut res = req.call().context("GHCR token")?;
    let v: serde_json::Value = serde_json::from_str(&res.body_mut().read_to_string()?)?;
    Ok(v["token"].as_str().context("GHCR token response")?.to_string())
}

/// A directory of blobs named by sha256 that stands in for GHCR (an offline
/// mirror, or a CI cache).
fn mirror() -> Option<std::path::PathBuf> {
    std::env::var_os("WAWONA_DEPS_MIRROR").filter(|v| !v.is_empty()).map(Into::into)
}

pub fn blob(sha256: &str) -> Result<Box<dyn Read>> {
    if let Some(m) = mirror() {
        let p = m.join(sha256);
        return Ok(Box::new(std::fs::File::open(&p).with_context(|| format!("open {}", p.display()))?));
    }
    let t = token("pull", None)?;
    let url = format!("https://{REGISTRY}/v2/{REPOSITORY}/blobs/sha256:{sha256}");
    let res = ureq::get(&url)
        .header("Authorization", &format!("Bearer {t}"))
        .config()
        .timeout_global(None)
        .build()
        .call()
        .with_context(|| format!("GET {url}"))?;
    Ok(Box::new(res.into_body().into_reader()))
}

fn push_token() -> Result<String> {
    let user = crate::util::env_or("GITHUB_ACTOR", "wawona");
    let pass = std::env::var("GITHUB_TOKEN")
        .or_else(|_| crate::util::output(crate::util::cmd("gh").args(["auth", "token"])))
        .context("GITHUB_TOKEN (packages:write) or gh auth")?;
    token("pull,push", Some(base64(format!("{user}:{pass}").as_bytes())))
}

fn absolute(location: &str) -> String {
    if location.starts_with("http") { location.to_string() } else { format!("https://{REGISTRY}{location}") }
}

fn upload(t: &str, digest: &str, mut data: impl Read) -> Result<()> {
    let head = format!("https://{REGISTRY}/v2/{REPOSITORY}/blobs/sha256:{digest}");
    if ureq::head(&head).header("Authorization", &format!("Bearer {t}")).call().is_ok() {
        return Ok(());
    }
    let res = ureq::post(&format!("https://{REGISTRY}/v2/{REPOSITORY}/blobs/uploads/"))
        .header("Authorization", &format!("Bearer {t}"))
        .send_empty()
        .context("start upload")?;
    let mut loc = absolute(res.headers().get("location").context("upload location")?.to_str()?);
    let mut offset = 0usize;
    let mut buf = vec![0u8; CHUNK];
    loop {
        let mut n = 0;
        while n < CHUNK {
            let r = data.read(&mut buf[n..])?;
            if r == 0 {
                break;
            }
            n += r;
        }
        if n == 0 {
            break;
        }
        let res = ureq::patch(&loc)
            .header("Authorization", &format!("Bearer {t}"))
            .header("Content-Type", "application/octet-stream")
            .header("Content-Range", &format!("{}-{}", offset, offset + n - 1))
            .config()
            .timeout_global(None)
            .build()
            .send(&buf[..n])
            .context("upload chunk")?;
        loc = absolute(res.headers().get("location").context("chunk location")?.to_str()?);
        offset += n;
    }
    let sep = if loc.contains('?') { '&' } else { '?' };
    ureq::put(&format!("{loc}{sep}digest=sha256:{digest}"))
        .header("Authorization", &format!("Bearer {t}"))
        .send_empty()
        .context("finish upload")?;
    Ok(())
}

pub fn push(sdk: &str, archive: &Path, sha256: &str, size: u64) -> Result<()> {
    if let Some(m) = mirror() {
        std::fs::create_dir_all(&m)?;
        std::fs::copy(archive, m.join(sha256))?;
        return Ok(());
    }
    let t = push_token()?;
    upload(&t, EMPTY_DIGEST, EMPTY)?;
    upload(&t, sha256, std::fs::File::open(archive)?)?;
    let manifest = serde_json::json!({
        "schemaVersion": 2,
        "mediaType": "application/vnd.oci.image.manifest.v1+json",
        "artifactType": "application/vnd.wawona.deps.v1",
        "config": { "mediaType": "application/vnd.oci.empty.v1+json", "digest": format!("sha256:{EMPTY_DIGEST}"), "size": 2 },
        "layers": [{
            "mediaType": "application/vnd.wawona.deps.layer.v1.tar+zstd",
            "digest": format!("sha256:{sha256}"),
            "size": size,
            "annotations": { "org.opencontainers.image.title": format!("{sdk}.tar.zst") },
        }],
        "annotations": { "org.opencontainers.image.source": "https://github.com/Wawona/Wawona" },
    });
    let tag = format!("{sdk}-{}", &sha256[..16]);
    let url = format!("https://{REGISTRY}/v2/{REPOSITORY}/manifests/{tag}");
    let res = ureq::put(&url)
        .header("Authorization", &format!("Bearer {t}"))
        .header("Content-Type", "application/vnd.oci.image.manifest.v1+json")
        .send(serde_json::to_vec(&manifest)?.as_slice())
        .with_context(|| format!("PUT {url}"))?;
    if !res.status().is_success() {
        bail!("PUT {url}: {}", res.status());
    }
    eprintln!("pushed {REGISTRY}/{REPOSITORY}:{tag}");
    Ok(())
}

fn base64(b: &[u8]) -> String {
    const T: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut s = String::new();
    for c in b.chunks(3) {
        let n = (c[0] as u32) << 16 | (*c.get(1).unwrap_or(&0) as u32) << 8 | *c.get(2).unwrap_or(&0) as u32;
        for i in 0..4 {
            if i <= c.len() {
                s.push(T[(n >> (18 - 6 * i) & 63) as usize] as char);
            } else {
                s.push('=');
            }
        }
    }
    s
}
