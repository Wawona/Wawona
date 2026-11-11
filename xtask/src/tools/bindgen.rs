//! The subset of the bindgen CLI that waypipe's wrap-ffmpeg build script
//! passes: `bindgen [options] <header> -- <clang args>`.

use anyhow::{bail, Context, Result};

pub fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let mut b = bindgen::Builder::default();
    let (mut out, mut depfile, mut header) = (None, None, None);
    let value = |args: &mut std::iter::Skip<std::env::Args>, flag: &str| {
        args.next().with_context(|| format!("{flag} needs a value"))
    };
    while let Some(a) = args.next() {
        match a.as_str() {
            "--" => {
                b = b.clang_args(args.by_ref());
                break;
            }
            "--dynamic-loading" => b = b.dynamic_library_name(value(&mut args, &a)?),
            "--dynamic-link-require-all" => b = b.dynamic_link_require_all(true),
            "--rust-target" => {
                let v = value(&mut args, &a)?;
                b = b.rust_target(v.parse().map_err(|e| anyhow::anyhow!("--rust-target {v}: {e}"))?);
            }
            "--no-doc-comments" => b = b.generate_comments(false),
            "--depfile" => depfile = Some(value(&mut args, &a)?),
            "--output" | "-o" => out = Some(value(&mut args, &a)?),
            "--allowlist-function" => b = b.allowlist_function(value(&mut args, &a)?),
            "--allowlist-var" => b = b.allowlist_var(value(&mut args, &a)?),
            "--allowlist-type" => b = b.allowlist_type(value(&mut args, &a)?),
            f if f.starts_with('-') => bail!("bindgen: unsupported option {f}"),
            h => header = Some(h.to_string()),
        }
    }
    let header = header.context("bindgen: no header")?;
    let out = out.context("bindgen: no --output")?;
    b = b.header(&header);
    if let Some(d) = depfile {
        b = b.depfile(&out, d);
    }
    let bindings = b.generate().map_err(|e| anyhow::anyhow!("bindgen {header}: {e}"))?;
    bindings.write_to_file(&out).with_context(|| format!("write {out}"))
}
