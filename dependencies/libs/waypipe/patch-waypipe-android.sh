#!/bin/bash
# Minimal waypipe patches for Android/macOS/Linux (OpenSSH, spawn, dynamic libs).
# NO iOS-specific patches: no libssh2, no eventfd_macos, no socket_wrapper.
# Android and macOS can use spawn/fork/OpenSSH natively.
set -e
chmod -R u+w src/ 2>/dev/null || true

# Cargo.toml: library-only for path dep (no binaries)
if [ -f "Cargo.toml" ]; then
  python3 <<'PY'
import pathlib, re
p = pathlib.Path('Cargo.toml')
content = p.read_text()
modified = False
if '[[bin]]' in content:
    start = content.find('[[bin]]')
    while start != -1:
        end = content.find('\n[[', start + 1)
        if end == -1: end = content.find('\n[', start + 1)
        if end == -1: end = len(content)
        content = content[:start] + content[end:]
        start = content.find('[[bin]]')
    modified = True
if "default-run" in content:
    content = re.sub(r'default-run\s*=\s*".*?"\n', "", content)
    modified = True
if '[lib]' in content:
    if 'crate-type' in content:
        content = re.sub(r'crate-type\s*=\s*\[.*?\]', 'crate-type = ["rlib", "staticlib"]', content)
    else:
        content = re.sub(r'(\[lib\]\n)', r'\1crate-type = ["rlib", "staticlib"]\n', content)
    modified = True
else:
    content += '\n[lib]\ncrate-type = ["rlib", "staticlib"]\n'
    modified = True
if modified:
    p.write_text(content)
PY
fi

# wrap-gbm: stub for non-Linux (Android target_os is "android")
if [ -f "wrap-gbm/build.rs" ]; then
  cat > wrap-gbm/build.rs <<'EOF'
fn main() {
    use std::env;
    use std::fs;
    use std::path::PathBuf;
    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
    let bindings_rs = out_dir.join("bindings.rs");
    fs::write(&bindings_rs, "// GBM not available on Android\n").unwrap();
    println!("cargo:warning=GBM not required on this platform");
}
EOF
fi

# wrap-zstd: minimal bindings (same as iOS, no bindgen)
if [ -f "wrap-zstd/build.rs" ]; then
  cat > wrap-zstd/build.rs <<'ZSTD_EOF'
fn main() {
    use std::env;
    use std::path::PathBuf;
    use std::fs;
    println!("cargo:rustc-link-lib=zstd");
    let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());
    let bindings_rs = out_path.join("bindings.rs");
    let bindings = r#"#[allow(non_camel_case_types)] pub type size_t = usize;
    #[repr(C)] pub struct ZSTD_CCtx { _private: [u8; 0] }
    #[repr(C)] pub struct ZSTD_DCtx { _private: [u8; 0] }
    #[repr(C)] #[derive(Clone, Copy, Debug, PartialEq, Eq)] pub enum ZSTD_cParameter {
        ZSTD_c_compressionLevel = 100, ZSTD_c_windowLog = 101, ZSTD_c_hashLog = 102,
        ZSTD_c_chainLog = 103, ZSTD_c_searchLog = 104, ZSTD_c_minMatch = 105,
        ZSTD_c_targetLength = 106, ZSTD_c_strategy = 107, ZSTD_c_contentSizeFlag = 200,
        ZSTD_c_checksumFlag = 201, ZSTD_c_dictIDFlag = 202,
    }
    pub const ZSTD_cParameter_ZSTD_c_compressionLevel: ZSTD_cParameter = ZSTD_cParameter::ZSTD_c_compressionLevel;
    pub const ZSTD_cParameter_ZSTD_c_windowLog: ZSTD_cParameter = ZSTD_cParameter::ZSTD_c_windowLog;
    extern "C" {
        pub fn ZSTD_createCCtx() -> *mut ZSTD_CCtx;
        pub fn ZSTD_freeCCtx(cctx: *mut ZSTD_CCtx) -> size_t;
        pub fn ZSTD_createDCtx() -> *mut ZSTD_DCtx;
        pub fn ZSTD_freeDCtx(dctx: *mut ZSTD_DCtx) -> size_t;
        pub fn ZSTD_CCtx_setParameter(cctx: *mut ZSTD_CCtx, param: ZSTD_cParameter, value: i32) -> size_t;
        pub fn ZSTD_compress2(cctx: *mut ZSTD_CCtx, dst: *mut u8, dstCapacity: size_t, src: *const u8, srcSize: size_t) -> size_t;
        pub fn ZSTD_decompressDCtx(dctx: *mut ZSTD_DCtx, dst: *mut u8, dstCapacity: size_t, src: *const u8, srcSize: size_t) -> size_t;
        pub fn ZSTD_compress(dst: *mut u8, dstCapacity: size_t, src: *const u8, srcSize: size_t, compressionLevel: i32) -> size_t;
        pub fn ZSTD_decompress(dst: *mut u8, dstCapacity: size_t, src: *const u8, compressedSize: size_t) -> size_t;
        pub fn ZSTD_compressBound(srcSize: size_t) -> size_t;
        pub fn ZSTD_isError(code: size_t) -> u32;
        pub fn ZSTD_getErrorName(code: size_t) -> *const i8;
    }
    "#;
    fs::write(&bindings_rs, bindings).expect("Couldn't write zstd bindings!");
}
ZSTD_EOF
fi

