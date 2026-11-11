//! `cargo xtask backend <slice>`: build libwawona for one slice into
//! `.build/backend/<slice>` (lib/, uniffi/{swift,kotlin}/).
//!
//! The C libraries come from `.deps/<slice>/slice.json`, the patched path
//! crates from `.deps/src`. The committed Cargo.lock pins every crate; the
//! build resolves against a copy so the `[patch]` entries for the patched
//! crates never rewrite it.

use crate::slices::{self, Slice};
use crate::util::*;
use anyhow::{bail, Context, Result};
use serde::Deserialize;
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

#[derive(Deserialize, Default)]
pub struct SliceJson {
    #[serde(default)]
    pub include_dirs: Vec<String>,
    #[serde(default)]
    pub lib_dirs: Vec<String>,
    #[serde(default)]
    pub pkgconfig_dirs: Vec<String>,
    #[serde(default)]
    pub env: BTreeMap<String, String>,
    #[serde(default)]
    pub link_libs: Vec<String>,
}

impl SliceJson {
    pub fn load(dir: &Path) -> Result<Self> {
        let raw = read(dir.join("slice.json"))?;
        let raw = raw.replace("@SLICE@", &dir.to_string_lossy());
        Ok(serde_json::from_str(&raw)?)
    }
}

#[derive(clap::Args)]
pub struct Args {
    pub slice: String,
    /// dev or release; default from Xcode's CONFIGURATION, else dev for
    /// simulators and macOS and release for devices.
    #[arg(long)]
    pub profile: Option<String>,
    /// Override the slice's minimum OS (the TrollStore tipa builds 14.0).
    #[arg(long)]
    pub min_os: Option<String>,
    /// Output directory; default .build/backend/<slice>.
    #[arg(long)]
    pub out: Option<PathBuf>,
}

