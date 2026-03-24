{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  androidToolchain ? (import ../../toolchains/android.nix { inherit lib pkgs; }),
  ...
}:

let
  fetchSource = common.fetchSource;
  # androidToolchain passed from caller
  waypipeSource = {
    source = "gitlab";
    owner = "mstoeckl";
    repo = "waypipe";
    tag = "v0.10.6";
    sha256 = "sha256-Tbd/yY90yb2+/ODYVL3SudHaJCGJKatZ9FuGM2uAX+8=";
  };

  # Dependencies
  libwayland = buildModule.buildForAndroid "libwayland" { };
  # Vulkan driver for Android: SwiftShader (CPU-based fallback)
  swiftshader = buildModule.buildForAndroid "swiftshader" { };
  # Compression libraries for waypipe features
  zstd = buildModule.buildForAndroid "zstd" { };
  lz4 = buildModule.buildForAndroid "lz4" { };
  # FFmpeg for video encoding/decoding
  ffmpeg = buildModule.buildForAndroid "ffmpeg" { };
  # wayland-protocols is needed for protocol definitions (XMLs)
  waylandProtocols = pkgs.wayland-protocols;

  # Build flags and features
  cargoBuildFeatures = [
    "dmabuf"
    "video"
  ];

  # Use pre-generated Cargo.lock that includes bindgen for reproducible builds
  # This file was generated once and committed to the repository to avoid
  # network access during builds (which breaks Nix reproducibility)
  updatedCargoLockFile = ./Cargo.lock.patched;

  # Define custom rust platform with Android target to avoid pkgsCross bootstrap issues
  rustToolchain = pkgs.rust-bin.stable.latest.default.override {
    targets = [ "aarch64-linux-android" ];
  };

  rustPlatform = pkgs.makeRustPlatform {
    cargo = rustToolchain;
    rustc = rustToolchain;
  };

  NDK_SYSROOT = "${androidToolchain.androidndkRoot}/toolchains/llvm/prebuilt/darwin-x86_64/sysroot";
  NDK_LIB_PATH = "${NDK_SYSROOT}/usr/lib/aarch64-linux-android/${toString androidToolchain.androidApiLevel}";
  NDK_USR_LIB_PATH = "${NDK_SYSROOT}/usr/lib/aarch64-linux-android";

  # Wrapper for the linker to ensure the correct target is passed to clang
  androidLinkerWrapper = pkgs.writeShellScript "android-linker-wrapper" ''
    exec ${androidToolchain.androidCC} \
      --target=${androidToolchain.androidTarget} \
      --sysroot=${NDK_SYSROOT} \
      -L${NDK_LIB_PATH} \
      -L${NDK_USR_LIB_PATH} \
      "$@"
  '';

