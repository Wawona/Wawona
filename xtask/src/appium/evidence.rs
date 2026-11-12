//! A catalog client passes on a machine screenshot of it running, not a log
//! line. Tiny, flat, or empty-content captures are not proof.

use std::path::{Path, PathBuf};

use anyhow::{bail, ensure, Result};

use crate::util::*;

const MIN_PNG_BYTES: u64 = 12_000;
const MIN_SIDE: u32 = 200;

pub fn gallery(artifacts: &Path) -> Result<PathBuf> {
    let g = artifacts.join("catalog-gallery");
    std::fs::create_dir_all(&g)?;
    Ok(g)
}

pub fn require_client_screenshot(path: &Path, client: &str) -> Result<()> {
    ensure!(path.is_file(), "missing screenshot for {client}: {}", path.display());
    let bytes = path.metadata()?.len();
    ensure!(bytes >= MIN_PNG_BYTES, "screenshot for {client} is {bytes} bytes (< {MIN_PNG_BYTES}): an empty capture");
    let img = image::open(path)?.into_luma8();
    let (w, h) = img.dimensions();
    ensure!(w >= MIN_SIDE && h >= MIN_SIDE, "screenshot for {client} is {w}x{h} (need {MIN_SIDE}x{MIN_SIDE})");
    // Empty Metal or Xvfb captures come back all black or all white.
    let samples: Vec<u8> = img.as_raw().iter().step_by(64).copied().collect();
    let (lo, hi) = (samples.iter().min().copied().unwrap_or(0), samples.iter().max().copied().unwrap_or(0));
    ensure!(hi - lo >= 8, "screenshot for {client} looks solid ({w}x{h})");
    // Mac2 may capture the whole display, whose chrome varies while the
    // Wawona pane is empty: judge the centre half. Dark clients (foot,
    // weston-terminal) stay dark but carry structure, so blank means flat
    // and near black or near white.
    let centre: Vec<f64> = (h / 4..3 * h / 4)
        .flat_map(|y| (w / 4..3 * w / 4).map(move |x| (x, y)))
        .map(|(x, y)| f64::from(img.get_pixel(x, y)[0]))
        .collect();
    let mean = centre.iter().sum::<f64>() / centre.len() as f64;
    let sd = (centre.iter().map(|p| (p - mean).powi(2)).sum::<f64>() / centre.len() as f64).sqrt();
    if sd < 12.0 && !(18.0..=235.0).contains(&mean) {
        bail!("screenshot for {client} has a blank content area ({w}x{h}); Start or Focus so the client paints first");
    }
    Ok(())
}

pub fn publish(src: &Path, artifacts: &Path, client: &str) -> Result<PathBuf> {
    let g = gallery(artifacts)?;
    let dest = g.join(format!("{client}.png"));
    std::fs::copy(src, &dest)?;
    write(g.join(format!("{client}.ok")), format!("client={client}\nbytes={}\n", src.metadata()?.len()))?;
    Ok(dest)
}

pub fn write_index(artifacts: &Path, clients: &[String]) -> Result<()> {
    let g = gallery(artifacts)?;
    let mut html = String::from(
        "<!DOCTYPE html><meta charset=utf-8>\n<title>Wawona Appium catalog gallery</title>\n\
         <style>body{font:14px system-ui;margin:24px}img{max-width:100%;border:1px solid #444}\
         figure{margin:0 0 32px}figcaption{font-weight:600;margin:8px 0}</style>\n\
         <h1>Catalog Wayland clients (machine screenshots)</h1>\n\
         <p>Each tile must show the named client running in Wawona.</p>\n",
    );
    for c in clients {
        if g.join(format!("{c}.png")).is_file() {
            html += &format!("<figure><figcaption>{c}</figcaption><img src='{c}.png' alt='{c}'></figure>\n");
        } else {
            html += &format!("<figure><figcaption>{c}: MISSING</figcaption></figure>\n");
        }
    }
    write(g.join("index.html"), html)
}

pub fn verify_gallery(artifacts: &Path, only: &[String]) -> Result<()> {
    let mut clients = super::Matrix::load()?.clients();
    let only: Vec<_> = only.iter().filter(|s| !s.is_empty()).collect();
    if !only.is_empty() {
        let unknown: Vec<_> = only.iter().filter(|o| !clients.contains(o)).collect();
        ensure!(unknown.is_empty(), "unknown catalog clients: {unknown:?}");
        clients.retain(|c| only.contains(&c));
    }
    let g = gallery(artifacts)?;
    let bad: Vec<String> = clients
        .iter()
        .filter_map(|c| require_client_screenshot(&g.join(format!("{c}.png")), c).err().map(|e| format!("{c}: {e}")))
        .collect();
    write_index(artifacts, &clients)?;
    if !bad.is_empty() {
        bad.iter().for_each(|b| println!("  BAD {b}"));
        bail!("catalog gallery at {}: {} of {} clients lack a real screenshot", g.display(), bad.len(), clients.len());
    }
    println!("OK catalog gallery ({} screenshots) -> {}", clients.len(), g.join("index.html").display());
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::require_client_screenshot;

    fn png(name: &str, f: impl Fn(u32, u32) -> u8) -> std::path::PathBuf {
        let img = image::GrayImage::from_fn(400, 300, |x, y| image::Luma([f(x, y)]));
        let p = std::env::temp_dir().join(format!("wwn-evidence-{}-{name}.png", std::process::id()));
        img.save(&p).unwrap();
        p
    }

    #[test]
    fn rejects_flat_and_accepts_drawn_frames() {
        assert!(require_client_screenshot(&png("black", |_, _| 0), "c").is_err());
        let noisy = |x: u32, y: u32| ((x * 7919 + y * 104729) % 251) as u8;
        assert!(require_client_screenshot(&png("noisy", noisy), "c").is_ok());
    }
}