# wrap-lz4: minimal bindings
if [ -f "wrap-lz4/build.rs" ]; then
  cat > wrap-lz4/build.rs <<'LZ4_EOF'
fn main() {
    use std::env;
    use std::path::PathBuf;
    use std::fs;
    println!("cargo:rustc-link-lib=lz4");
    let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());
    let bindings_rs = out_path.join("bindings.rs");
    let bindings = r#"#[allow(non_camel_case_types)] pub type size_t = usize;
    extern "C" {
        pub fn LZ4_compress_default(src: *const u8, dst: *mut u8, srcSize: i32, dstCapacity: i32) -> i32;
        pub fn LZ4_decompress_safe(src: *const u8, dst: *mut u8, compressedSize: i32, dstCapacity: i32) -> i32;
        pub fn LZ4_compressBound(inputSize: i32) -> i32;
        pub fn LZ4_sizeofState() -> i32;
        pub fn LZ4_sizeofStateHC() -> i32;
        pub fn LZ4_compress_fast_extState(state: *mut u8, src: *const u8, dst: *mut u8, srcSize: i32, dstCapacity: i32, acceleration: i32) -> i32;
        pub fn LZ4_compress_HC_extStateHC(stateHC: *mut u8, src: *const u8, dst: *mut u8, srcSize: i32, dstCapacity: i32, compressionLevel: i32) -> i32;
    }
    "#;
    fs::write(&bindings_rs, bindings).expect("Couldn't write lz4 bindings!");
}
LZ4_EOF
fi

# wrap-ffmpeg: stub build.rs for Android (no ffmpeg codec support needed)
if [ -f "wrap-ffmpeg/build.rs" ]; then
  cat > wrap-ffmpeg/build.rs <<'FFMPEG_EOF'
fn main() {
    use std::env;
    use std::fs;
    use std::path::PathBuf;
    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
    let bindings_rs = out_dir.join("bindings.rs");
    fs::write(&bindings_rs, "// FFmpeg not available on Android\n").unwrap();
    println!("cargo:warning=FFmpeg not required on Android");
}
FFMPEG_EOF
fi

# shaders stub
if [ -f "shaders/build.rs" ]; then
  cat > shaders/build.rs <<'EOF'
fn main() {
    use std::env;
    use std::fs;
    use std::path::PathBuf;
    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
    let shaders_rs = out_dir.join("shaders.rs");
    fs::write(&shaders_rs, "pub const NV12_IMG_TO_RGB: &[u32] = &[];\npub const RGB_TO_NV12_IMG: &[u32] = &[];\npub const RGB_TO_YUV420_BUF: &[u32] = &[];\npub const YUV420_BUF_TO_RGB: &[u32] = &[];\n").unwrap();
}
EOF
fi

# Remove tests/proto.rs
[ -f "tests/proto.rs" ] && rm tests/proto.rs

# Rename src/main.rs to src/lib.rs for library compilation
# Cargo expects src/lib.rs for [lib] crates; without this, `cargo metadata` fails
# with "can't find library `waypipe`, rename file to `src/lib.rs`"
if [ -f "src/main.rs" ] && [ ! -f "src/lib.rs" ]; then
  mv src/main.rs src/lib.rs
  echo "✓ Renamed src/main.rs to src/lib.rs"
fi

# Inject waypipe_main C entry point (needed by android_jni.c)
if [ -f "src/lib.rs" ]; then
  python3 - src/lib.rs <<'INJECT_MAIN_EOF'