pub fn main(a: Args) -> Result<()> {
    let s = slices::get(&a.slice)?;
    let root = root();
    let deps = root.join(".deps").join(slices::deps_name(s.name));
    let src = root.join(".deps/src");
    for d in [&deps, &src] {
        if !d.join(if d == &src { "waypipe" } else { "slice.json" }).exists() {
            bail!("{} is missing. Run: cargo xtask deps {}", d.display(), slices::deps_name(s.name));
        }
    }
    let j = SliceJson::load(&deps)?;
    let profile = a.profile.unwrap_or_else(|| match std::env::var("CONFIGURATION").as_deref() {
        Ok("Release") => "release".into(),
        Ok(_) => "dev".into(),
        Err(_) if s.apple.as_ref().is_some_and(|x| !x.simulator) && s.name != "macosx" => "release".into(),
        Err(_) => "dev".into(),
    });
    let min = a.min_os.as_deref().unwrap_or(s.min_os);
    let out = a.out.unwrap_or_else(|| root.join(".build/backend").join(s.name));

    for c in ["waypipe", "coreutils"] {
        let link = root.join(c);
        // Android's waypipe carries its own patch set (patch-waypipe-android.sh).
        let android = src.join("android").join(c);
        let want = if s.name == "android" && android.exists() { android } else { src.join(c) };
        if std::fs::read_link(&link).ok().as_deref() != Some(want.as_path()) {
            symlink(&want, &link)?;
        }
    }

    let triple = if s.name == "linux" { host_triple()? } else { s.triple.to_string() };
    let u = triple.replace('-', "_");
    let upper = u.to_uppercase();
    let tools = crate::tools::install(&root)?;
    let mut c = cmd("cargo");
    c.current_dir(&root);
    for (k, v) in &j.env {
        c.env(k, v);
    }
    c.env("PATH", prepend_path(&tools))
        .env("PKG_CONFIG", tools.join("pkg-config"))
        .env("BINDGEN", tools.join("bindgen"))
        .env("PKG_CONFIG_PATH", j.pkgconfig_dirs.join(":"))
        .env("PKG_CONFIG_ALLOW_CROSS", "1");
    let incs: String = j.include_dirs.iter().map(|d| format!(" -I{d}")).collect();
    let mut cflags = incs.clone();
    let mut rustflags: String = j.lib_dirs.iter().map(|d| format!(" -L native={d}")).collect();
    for l in &j.link_libs {
        rustflags += &format!(" -l {l}");
    }

    if let Some(apple) = &s.apple {
        // Xcode's SDKs and clang. A build phase exports the SDK it builds
        // for (and DEVELOPER_DIR); cc-rs passes those to xcrun.
        for k in ["SDKROOT", "DEVELOPER_DIR", "IPHONEOS_DEPLOYMENT_TARGET", "MACOSX_DEPLOYMENT_TARGET"] {
            c.env_remove(k);
        }
        let sdkroot = output(cmd("xcrun").args(["--sdk", apple.sdk, "--show-sdk-path"]))?;
        let cc = output(cmd("xcrun").args(["--sdk", apple.sdk, "-f", "clang"]))?;
        let target = format!("{}{min}{}", apple.clang, if apple.simulator { "-simulator" } else { "" });
        cflags += &format!(" -isysroot {sdkroot}");
        rustflags += &format!(" -C link-arg=-target -C link-arg={target} -C link-arg=-isysroot -C link-arg={sdkroot}");
        c.env(apple.deploy_var, min)
            .env(format!("CC_{u}"), &cc)
            .env(format!("CARGO_TARGET_{upper}_LINKER"), &cc)
            .env(format!("BINDGEN_EXTRA_CLANG_ARGS_{u}"), format!("--target={target} -isysroot {sdkroot}{incs}"))
            .env("LIBCLANG_PATH", xcode_libclang()?);
    } else if s.name == "android" {
        let ndk = android_ndk(&root)?;
        let llvm = ndk.join("toolchains/llvm/prebuilt/darwin-x86_64");
        let bin = llvm.join("bin");
        let cc = bin.join(format!("aarch64-linux-android{min}-clang"));
        // libclang, unlike the clang driver, does not find the NDK sysroot.
        let sysroot = llvm.join("sysroot");
        c.env(format!("CC_{u}"), &cc)
            .env(format!("CXX_{u}"), bin.join(format!("aarch64-linux-android{min}-clang++")))
            .env(format!("AR_{u}"), bin.join("llvm-ar"))
            .env(format!("CARGO_TARGET_{upper}_LINKER"), &cc)
            .env(
                "BINDGEN_EXTRA_CLANG_ARGS",
                format!("--target=aarch64-linux-android{min} --sysroot={}{incs}", sysroot.display()),
            )
            .env("LIBCLANG_PATH", llvm.join("lib"));
        cflags += " -fPIC";
    } else {
        c.env("BINDGEN_EXTRA_CLANG_ARGS", incs.trim());
    }
    c.env(format!("CFLAGS_{u}"), cflags.trim()).env(format!("CARGO_TARGET_{upper}_RUSTFLAGS"), rustflags.trim());

    // Resolve against a copy of the lockfile, refreshed when the committed
    // one changes, so the patches below never touch it.
    let lock = root.join("target/wawona-lock/Cargo.lock");
    let committed = root.join("Cargo.lock");
    if !lock.exists() || mtime(&committed)? > mtime(&lock)? {
        std::fs::create_dir_all(lock.parent().unwrap())?;
        std::fs::copy(&committed, &lock)?;
    }
    c.args(["rustc", "--lib", "--crate-type", if s.cdylib { "staticlib,cdylib" } else { "staticlib" }])
        .args(["--target", &triple, "--profile", &profile, "--no-default-features"])
        .args(["--features", &s.features.join(" ")])
        .args(["--config", &format!("resolver.lockfile-path={:?}", lock.to_string_lossy())]);
    for (key, package, dir) in patched_crates(&src)? {
        c.args(["--config", &format!("patch.crates-io.{key}.path={:?}", dir.to_string_lossy())])
            .args(["--config", &format!("patch.crates-io.{key}.package={package:?}")]);
    }
    run(&mut c).context("backend build")?;

    stage(s, &root, &triple, &profile, &out, &tools)
}

/// The crates `.deps/src/crates/<name>-<version>` patches, as
/// (`[patch.crates-io]` key, package, path). One key per directory lets two
/// versions of one crate both be patched.
fn patched_crates(src: &Path) -> Result<Vec<(String, String, PathBuf)>> {
    let dir = src.join("crates");
    if !dir.exists() {
        return Ok(Vec::new());
    }
    let mut v = Vec::new();
    for e in std::fs::read_dir(&dir)? {
        let e = e?;
        let n = e.file_name().to_string_lossy().into_owned();
        let Some((name, _)) = n.rsplit_once('-') else { continue };
        v.push((n.replace(['.', '-'], "_"), name.to_string(), e.path()));
    }
    v.sort();
    Ok(v)
}

