//! Per-machine thumbnail persistence (mirrors Android `MachineThumbnailStore`).
//!
//! PNG files live under `~/.config/wawona/machine-thumbnails/<machine-id>.png`.

use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};

fn base_dir() -> Result<PathBuf> {
    let base = if let Ok(custom) = std::env::var("XDG_CONFIG_HOME") {
        PathBuf::from(custom)
    } else {
        let home = std::env::var("HOME").context("HOME is not set")?;
        Path::new(&home).join(".config")
    };
    Ok(base.join("wawona").join("machine-thumbnails"))
}

/// Path to the PNG thumbnail for a machine, if stored.
pub fn thumbnail_path(machine_id: &str) -> Result<PathBuf> {
    Ok(base_dir()?.join(format!("{machine_id}.png")))
}

/// True when a thumbnail PNG exists on disk.
pub fn has_thumbnail(machine_id: &str) -> bool {
    thumbnail_path(machine_id).ok().is_some_and(|p| p.is_file())
}

/// Encode a cairo `ARgb32` (premultiplied, native little-endian BGRA) buffer
/// as an RGBA PNG, scaled so the long edge is at most 320px.
pub fn encode_argb32_premul_png(
    width: u32,
    height: u32,
    stride: u32,
    pixels: &[u8],
) -> Result<Vec<u8>> {
    if width == 0 || height == 0 || stride < width.saturating_mul(4) {
        anyhow::bail!("invalid shm thumbnail buffer {width}x{height} stride {stride}");
    }
    let need = stride as usize * height as usize;
    if pixels.len() < need {
        anyhow::bail!("shm thumbnail buffer shorter than stride*height");
    }

    let max_edge = 320u32;
    let long_edge = width.max(height);
    let (out_w, out_h) = if long_edge <= max_edge {
        (width, height)
    } else {
        (
            ((width as u64 * max_edge as u64) / long_edge as u64).max(1) as u32,
            ((height as u64 * max_edge as u64) / long_edge as u64).max(1) as u32,
        )
    };

    // XRGB8888 often stores a zero padding byte. If every sample alpha is 0,
    // the color is already straight and the frame is opaque.
    let xrgb = alpha_channel_unused(pixels, width, height, stride);
    let mut rgba = vec![0u8; out_w as usize * out_h as usize * 4];
    for y in 0..out_h {
        let src_y = ((y as u64 * height as u64) / out_h as u64) as usize;
        for x in 0..out_w {
            let src_x = ((x as u64 * width as u64) / out_w as u64) as usize;
            let off = src_y * stride as usize + src_x * 4;
            let b = pixels[off];
            let g = pixels[off + 1];
            let r = pixels[off + 2];
            let a = pixels[off + 3];
            let (r, g, b, a) = if xrgb || a == 0 {
                (r, g, b, 255)
            } else if a == 255 {
                (r, g, b, 255)
            } else {
                (
                    unpremultiply(r, a),
                    unpremultiply(g, a),
                    unpremultiply(b, a),
                    a,
                )
            };
            let dst = (y as usize * out_w as usize + x as usize) * 4;
            rgba[dst] = r;
            rgba[dst + 1] = g;
            rgba[dst + 2] = b;
            rgba[dst + 3] = a;
        }
    }

    let mut out = Vec::new();
    let mut encoder = png::Encoder::new(&mut out, out_w, out_h);
    encoder.set_color(png::ColorType::Rgba);
    encoder.set_depth(png::BitDepth::Eight);
    let mut writer = encoder
        .write_header()
        .context("png header for machine thumbnail")?;
    writer
        .write_image_data(&rgba)
        .context("png pixels for machine thumbnail")?;
    drop(writer);
    Ok(out)
}

fn unpremultiply(channel: u8, alpha: u8) -> u8 {
    let value = (channel as u16 * 255) / alpha as u16;
    value.min(255) as u8
}

fn alpha_channel_unused(pixels: &[u8], width: u32, height: u32, stride: u32) -> bool {
    let samples = 8u32;
    for i in 0..samples {
        let x = (width.saturating_sub(1) * i) / samples;
        let y = (height.saturating_sub(1) * i) / samples;
        let off = y as usize * stride as usize + x as usize * 4 + 3;
        if pixels.get(off).copied().unwrap_or(255) != 0 {
            return false;
        }
    }
    true
}

/// Downscale a Wayland SHM frame and store it as the machine thumbnail.
pub fn save_argb32_premul(
    machine_id: &str,
    width: u32,
    height: u32,
    stride: u32,
    pixels: &[u8],
) -> Result<()> {
    let png_bytes = encode_argb32_premul_png(width, height, stride, pixels)?;
    save_png(machine_id, &png_bytes)
}

/// Write raw PNG bytes for a machine thumbnail.
pub fn save_png(machine_id: &str, png_bytes: &[u8]) -> Result<()> {
    let path = thumbnail_path(machine_id)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("failed to create {}", parent.display()))?;
    }
    fs::write(&path, png_bytes).with_context(|| format!("failed to write {}", path.display()))?;
    Ok(())
}

/// Remove a machine's stored thumbnail.
pub fn delete(machine_id: &str) -> Result<()> {
    let path = thumbnail_path(machine_id)?;
    if path.exists() {
        fs::remove_file(&path).with_context(|| format!("failed to remove {}", path.display()))?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn thumbnail_path_is_under_config() {
        let path = thumbnail_path("abc-123").unwrap();
        assert!(path.to_string_lossy().contains("machine-thumbnails"));
        assert!(path.to_string_lossy().ends_with("abc-123.png"));
    }

    #[test]
    fn argb32_frame_encodes_png() {
        // Little-endian cairo ARgb32: B, G, R, A. Opaque red pixel.
        let pixels = [0u8, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255, 255];
        let png = encode_argb32_premul_png(2, 2, 8, &pixels).unwrap();
        assert_eq!(&png[..8], b"\x89PNG\r\n\x1a\n");
    }

    #[test]
    fn xrgb_zero_alpha_stays_opaque() {
        let pixels = [255u8, 0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0];
        let png = encode_argb32_premul_png(2, 2, 8, &pixels).unwrap();
        assert!(png.len() > 8);
    }
}