import sys
import re

file_path = sys.argv[1]
with open(file_path, "r") as f:
    content = f.read()

inner_attr_lines = re.findall(r'^\s*#!\[.*?\]\s*$', content, re.MULTILINE)
content = re.sub(r'^\s*#!\[.*?\]\s*$', '', content, flags=re.MULTILINE)
# Also extract inner doc comments (/*! ... */ and //! ...)
inner_doc_comments = re.findall(r'/\*!.*?\*/', content, re.DOTALL)
content = re.sub(r'/\*!.*?\*/', '', content, flags=re.DOTALL)
inner_line_docs = re.findall(r'^\s*//!.*$', content, re.MULTILINE)
content = re.sub(r'^\s*//!.*$', '', content, flags=re.MULTILINE)

imports = r"""
macro_rules! wplog {
    ($tag:expr, $($arg:tt)*) => {{
        use std::io::Write as _;
        let _ = writeln!(std::io::stderr(), "[{}] {}", $tag, format!($($arg)*));
    }};
}
use std::ffi::CStr;
use std::os::raw::{c_int, c_char};
use std::sync::Mutex;
"""

if "GLOBAL_ARGS" not in content:
    content = re.sub(r'macro_rules! wplog \{.*?\}\n', '', content, flags=re.DOTALL)
    prefix = "\n".join(inner_attr_lines) + "\n"
    if inner_doc_comments:
        prefix += "\n".join(inner_doc_comments) + "\n"
    if inner_line_docs:
        prefix += "\n".join(inner_line_docs) + "\n"
    content = prefix + imports + "\n" + content

globals_code = """
static GLOBAL_ARGS: Mutex<Vec<String>> = Mutex::new(Vec::new());

fn set_global_args(args: Vec<String>) {
    let mut guard = GLOBAL_ARGS.lock().unwrap();
    *guard = args;
}

fn get_args() -> Vec<String> {
    let guard = GLOBAL_ARGS.lock().unwrap();
    if guard.is_empty() {
        std::env::args().collect()
    } else {
        guard.clone()
    }
}
"""

if "GLOBAL_ARGS" not in content:
    content = re.sub(r'fn get_args\(\) -> Vec<String> \{.*?\}', '', content, flags=re.DOTALL)
    content += globals_code

waypipe_main_code = """
#[no_mangle]
pub extern "C" fn waypipe_main(argc: c_int, argv: *const *const c_char) -> c_int {
    let mut args: Vec<String> = Vec::new();
    for i in 0..argc {
        unsafe {
            let ptr = *argv.offset(i as isize);
            if !ptr.is_null() {
                let c_str = CStr::from_ptr(ptr);
                if let Ok(s) = c_str.to_str() {
                    args.push(String::from(s));
                }
            }
        }
    }
    waypipe_run_main(args)
}

#[no_mangle]
pub fn waypipe_run_main(args: Vec<String>) -> i32 {
    set_global_args(args);
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| w_main())) {
        Ok(Ok(_)) => 0,
        Ok(Err(e)) => {
            wplog!("WAYPIPE-CORE", "Error: {:?}", e);
            1
        }
        Err(panic_info) => {
            wplog!("WAYPIPE-CORE", "Panic caught (prevented abort): {:?}", panic_info);
            2
        }
    }
}

#[allow(dead_code)]
fn get_waypipe_args() -> impl Iterator<Item = String> {
    get_args().into_iter()
}

#[allow(dead_code)]
fn get_waypipe_args_os() -> impl Iterator<Item = std::ffi::OsString> {
    get_args().into_iter().map(std::ffi::OsString::from)
}
"""
if "fn waypipe_main" not in content:
    content += waypipe_main_code

content = re.sub(r'fn (main|waypipe_inner_main)\s*\(', 'fn w_main(', content)
content = re.sub(r'waypipe_inner_main\s*\(', 'w_main(', content)

if "pub fn main() -> std::process::ExitCode" not in content:
    content = re.sub(r'pub fn main\(\) -> Result<[^>]*> \{ w_main\(\) \}', '', content)
    content += """
pub fn main() -> std::process::ExitCode {
    match w_main() {
        Ok(_) => std::process::ExitCode::SUCCESS,
        Err(_) => std::process::ExitCode::FAILURE,
    }
}
"""

with open(file_path, "w") as f:
    f.write(content)
