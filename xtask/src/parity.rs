//! The UI parity gate: iOS and Android snapshots of the same screen may
//! differ by at most a normalised mean absolute error.

use std::path::PathBuf;

use anyhow::{bail, Context, Result};
use image::imageops::FilterType;

#[derive(clap::Args)]
pub struct Args {
    /// Directory holding the snapshot PNGs.
    #[arg(long)]
    screenshots_dir: PathBuf,
    /// Normalised MAE ceiling (0.0 to 1.0). Lower is stricter.
    #[arg(long, default_value_t = 0.12)]
    threshold: f64,
}

const PAIRS: [(&str, &str, &str); 4] = [
    ("phone-home-light", "ios_phone_home_light.png", "android_phone_home_light.png"),
    ("phone-home-dark", "ios_phone_home_dark.png", "android_phone_home_dark.png"),
    ("phone-settings-light", "ios_phone_settings_light.png", "android_phone_settings_light.png"),
    ("phone-settings-dark", "ios_phone_settings_dark.png", "android_phone_settings_dark.png"),
];

/// Mean absolute RGB error over 0..1, the right image resized to the left's.
fn normalized_mae(left: &std::path::Path, right: &std::path::Path) -> Result<f64> {
    let open = |p: &std::path::Path| image::open(p).with_context(|| format!("missing snapshot: {}", p.display()));
    let l = open(left)?.into_rgb8();
    let mut r = open(right)?.into_rgb8();
    if l.dimensions() != r.dimensions() {
        r = image::imageops::resize(&r, l.width(), l.height(), FilterType::CatmullRom);
    }
    let total: u64 = l.as_raw().iter().zip(r.as_raw()).map(|(a, b)| a.abs_diff(*b) as u64).sum();
    Ok(total as f64 / l.as_raw().len() as f64 / 255.0)
}

pub fn main(a: Args) -> Result<()> {
    let mut failures = Vec::new();
    for (name, left, right) in PAIRS {
        let score = normalized_mae(&a.screenshots_dir.join(left), &a.screenshots_dir.join(right))?;
        println!("{name}: {score:.4}");
        if score > a.threshold {
            failures.push(format!("  - {name}: {score:.4} > threshold {:.4}", a.threshold));
        }
    }
    if !failures.is_empty() {
        bail!("parity gate failed:\n{}", failures.join("\n"));
    }
    println!("\nParity gate PASSED.");
    Ok(())
}