in
rustPlatform.buildRustPackage {
  pname = "waypipe";
  version = "v0.10.6";

  src =
    pkgs.runCommand "waypipe-src-with-bindgen"
      {
        src = fetchSource waypipeSource;
      }
      ''
            mkdir -p $out
            if [ -d "$src" ]; then 
              cp -r "$src"/. "$out/"
            else 
              tar -xf "$src" -C "$out" --strip-components=1
            fi
            chmod -R u+w $out
            cd $out
            
            if [ -f "wrap-ffmpeg/Cargo.toml" ] && ! grep -q "bindgen" wrap-ffmpeg/Cargo.toml; then
              if grep -q "\[build-dependencies\]" wrap-ffmpeg/Cargo.toml; then
                sed -i '/\[build-dependencies\]/a\bindgen = "0.69"' wrap-ffmpeg/Cargo.toml
              else
                echo "" >> wrap-ffmpeg/Cargo.toml; echo "[build-dependencies]" >> wrap-ffmpeg/Cargo.toml; echo 'bindgen = "0.69"' >> wrap-ffmpeg/Cargo.toml
              fi
            fi
            
            if [ -f "wrap-ffmpeg/Cargo.toml" ] && ! grep -q "pkg-config" wrap-ffmpeg/Cargo.toml; then
              if grep -q "\[build-dependencies\]" wrap-ffmpeg/Cargo.toml; then
                sed -i '/\[build-dependencies\]/a\pkg-config = "0.3"' wrap-ffmpeg/Cargo.toml
              else
                echo "" >> wrap-ffmpeg/Cargo.toml; echo "[build-dependencies]" >> wrap-ffmpeg/Cargo.toml; echo 'pkg-config = "0.3"' >> wrap-ffmpeg/Cargo.toml
              fi
            fi

            # Add bindgen and pkg-config to wrap-lz4
            if [ -f "wrap-lz4/Cargo.toml" ] && ! grep -q "bindgen" wrap-lz4/Cargo.toml; then
              if grep -q "\[build-dependencies\]" wrap-lz4/Cargo.toml; then
                sed -i '/\[build-dependencies\]/a\bindgen = "0.69"' wrap-lz4/Cargo.toml
              else
                echo "" >> wrap-lz4/Cargo.toml; echo "[build-dependencies]" >> wrap-lz4/Cargo.toml; echo 'bindgen = "0.69"' >> wrap-lz4/Cargo.toml
              fi
            fi
            if [ -f "wrap-lz4/Cargo.toml" ] && ! grep -q "pkg-config" wrap-lz4/Cargo.toml; then
              if grep -q "\[build-dependencies\]" wrap-lz4/Cargo.toml; then
                sed -i '/\[build-dependencies\]/a\pkg-config = "0.3"' wrap-lz4/Cargo.toml
              else
                echo "" >> wrap-lz4/Cargo.toml; echo "[build-dependencies]" >> wrap-lz4/Cargo.toml; echo 'pkg-config = "0.3"' >> wrap-lz4/Cargo.toml
              fi
            fi

            # Add bindgen and pkg-config to wrap-zstd
            if [ -f "wrap-zstd/Cargo.toml" ] && ! grep -q "bindgen" wrap-zstd/Cargo.toml; then
              if grep -q "\[build-dependencies\]" wrap-zstd/Cargo.toml; then
                sed -i '/\[build-dependencies\]/a\bindgen = "0.69"' wrap-zstd/Cargo.toml
              else
                echo "" >> wrap-zstd/Cargo.toml; echo "[build-dependencies]" >> wrap-zstd/Cargo.toml; echo 'bindgen = "0.69"' >> wrap-zstd/Cargo.toml
              fi
            fi
            if [ -f "wrap-zstd/Cargo.toml" ] && ! grep -q "pkg-config" wrap-zstd/Cargo.toml; then
              if grep -q "\[build-dependencies\]" wrap-zstd/Cargo.toml; then
                sed -i '/\[build-dependencies\]/a\pkg-config = "0.3"' wrap-zstd/Cargo.toml
              else
                echo "" >> wrap-zstd/Cargo.toml; echo "[build-dependencies]" >> wrap-zstd/Cargo.toml; echo 'pkg-config = "0.3"' >> wrap-zstd/Cargo.toml
              fi
            fi

            # Overwrite wrap-zstd/build.rs to use pkg-config
            cat > wrap-zstd/build.rs <<'EOF'
        fn main() {
            use std::env;
            use std::path::PathBuf;
            
            // Explicitly link search path from env var
            if let Ok(path) = std::env::var("ZSTD_LIB_DIR") {
                println!("cargo:rustc-link-search=native={}", path);
            }

            let library = pkg_config::Config::new().probe("libzstd").unwrap();
            
            // Manually emit link search paths to ensure they are passed to the linker
            for path in &library.link_paths {
                println!("cargo:rustc-link-search=native={}", path.display());
            }

            let mut clang_args = Vec::new();
            for path in library.include_paths {
                clang_args.push(format!("-I{}", path.display()));
            }
            
            if let Ok(extra_args) = std::env::var("BINDGEN_EXTRA_CLANG_ARGS") {
                for arg in extra_args.split_whitespace() { clang_args.push(arg.to_string()); }
            }

            let bindings = bindgen::Builder::default()
                .header("wrapper.h")
                .clang_args(&clang_args)
                .allowlist_function("ZSTD_.*")
                .generate()
                .expect("Unable to generate bindings");
            
            let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());
            bindings.write_to_file(out_path.join("bindings.rs")).expect("Couldn't write bindings!");
        }
        EOF

            # Overwrite wrap-lz4/build.rs to use pkg-config
            cat > wrap-lz4/build.rs <<'EOF'
        fn main() {
            use std::env;
            use std::path::PathBuf;
            
            // Explicitly link search path from env var
            if let Ok(path) = std::env::var("LZ4_LIB_DIR") {
                println!("cargo:rustc-link-search=native={}", path);
            }

            let library = pkg_config::Config::new().probe("liblz4").unwrap();
            
            // Manually emit link search paths to ensure they are passed to the linker
            for path in &library.link_paths {
                println!("cargo:rustc-link-search=native={}", path.display());
            }
            
            let mut clang_args = Vec::new();
            for path in library.include_paths {
                clang_args.push(format!("-I{}", path.display()));
            }
            
            if let Ok(extra_args) = std::env::var("BINDGEN_EXTRA_CLANG_ARGS") {
                for arg in extra_args.split_whitespace() { clang_args.push(arg.to_string()); }
            }

            let bindings = bindgen::Builder::default()
                .header("wrapper.h")
                .clang_args(&clang_args)
                .allowlist_function("LZ4_.*")
                .generate()
                .expect("Unable to generate bindings");
            
            let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());
            bindings.write_to_file(out_path.join("bindings.rs")).expect("Couldn't write bindings!");
        }
        EOF

      '';

  cargoHash = lib.fakeHash;
  cargoLock = {
    lockFile = updatedCargoLockFile;
  };
  cargoDeps = null;

  nativeBuildInputs = with buildPackages; [
    pkg-config
    waylandProtocols
    rustPlatform.bindgenHook
    shaderc
    # Need python3 for some scripts?
  ];

  buildInputs = [
    libwayland
    swiftshader # Vulkan ICD driver for Android
    zstd # Compression library
    lz4 # Compression library
    ffmpeg # Video encoding/decoding
  ];

  # Cross-compilation targets
  CARGO_BUILD_TARGET = "aarch64-linux-android";

  # Configure compilers for the target
  CC_aarch64_linux_android = "${androidLinkerWrapper}";
  CXX_aarch64_linux_android = androidToolchain.androidCXX;
  AR_aarch64_linux_android = androidToolchain.androidAR;
  CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER = "${androidLinkerWrapper}";

  buildFeatures = cargoBuildFeatures;

  # Force cargo to build for the Android target
  cargoBuildFlags = [
    "--target"
    "aarch64-linux-android"
    "--bin"
    "waypipe"
  ];

  doCheck = false;

  preConfigure = ''
    # Debug: List wrap-zstd and wrap-lz4 contents
    echo "=== wrap-zstd contents ==="
    ls -R wrap-zstd || echo "Failed to list wrap-zstd"
    echo "=== wrap-zstd/build.rs content ==="
    cat wrap-zstd/build.rs || echo "No build.rs in wrap-zstd"

    echo "=== wrap-lz4 contents ==="
    ls -R wrap-lz4 || echo "Failed to list wrap-lz4"
    echo "=== wrap-lz4/build.rs content ==="
    cat wrap-lz4/build.rs || echo "No build.rs in wrap-lz4"

    # Set GLSLC path for waypipe-shaders build script
    export GLSLC="${lib.getBin buildPackages.shaderc}/bin/glslc"
    echo "Using GLSLC: $GLSLC"

    # Set PKG_CONFIG_PATH to find target libraries
    export PKG_CONFIG_PATH="${libwayland}/lib/pkgconfig:${waylandProtocols}/share/pkgconfig:${zstd}/lib/pkgconfig:${lz4}/lib/pkgconfig:${ffmpeg}/lib/pkgconfig:$PKG_CONFIG_PATH"
    export PKG_CONFIG_ALLOW_CROSS=1
    export PKG_CONFIG_aarch64_linux_android="${buildPackages.pkg-config}/bin/pkg-config"
    echo "Using PKG_CONFIG_PATH: $PKG_CONFIG_PATH"

    # Set up library search paths for Vulkan driver
    export LIBRARY_PATH="${swiftshader}/lib:${libwayland}/lib:${zstd}/lib:${lz4}/lib:${ffmpeg}/lib:$LIBRARY_PATH"

    # Export specific lib paths for build.rs to pick up if pkg-config fails to propagate them
    export ZSTD_LIB_DIR="${zstd}/lib"
    export LZ4_LIB_DIR="${lz4}/lib"

    # Set up include paths for bindgen (needed for wrap-zstd, wrap-lz4, and wrap-ffmpeg)
    export C_INCLUDE_PATH="${zstd}/include:${lz4}/include:${ffmpeg}/include:$C_INCLUDE_PATH"
    export CPP_INCLUDE_PATH="${zstd}/include:${lz4}/include:${ffmpeg}/include:$CPP_INCLUDE_PATH"

    # Configure Bindgen to find Android NDK headers and FFmpeg
    # We need to point to the sysroot include directories
    NDK_SYSROOT="${NDK_SYSROOT}"
    export BINDGEN_EXTRA_CLANG_ARGS="-isystem ${zstd}/include -isystem ${lz4}/include -isystem ${ffmpeg}/include -isystem $NDK_SYSROOT/usr/include -isystem $NDK_SYSROOT/usr/include/aarch64-linux-android --target=aarch64-linux-android"
    echo "BINDGEN_EXTRA_CLANG_ARGS: $BINDGEN_EXTRA_CLANG_ARGS"

    echo "Vulkan driver (SwiftShader) library path: ${swiftshader}/lib"
    ls -la "${swiftshader}/lib/" || echo "Warning: SwiftShader lib directory not found"

    echo "=== NDK Sysroot Debug ==="
    echo "NDK_SYSROOT: ${NDK_SYSROOT}"
    echo "Checking lib paths:"
    ls -la "${NDK_SYSROOT}/usr/lib/aarch64-linux-android/" || echo "NDK lib path not found"
    if [ -d "${NDK_SYSROOT}/usr/lib/aarch64-linux-android/30" ]; then
      echo "Content of API 30 lib:"
      ls -la "${NDK_SYSROOT}/usr/lib/aarch64-linux-android/30" | grep crt || echo "No crt files found in API 30"
    else
      echo "API 30 lib dir not found"
    fi
  '';

  # Custom build and install phases to avoid host target confusion
  buildPhase = ''
    echo "Running custom buildPhase for Android..."
    export CARGO_HOME=$(pwd)/.cargo_home
    mkdir -p $CARGO_HOME

    # We need to ensure cargo finds the vendored dependencies
    # configurePhase should have set up .cargo/config

    echo "PKG_CONFIG_PATH: $PKG_CONFIG_PATH"
    echo "Testing pkg-config for libzstd:"
    $PKG_CONFIG_aarch64_linux_android --libs libzstd || echo "pkg-config failed"
    echo "Testing pkg-config for liblz4:"
    $PKG_CONFIG_aarch64_linux_android --libs liblz4 || echo "pkg-config failed"

    # Pass library paths via RUSTFLAGS to ensure linker finds them
    export RUSTFLAGS="-L native=${zstd}/lib -L native=${lz4}/lib"

    echo "Starting cargo build..."
    cargo build -vv --target aarch64-linux-android --release --bin waypipe --offline --features "dmabuf,video"
  '';

  installPhase = ''
    echo "Installing binary..."
    mkdir -p $out/bin
    cp target/aarch64-linux-android/release/waypipe $out/bin/
  '';

  # Patch waypipe wrappers for Android
  postPatch = ''
        echo "=== Patching waypipe wrappers for Android ==="
        
        # Copy generated Cargo.lock
        cp ${updatedCargoLockFile} Cargo.lock

        # Stub GBM for Android (as we don't have libgbm usually)
        if [ -f "wrap-gbm/build.rs" ]; then
          cat > wrap-gbm/build.rs <<'BUILDRS_EOF'
    fn main() {
        use std::env;
        use std::fs;
        use std::path::PathBuf;
        let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
        let bindings_rs = out_dir.join("bindings.rs");
        // Force GBM stubbing on Android
        fs::write(&bindings_rs, "// GBM bindings disabled - GBM not available on this platform\n").unwrap();
        println!("cargo:warning=GBM not required on this platform");
    }
    BUILDRS_EOF
        fi
        
        # Create src/gbm.rs stub for Android (replacing original)
        cat > src/gbm.rs <<'GBM_EOF'
    use std::os::unix::io::RawFd;
    use crate::util::AddDmabufPlane;
    use std::rc::Rc;

    pub struct GbmDevice {}
    impl GbmDevice {
        pub fn new(_fd: RawFd) -> Result<Rc<Self>, String> { Ok(Rc::new(Self {})) }
    }

    pub struct GbmDmabuf {
        pub width: u32,
        pub height: u32,
        pub stride: u32,
        pub format: u32,
    }
    impl GbmDmabuf {
        pub fn nominal_size(&self, _stride: Option<u32>) -> usize { (self.width * self.height * 4) as usize }
        pub fn get_bpp(&self) -> u32 { 4 }
        pub fn copy_onto_dmabuf(&mut self, _stride: Option<u32>, _data: &[u8]) -> Result<(), String> {
            Err("GBM not supported".to_string())
        }
        pub fn copy_from_dmabuf(&mut self, _stride: Option<u32>, _data: &mut [u8]) -> Result<(), String> {
            Err("GBM not supported".to_string())
        }
    }
    pub type GbmBo = GbmDmabuf;
    pub type GBMDmabuf = GbmDmabuf;
    pub type GBMDevice = GbmDevice;

    pub fn gbm_import_dmabuf<T>(_gbm: &GbmDevice, _planes: Vec<T>, _width: u32, _height: u32, _format: u32) -> Result<GbmDmabuf, String> {
         Err("GBM not supported".to_string())
    }

    pub fn gbm_supported_modifiers(_gbm: &GbmDevice, _format: u32) -> &'static [u64] {
        &[]
    }

    pub fn gbm_create_dmabuf(_gbm: &GbmDevice, _width: u32, _height: u32, _format: u32, _modifiers: &[u64]) -> Result<(GbmDmabuf, Vec<AddDmabufPlane>), String> {
        Err("GBM not supported".to_string())
    }

    pub fn gbm_get_device_id(_gbm: &GbmDevice) -> u64 {
        0
    }

    pub fn setup_gbm_device(_device: Option<u64>) -> Result<Option<Rc<GbmDevice>>, String> {
        Ok(None)
    }
    GBM_EOF

        # Patch src/main.rs for pipe2 compat on Android
        if [ -f "src/main.rs" ]; then
            # Add libc dependency to Cargo.toml
            sed -i '/\[dependencies\]/a\libc = "0.2"' Cargo.toml

            # Remove test_proto binary from Cargo.toml to avoid build failures
            sed -i '/\[\[bin\]\]/,/name = "test_proto"/d' Cargo.toml
            sed -i '/path = "src\/test_proto.rs"/d' Cargo.toml
            
            # Patch src/dmabuf.rs to use libc directly instead of nix::libc and handle missing eventfd/memfd
            if [ -f "src/dmabuf.rs" ]; then
                 # Remove existing nix::sys::memfd import
                 sed -i 's/use nix::sys::memfd;//g' src/dmabuf.rs
                 
                 # Create android_compat content with top-level definitions
                 cat > android_compat.rs <<'RUST_EOF'

    pub const EFD_CLOEXEC_COMPAT: libc::c_int = 0o2000000;
    pub const EFD_NONBLOCK_COMPAT: libc::c_int = 0o4000;

    pub unsafe fn eventfd_compat(initval: libc::c_uint, flags: libc::c_int) -> libc::c_int {
        // SYS_eventfd2 = 290 on aarch64
        libc::syscall(290, initval, flags) as libc::c_int
    }

    pub mod memfd_compat {
        use super::*;
        use std::os::fd::OwnedFd;
        use std::os::fd::FromRawFd;
        
        #[derive(Clone, Copy)]
        pub struct MFdFlags(pub libc::c_uint);
        impl MFdFlags {
            pub const MFD_CLOEXEC: MFdFlags = MFdFlags(0x0001);
            pub const MFD_ALLOW_SEALING: MFdFlags = MFdFlags(0x0002);
        }
        impl std::ops::BitOr for MFdFlags {
            type Output = Self;
            fn bitor(self, rhs: Self) -> Self {
                MFdFlags(self.0 | rhs.0)
            }
        }

        pub fn memfd_create(name: &std::ffi::CStr, flags: MFdFlags) -> nix::Result<OwnedFd> {
            // SYS_memfd_create = 279 on aarch64
            let res = unsafe { libc::syscall(279, name.as_ptr(), flags.0) };
            if res < 0 {
                return Err(nix::errno::Errno::last());
            }
            unsafe { Ok(OwnedFd::from_raw_fd(res as i32)) }
        }
    }
    RUST_EOF
                 
                 # Insert android_compat content after module attributes
                 # We need to insert after #![cfg(feature = "dmabuf")] to avoid inner attribute errors
                 if grep -q '#!\[cfg(feature = "dmabuf")\]' src/dmabuf.rs; then
                     sed -i '/#!\[cfg(feature = "dmabuf")\]/r android_compat.rs' src/dmabuf.rs
                 else
                     # Fallback if line not found (shouldn't happen based on logs)
                     cat android_compat.rs src/dmabuf.rs > src/dmabuf.rs.new
                     mv src/dmabuf.rs.new src/dmabuf.rs
                 fi

                 # Replace usages
                 sed -i 's/nix::libc::EFD_CLOEXEC/EFD_CLOEXEC_COMPAT/g' src/dmabuf.rs
                 sed -i 's/nix::libc::EFD_NONBLOCK/EFD_NONBLOCK_COMPAT/g' src/dmabuf.rs
                 sed -i 's/nix::libc::eventfd/eventfd_compat/g' src/dmabuf.rs
                 sed -i 's/nix::sys::memfd/memfd_compat/g' src/dmabuf.rs
                 
                 # Also replace libc::EFD_... if my previous sed replaced nix::libc:: with libc::
                 sed -i 's/libc::EFD_CLOEXEC/EFD_CLOEXEC_COMPAT/g' src/dmabuf.rs
                 sed -i 's/libc::EFD_NONBLOCK/EFD_NONBLOCK_COMPAT/g' src/dmabuf.rs
                 sed -i 's/libc::eventfd/eventfd_compat/g' src/dmabuf.rs
            fi

            # Inject pipe2_compat into src/read.rs if it exists (it uses pipe2)
            if [ -f "src/read.rs" ]; then
                # Add imports
                sed -i '0,/^use/s/^use/use crate::mainloop::pipe2_compat;\nuse/' src/read.rs
                # Replace pipe2 calls
                sed -i 's/unistd::pipe2/pipe2_compat/g' src/read.rs
            fi

            # Inject waitid_compat, pipe2_compat, and ppoll_compat into src/mainloop.rs
            # This makes them available to other modules too if we make them pub
            cat >> src/mainloop.rs <<'RUST_EOF'

    // Android compatibility wrappers
    pub fn waitid_compat(_id: (), flags: nix::sys::wait::WaitPidFlag) -> nix::Result<nix::sys::wait::WaitStatus> {
        nix::sys::wait::waitpid(None, Some(flags))
    }

    pub fn pipe2_compat(flags: nix::fcntl::OFlag) -> nix::Result<(std::os::fd::OwnedFd, std::os::fd::OwnedFd)> {
        use std::os::fd::FromRawFd;
        let mut fds = [0i32; 2];
        
        // Fallback to pipe() + fcntl() since libc::pipe2 might be missing in Android bindings
        let res = unsafe { libc::pipe(fds.as_mut_ptr()) };
        if res < 0 {
            return Err(nix::errno::Errno::last());
        }

        let r_fd = fds[0];
        let w_fd = fds[1];
        
        let set_flags = |fd: i32| -> nix::Result<()> {
            if flags.contains(nix::fcntl::OFlag::O_CLOEXEC) {
                let mut current = unsafe { libc::fcntl(fd, libc::F_GETFD) };
                if current >= 0 {
                    current |= libc::FD_CLOEXEC;
                    unsafe { libc::fcntl(fd, libc::F_SETFD, current) };
                }
            }
            if flags.contains(nix::fcntl::OFlag::O_NONBLOCK) {
                let mut current = unsafe { libc::fcntl(fd, libc::F_GETFL) };
                if current >= 0 {
                    current |= libc::O_NONBLOCK;
                    unsafe { libc::fcntl(fd, libc::F_SETFL, current) };
                }
            }
            Ok(())
        };

        if let Err(e) = set_flags(r_fd) {
            unsafe { libc::close(r_fd); libc::close(w_fd); }
            return Err(e);
        }
        if let Err(e) = set_flags(w_fd) {
            unsafe { libc::close(r_fd); libc::close(w_fd); }
            return Err(e);
        }

        unsafe {
            Ok((
                std::os::fd::OwnedFd::from_raw_fd(r_fd),
                std::os::fd::OwnedFd::from_raw_fd(w_fd),
            ))
        }
    }

    pub fn ppoll_compat(fds: &mut [nix::poll::PollFd], timeout: Option<nix::sys::time::TimeSpec>, _sigmask: Option<nix::sys::signal::SigSet>) -> nix::Result<libc::c_int> {
        let timeout_ms = match timeout {
            Some(ts) => (ts.tv_sec() * 1000 + ts.tv_nsec() / 1000000) as libc::c_int,
            None => -1,
        };
        let res = unsafe { libc::poll(fds.as_mut_ptr() as *mut libc::pollfd, fds.len() as libc::nfds_t, timeout_ms) };
        if res < 0 {
            return Err(nix::errno::Errno::last());
        }
        Ok(res)
    }
    RUST_EOF

            # Fix src/main.rs usage
            # Import waitid_compat, pipe2_compat, ppoll_compat from mainloop
            if grep -q "mod mainloop;" src/main.rs; then
                 sed -i '/mod mainloop;/a\
    use crate::mainloop::{waitid_compat, pipe2_compat, ppoll_compat};
    ' src/main.rs
            fi

            # Replace nix::poll::ppoll with ppoll_compat in src/main.rs
            sed -i 's/nix::poll::ppoll/ppoll_compat/g' src/main.rs
            # Replace nix::poll::ppoll with ppoll_compat in src/mainloop.rs (if used there)
            sed -i 's/nix::poll::ppoll/ppoll_compat/g' src/mainloop.rs

            # Replace unistd::pipe2 with pipe2_compat in src/main.rs
            sed -i 's/unistd::pipe2/pipe2_compat/g' src/main.rs
            # Replace unistd::pipe2 with pipe2_compat in src/mainloop.rs
            sed -i 's/unistd::pipe2/pipe2_compat/g' src/mainloop.rs

            # Replace wait::Id::All with () globally in src/main.rs and src/mainloop.rs
            sed -i 's/wait::Id::All/()/g' src/main.rs
            sed -i 's/wait::Id::All/()/g' src/mainloop.rs
            
            # Replace wait::waitid with waitid_compat
            sed -i 's/wait::waitid/waitid_compat/g' src/main.rs
            sed -i 's/wait::waitid/waitid_compat/g' src/mainloop.rs
            
            # Handle import if waitid is imported
            sed -i 's/use nix::sys::wait::waitid;/use nix::sys::wait::waitpid;/g' src/main.rs
            sed -i 's/use nix::sys::wait::waitid;/use nix::sys::wait::waitpid;/g' src/mainloop.rs
            
            # Fix memfd usage in mainloop.rs and tracking.rs
            if [ -f "src/mainloop.rs" ]; then
                 # Remove memfd from nested import
                 sed -i 's/memfd, //g' src/mainloop.rs
                 sed -i 's/, memfd//g' src/mainloop.rs
                 # Add replacement import
                 sed -i '/use nix::sys::{/a use crate::dmabuf::memfd_compat as memfd;' src/mainloop.rs
            fi
            
            if [ -f "src/tracking.rs" ]; then
                 sed -i 's/use nix::sys::memfd;/use crate::dmabuf::memfd_compat as memfd;/g' src/tracking.rs
            fi
            
            # Silence unused variable warning for abstract_socket
            sed -i 's/let abstract_socket =/let _abstract_socket =/g' src/main.rs

            # Try to match other patterns for pipe2/ppoll to avoid unused imports
            sed -i 's/pipe2(/pipe2_compat(/g' src/main.rs
            sed -i 's/ppoll(/ppoll_compat(/g' src/main.rs
        fi


        
        # Patch src/platform.rs for st_rdev type mismatch
        if [ -f "src/platform.rs" ]; then
            sed -i 's/result.st_rdev.into()/result.st_rdev as u64/g' src/platform.rs
        fi
        
        # Patch shaders/build.rs to use GLSLC env var
        if [ -f "shaders/build.rs" ]; then
            sed -i 's/let compiler = "glslc";/let compiler = env::var("GLSLC").unwrap_or_else(|_| "glslc".to_string());/' shaders/build.rs
            sed -i 's/Command::new(compiler)/Command::new(\&compiler)/g' shaders/build.rs
        fi

        # Patch source files for SockFlag on Android
        # Replace SockFlag::SOCK_CLOEXEC and SOCK_NONBLOCK with from_bits_truncate
        # Use libc::O_CLOEXEC/O_NONBLOCK as fallbacks if SOCK_ constants are missing
        find src -name "*.rs" -exec sed -i 's/socket::SockFlag::SOCK_CLOEXEC/socket::SockFlag::from_bits_truncate(libc::O_CLOEXEC)/g' {} +
        find src -name "*.rs" -exec sed -i 's/socket::SockFlag::SOCK_NONBLOCK/socket::SockFlag::from_bits_truncate(libc::O_NONBLOCK)/g' {} +

        # Patch wrap-ffmpeg build.rs
        if [ -f "wrap-ffmpeg/build.rs" ]; then
          cat > wrap-ffmpeg/wrapper.h <<'WRAPPER_EOF'
    #include <libavutil/avutil.h>
    #include <libavcodec/avcodec.h>
    #include <libavutil/hwcontext.h>
    #include <libavutil/hwcontext_vulkan.h>
    #include <libavutil/pixfmt.h>
    WRAPPER_EOF

          cat > wrap-ffmpeg/build.rs <<'BUILDRS_EOF'
    fn main() {
        use std::env;
        use std::path::PathBuf;
        let pkg_config = pkg_config::Config::new();
        let ffmpeg = pkg_config.probe("libavutil").expect("Could not find libavutil");
        let avcodec = pkg_config::Config::new().probe("libavcodec").expect("Could not find libavcodec");
        
        let mut include_paths = std::collections::HashSet::new();
        for path in &ffmpeg.include_paths { include_paths.insert(path.clone()); }
        for path in &avcodec.include_paths { include_paths.insert(path.clone()); }
        
        if include_paths.is_empty() {
            if let Ok(pkg_config_path) = std::env::var("PKG_CONFIG_PATH") {
                for path in pkg_config_path.split(':') {
                    if path.contains("ffmpeg") {
                         if let Some(base) = path.strip_suffix("/lib/pkgconfig") {
                            let include_path = format!("{}/include", base);
                            if std::path::Path::new(&include_path).exists() {
                                include_paths.insert(std::path::PathBuf::from(include_path));
                            }
                        }
                    }
                }
            }
        }
        
        let mut clang_args: Vec<String> = include_paths.iter().map(|path| format!("-I{}", path.display())).collect();
        if let Ok(extra_args) = std::env::var("BINDGEN_EXTRA_CLANG_ARGS") {
            for arg in extra_args.split_whitespace() { clang_args.push(arg.to_string()); }
        }
        
        let bindings = bindgen::Builder::default()
            .header("wrapper.h")
            .clang_args(&clang_args)
            .allowlist_type("AV.*")
            .allowlist_function("av.*")
            .allowlist_var("AV_.*")
            .allowlist_var("LIBAV.*")
            .dynamic_library_name("ffmpeg")
            .dynamic_link_require_all(true)
            .generate()
            .expect("Unable to generate bindings");
        
        let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());
        bindings.write_to_file(out_path.join("bindings.rs")).expect("Couldn't write bindings!");
    }
    BUILDRS_EOF
        fi

        # Patch wrap-lz4 build.rs
        if [ -f "wrap-lz4/build.rs" ]; then
          cat > wrap-lz4/wrapper.h <<'WRAPPER_EOF'
    #include <lz4.h>
    #include <lz4hc.h>
    WRAPPER_EOF

          cat > wrap-lz4/build.rs <<'BUILDRS_EOF'
    fn main() {
        use std::env;
        use std::path::PathBuf;
        
        let mut include_paths = std::collections::HashSet::new();
        
        if let Ok(pkg_config_path) = std::env::var("PKG_CONFIG_PATH") {
            for path in pkg_config_path.split(':') {
                if path.contains("lz4") {
                     if let Some(base) = path.strip_suffix("/lib/pkgconfig") {
                        let include_path = format!("{}/include", base);
                        if std::path::Path::new(&include_path).exists() {
                            include_paths.insert(std::path::PathBuf::from(include_path));
                        }
                    }
                }
            }
        }
        
        let mut clang_args: Vec<String> = include_paths.iter().map(|path| format!("-I{}", path.display())).collect();
        if let Ok(extra_args) = std::env::var("BINDGEN_EXTRA_CLANG_ARGS") {
            for arg in extra_args.split_whitespace() { clang_args.push(arg.to_string()); }
        }
        
        println!("cargo:rustc-link-lib=lz4");
        
        let bindings = bindgen::Builder::default()
            .header("wrapper.h")
            .clang_args(&clang_args)
            .allowlist_function("LZ4_.*")
            .generate()
            .expect("Unable to generate bindings");
        
        let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());
        bindings.write_to_file(out_path.join("bindings.rs")).expect("Couldn't write bindings!");
    }
    BUILDRS_EOF
        fi

        # Patch wrap-ffmpeg/src/lib.rs
        if [ -f "wrap-ffmpeg/src/lib.rs" ]; then
          cat > wrap-ffmpeg/src/lib.rs <<'LIBRS_EOF'
    #![allow(non_upper_case_globals)]
    #![allow(non_camel_case_types)]
    #![allow(non_snake_case)]
    #![allow(improper_ctypes)]
    include!(concat!(env!("OUT_DIR"), "/bindings.rs"));
    LIBRS_EOF
        fi

        # Patch wrap-lz4/src/lib.rs
        if [ -f "wrap-lz4/src/lib.rs" ]; then
          cat > wrap-lz4/src/lib.rs <<'LIBRS_EOF'
    #![allow(non_upper_case_globals)]
    #![allow(non_camel_case_types)]
    #![allow(non_snake_case)]
    #![allow(improper_ctypes)]
    include!(concat!(env!("OUT_DIR"), "/bindings.rs"));
    LIBRS_EOF
        fi

        # Patch wrap-zstd/src/lib.rs
        if [ -f "wrap-zstd/src/lib.rs" ]; then
          cat > wrap-zstd/src/lib.rs <<'LIBRS_EOF'
    #![allow(non_upper_case_globals)]
    #![allow(non_camel_case_types)]
    #![allow(non_snake_case)]
    #![allow(improper_ctypes)]
    include!(concat!(env!("OUT_DIR"), "/bindings.rs"));
    LIBRS_EOF
        fi

        # Patch wrap-zstd build.rs
        if [ -f "wrap-zstd/build.rs" ]; then
          cat > wrap-zstd/wrapper.h <<'WRAPPER_EOF'
    #include <zstd.h>
    WRAPPER_EOF

          cat > wrap-zstd/build.rs <<'BUILDRS_EOF'
    fn main() {
        use std::env;
        use std::path::PathBuf;
        
        let mut include_paths = std::collections::HashSet::new();
        
        if let Ok(pkg_config_path) = std::env::var("PKG_CONFIG_PATH") {
            for path in pkg_config_path.split(':') {
                if path.contains("zstd") {
                     if let Some(base) = path.strip_suffix("/lib/pkgconfig") {
                        let include_path = format!("{}/include", base);
                        if std::path::Path::new(&include_path).exists() {
                            include_paths.insert(std::path::PathBuf::from(include_path));
                        }
                    }
                }
            }
        }
        
        let mut clang_args: Vec<String> = include_paths.iter().map(|path| format!("-I{}", path.display())).collect();
        if let Ok(extra_args) = std::env::var("BINDGEN_EXTRA_CLANG_ARGS") {
            for arg in extra_args.split_whitespace() { clang_args.push(arg.to_string()); }
        }
        
        println!("cargo:rustc-link-lib=zstd");
        
        let bindings = bindgen::Builder::default()
            .header("wrapper.h")
            .clang_args(&clang_args)
            .allowlist_function("ZSTD_.*")
            .generate()
            .expect("Unable to generate bindings");
        
        let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());
        bindings.write_to_file(out_path.join("bindings.rs")).expect("Couldn't write bindings!");
    }
    BUILDRS_EOF
        fi

        echo "=== Finished patching waypipe for Android ==="
  '';

  # Set runtime environment variables for Vulkan ICD discovery
  postInstall = ''
        # Create a wrapper script that sets VK_ICD_FILENAMES/VK_DRIVER_FILES for SwiftShader
        if [ -f "$out/bin/waypipe" ]; then
          mv "$out/bin/waypipe" "$out/bin/waypipe.real"
          cat > "$out/bin/waypipe" <<EOF
    #!/bin/sh
    # Set Vulkan ICD path for SwiftShader driver
    # Check for ICD JSON manifest in standard locations
    if [ -f "${swiftshader}/lib/vulkan/icd.d/vk_swiftshader_icd.json" ]; then
      export VK_DRIVER_FILES="${swiftshader}/lib/vulkan/icd.d/vk_swiftshader_icd.json"
      export VK_ICD_FILENAMES="${swiftshader}/lib/vulkan/icd.d/vk_swiftshader_icd.json"
    elif [ -f "${swiftshader}/share/vulkan/icd.d/vk_swiftshader_icd.json" ]; then
      export VK_DRIVER_FILES="${swiftshader}/share/vulkan/icd.d/vk_swiftshader_icd.json"
      export VK_ICD_FILENAMES="${swiftshader}/share/vulkan/icd.d/vk_swiftshader_icd.json"
    fi
    # Add SwiftShader library to library path
    export LD_LIBRARY_PATH="${swiftshader}/lib:''${LD_LIBRARY_PATH:-}"
    exec "$out/bin/waypipe.real" "$@"
    EOF
          chmod +x "$out/bin/waypipe"
        fi
  '';
}