print("Injected waypipe_main C entry point")
INJECT_MAIN_EOF
  echo "✓ Injected waypipe_main"

  # Fix clap argument parsing: use injected args instead of std::env::args().
  # Without this, clap reads the Android app's process args (e.g. the package
  # name), fails to parse, and calls std::process::exit() — which kills the
  # entire app since waypipe runs as a linked library, not a standalone binary.
  python3 <<'CLAP_PY'
from pathlib import Path
target = Path("src/lib.rs")
if not target.exists():
    target = Path("src/main.rs")
if target.exists():
    s = target.read_text()
    old = "let matches = command.get_matches()"
    new = 'let matches = command.try_get_matches_from(get_args()).map_err(|e| format!("Argument parsing failed: {}", e))?'
    if old in s:
        s = s.replace(old, new)
        target.write_text(s)
        print(f"✓ Patched clap get_matches in {target}")
    else:
        print(f"Note: command.get_matches() not found in {target} (already patched or pattern differs)")
CLAP_PY

  # Fix logger initialization: use .ok() instead of .unwrap() so that
  # re-entering waypipe_main (second "Run Waypipe" in same app instance)
  # doesn't panic with SetLoggerError when the global logger is already set.
  python3 <<'LOGGER_PY'
from pathlib import Path
target = Path("src/lib.rs")
if not target.exists():
    target = Path("src/main.rs")
if target.exists():
    s = target.read_text()
    old = "log::set_boxed_logger(Box::new(logger)).unwrap()"
    new = "let _ = log::set_boxed_logger(Box::new(logger))"
    if old in s:
        s = s.replace(old, new)
        target.write_text(s)
        print(f"✓ Patched logger init (.unwrap -> let _) in {target}")
    else:
        print(f"Note: set_boxed_logger().unwrap() not found in {target} (already patched or pattern differs)")
LOGGER_PY
fi

# Add with_libssh2 feature stub (empty — no ssh2 dep on Android).
# Android uses OpenSSH via fork/exec, NOT libssh2.
# The Cargo.lock is patched in workspace-src.nix to strip ssh2 from waypipe.
if [ -f "Cargo.toml" ]; then
  python3 <<'FEAT_PY'
from pathlib import Path
s = Path("Cargo.toml").read_text()
if "with_libssh2" not in s:
    if "[features]" in s:
        s = s.replace("[features]", "[features]\nwith_libssh2 = []")
    else:
        s += "\n[features]\nwith_libssh2 = []\n"
    Path("Cargo.toml").write_text(s)
    print("Added with_libssh2 empty feature stub")
FEAT_PY
fi

# Fix compress.rs: our minimal zstd/lz4 bindings use *u8 not *c_void/*c_char
if [ -f "src/compress.rs" ]; then
  sed -i 's/as \*mut c_void/as *mut u8/g' src/compress.rs
  sed -i 's/as \*const c_void/as *const u8/g' src/compress.rs
  sed -i 's/as \*mut c_char/as *mut u8/g' src/compress.rs
  sed -i 's/as \*const c_char/as *const u8/g' src/compress.rs
  sed -i '/use core::ffi::{c_char, c_void};/d' src/compress.rs
  sed -i '/use core::ffi::c_char;/d' src/compress.rs
  sed -i '/use core::ffi::c_void;/d' src/compress.rs
  echo "✓ Fixed compress.rs pointer casts"
fi

# Stub out gbm.rs — Android doesn't use GBM (Vulkan/EGL rendering)
if [ -f "src/gbm.rs" ]; then
  cat > src/gbm.rs <<'GBM_STUB'
#![allow(dead_code, unused_imports, unused_variables)]
use crate::util::AddDmabufPlane;
use std::rc::Rc;

pub struct GbmDevice;
pub type GBMDevice = GbmDevice;
pub type GbmBo = GbmDmabuf;
pub type GBMBo = GbmBo;

pub struct GbmDmabuf {
    pub width: u32,
    pub height: u32,
    pub stride: u32,
    pub format: u32,
}
pub type GBMDmabuf = GbmDmabuf;

impl GbmDmabuf {
    pub fn nominal_size(&self, _stride: Option<u32>) -> usize { (self.width * self.height * 4) as usize }
    pub fn get_bpp(&self) -> u32 { 4 }
    pub fn copy_onto_dmabuf(&mut self, _stride: Option<u32>, _data: &[u8]) -> Result<(), String> { Err("GBM not available on Android".into()) }
    pub fn copy_from_dmabuf(&mut self, _stride: Option<u32>, _data: &mut [u8]) -> Result<(), String> { Err("GBM not available on Android".into()) }
}