fn stage(s: &Slice, root: &Path, triple: &str, profile: &str, out: &Path, tools: &Path) -> Result<()> {
    let built = root.join("target").join(triple).join(if profile == "dev" { "debug" } else { profile });
    let _ = std::fs::remove_dir_all(out);
    std::fs::create_dir_all(out.join("lib"))?;
    std::fs::copy(built.join("libwawona.a"), out.join("lib/libwawona.a"))?;
    let mut lib = out.join("lib/libwawona.a");
    if built.join("libwawona.dylib").exists() {
        lib = out.join("lib/libwawona.dylib");
        std::fs::copy(built.join("libwawona.dylib"), &lib)?;
    }
    if built.join("libwawona.so").exists() {
        lib = out.join("lib/libwawona_core.so");
        std::fs::copy(built.join("libwawona.so"), &lib)?;
    }
    // Only the Apple apps import UniFFI; Android talks JNI (android_jni.c).
    let langs: &[&str] = if s.apple.is_some() { &["swift"] } else { &[] };
    for lang in langs {
        run(cmd(tools.join("uniffi-bindgen"))
            .args(["generate", "--library"])
            .arg(&lib)
            .args(["--language", lang, "--out-dir"])
            .arg(out.join("uniffi").join(lang)))
        .with_context(|| format!("uniffi {lang} bindings"))?;
    }
    if s.name == "android" {
        // Gradle's jniLibs source set wants an ABI directory.
        let abi = out.join("jniLibs/arm64-v8a");
        std::fs::create_dir_all(&abi)?;
        std::fs::copy(&lib, abi.join("libwawona_core.so"))?;
    } else if s.apple.is_some() {
        // WawonaModel imports the bindings from .deps/uniffi.
        symlink(out.join("uniffi/swift"), root.join(".deps/uniffi"))?;
    }
    eprintln!("Built {}", out.display());
    Ok(())
}

fn mtime(p: &Path) -> Result<std::time::SystemTime> {
    Ok(std::fs::metadata(p)?.modified()?)
}

fn prepend_path(dir: &Path) -> String {
    format!("{}:{}", dir.display(), std::env::var("PATH").unwrap_or_default())
}

fn host_triple() -> Result<String> {
    let v = output(cmd("rustc").arg("-vV"))?;
    v.lines().find_map(|l| l.strip_prefix("host: ")).map(str::to_string).context("rustc host")
}

fn xcode_libclang() -> Result<PathBuf> {
    let dev = output(cmd("xcode-select").arg("-p"))?;
    Ok(Path::new(&dev).join("Toolchains/XcodeDefault.xctoolchain/usr/lib"))
}

/// The NDK Android Studio installed, at the version android/app pins.
pub fn android_ndk(root: &Path) -> Result<PathBuf> {
    let gradle = read(root.join("android/app/build.gradle.kts"))?;
    let ver = regex::Regex::new(r#"ndkVersion\s*=\s*"([^"]+)""#)?
        .captures(&gradle)
        .map(|c| c[1].to_string())
        .context("ndkVersion in android/app/build.gradle.kts")?;
    let sdk = android_sdk()?;
    let ndk = sdk.join("ndk").join(&ver);
    if !ndk.exists() {
        bail!("NDK {ver} is missing. Install it from Android Studio (SDK Manager, SDK Tools, NDK) or: sdkmanager \"ndk;{ver}\"");
    }
    Ok(ndk)
}

pub fn android_sdk() -> Result<PathBuf> {
    for k in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
        if let Ok(v) = std::env::var(k) {
            if !v.is_empty() {
                return Ok(v.into());
            }
        }
    }
    let home = std::env::var("HOME")?;
    let p = Path::new(&home).join("Library/Android/sdk");
    if p.exists() {
        return Ok(p);
    }
    bail!("Android SDK not found: set ANDROID_HOME or install Android Studio")
}