pub fn new(_path: &str) -> Result<GbmDevice, ()> { Err(()) }
pub fn gbm_supported_modifiers(_gbm: &GbmDevice, _format: u32) -> &'static [u64] { &[] }
pub fn setup_gbm_device(_path: Option<u64>) -> Result<Option<Rc<GbmDevice>>, String> { Ok(None) }
pub fn gbm_import_dmabuf(_gbm: &GbmDevice, _planes: Vec<AddDmabufPlane>, _w: u32, _h: u32, _f: u32) -> Result<GbmBo, String> { Err("GBM not available on Android".into()) }
pub fn gbm_create_dmabuf(_gbm: &GbmDevice, _w: u32, _h: u32, _f: u32, _m: &[u64]) -> Result<(GbmBo, Vec<AddDmabufPlane>), String> { Err("GBM not available on Android".into()) }
pub fn gbm_get_device_id(_gbm: &GbmDevice) -> u64 { 0 }
GBM_STUB
  echo "✓ Stubbed gbm.rs"
fi

# Stub out video.rs — Android doesn't use Vulkan Video / FFmpeg codec
# Signatures must match what mainloop.rs and dmabuf.rs call with.
if [ -f "src/video.rs" ]; then
  cat > src/video.rs <<'VIDEO_STUB'
#![allow(dead_code, unused_imports, unused_variables)]
use std::sync::Arc;
use crate::dmabuf;
pub use crate::util::VideoFormat;

pub struct VideoContext;
pub struct VulkanVideo;
pub struct VideoEncodeState;
pub struct VideoDecodeState;

pub struct VulkanDecodeOpHandle;
impl VulkanDecodeOpHandle {
    pub fn get_timeline_point(&self) -> u64 { 0 }
}

pub fn setup_video_context(_debug: bool) -> Result<Option<VideoContext>, String> {
    Ok(None)
}

pub fn destroy_video(_dev: &ash::Device, _v: &VulkanVideo) {}
pub fn video_lock_queue(_v: &VulkanVideo, _queue_family: u32) {}
pub fn video_unlock_queue(_v: &VulkanVideo, _queue_family: u32) {}

pub fn setup_video(
    _entry: &ash::Entry,
    _instance: &ash::Instance,
    _physdev: &ash::vk::PhysicalDevice,
    _dev: &ash::Device,
    _dev_info: &dmabuf::DeviceInfo,
    _debug: bool,
    _qfis: [u32; 4],
    _enabled_exts: &[*const u8],
    _instance_exts: &[*const u8],
) -> Result<Option<VulkanVideo>, String> {
    Ok(None)
}

pub fn supports_video_format(
    _dev: &dmabuf::VulkanDevice,
    _vid_type: VideoFormat,
    _format: u32,
    _width: u32,
    _height: u32,
) -> bool {
    false
}

pub fn setup_video_encode(
    _buf: &Arc<dmabuf::VulkanDmabuf>,
    _f: VideoFormat,
    _bits_per_frame: Option<f32>,
) -> Result<VideoEncodeState, String> {
    Err("Vulkan Video encode not available on Android".into())
}

pub fn setup_video_decode(
    _buf: &Arc<dmabuf::VulkanDmabuf>,
    _vid_type: VideoFormat,
) -> Result<VideoDecodeState, String> {
    Err("Vulkan Video decode not available on Android".into())
}

pub fn start_dmavid_encode(
    _state: &VideoEncodeState,
    _pool: &Arc<dmabuf::VulkanCommandPool>,
    _explicit: &[(Arc<dmabuf::VulkanTimelineSemaphore>, u64)],
    _implicit: &[dmabuf::VulkanBinarySemaphore],
) -> Result<Vec<u8>, String> {
    Err("Vulkan Video encode not available on Android".into())
}

pub fn start_dmavid_apply(
    _state: &Arc<VideoDecodeState>,
    _pool: &Arc<dmabuf::VulkanCommandPool>,
    _packet: &[u8],
) -> Result<VulkanDecodeOpHandle, String> {
    Err("Vulkan Video decode not available on Android".into())
}
VIDEO_STUB
  echo "✓ Stubbed video.rs"
fi

echo "✓ Waypipe patched for Android (OpenSSH, no libssh2)"
