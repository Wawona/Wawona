{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  simulator ? false,
  iosToolchain,
}:

let
  getBuildSystem = common.getBuildSystem;
  fetchSource = common.fetchSource;
  xcodeUtils = iosToolchain;
  setupIOSBuildEnv = xcodeUtils.mkIOSBuildEnv { inherit simulator; };
  deploymentFlag = if simulator then "-mios-simulator-version-min=${xcodeUtils.deploymentTarget}" else "-miphoneos-version-min=${xcodeUtils.deploymentTarget}";
in

{
  buildForIOS =
    name: entry:
    if name == "libwayland" then
      pkgs.callPackage ../libs/libwayland/ios.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else if name == "expat" then
      pkgs.callPackage ../libs/expat/ios.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else if name == "libffi" then
      pkgs.callPackage ../libs/libffi/ios.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else if name == "libxml2" then
      pkgs.callPackage ../libs/libxml2/ios.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else if name == "waypipe" then
      pkgs.callPackage ../libs/waypipe/ios.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else if name == "zlib" then
      pkgs.callPackage ../libs/zlib/ios.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else if name == "zstd" then
      pkgs.callPackage ../libs/zstd/ios.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else if name == "lz4" then
      pkgs.callPackage ../libs/lz4/ios.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else if name == "ffmpeg" then
      pkgs.callPackage ../libs/ffmpeg/ios.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else if name == "spirv-llvm-translator" then
      pkgs.callPackage ../libs/spirv-llvm-translator/ios.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else if name == "spirv-tools" then
      pkgs.callPackage ../libs/spirv-tools/ios.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else if name == "libclc" then
      pkgs.callPackage ../libs/libclc/ios.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else if name == "xkbcommon" then
      pkgs.callPackage ../libs/xkbcommon/ios.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    # Note: libssh2 removed - using OpenSSH binary instead
    else if name == "mbedtls" then
      pkgs.callPackage ../libs/mbedtls/ios.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else if name == "sshpass" then
      pkgs.callPackage ../libs/sshpass/ios.nix { inherit buildPackages common buildModule simulator iosToolchain; }
    else
      let
        src =
          if !(entry ? source) then null
          else if entry.source == "system" then null
          else fetchSource entry;
        buildSystem = getBuildSystem entry;
        buildFlags = entry.buildFlags.ios or [ ];
        patches = lib.filter (p: p != null && builtins.pathExists (toString p)) (entry.patches.ios or [ ]);
      in
      if buildSystem == "cmake" then
        pkgs.stdenv.mkDerivation {
          name = "${name}-ios";
          inherit src patches;
          nativeBuildInputs = with buildPackages; [
            cmake
            pkg-config
          ];
          buildInputs = [ ];
          preConfigure = ''
                          if [ -z "''${XCODE_APP:-}" ]; then
                          ${setupIOSBuildEnv}
                          if [ -d expat ]; then
                            cd expat
                          fi
                          export NIX_CFLAGS_COMPILE=""
                          export NIX_CXXFLAGS_COMPILE=""
                          export MACOS_SDK_PATH="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
                          cat > ios-toolchain.cmake <<EOF
            set(CMAKE_SYSTEM_NAME iOS)
            set(CMAKE_OSX_ARCHITECTURES $IOS_ARCH)
            set(CMAKE_OSX_DEPLOYMENT_TARGET ${xcodeUtils.deploymentTarget})
            set(CMAKE_C_COMPILER "$XCODE_CLANG")
            set(CMAKE_CXX_COMPILER "$XCODE_CLANGXX")
            set(CMAKE_SYSROOT "$SDKROOT")
            set(CMAKE_OSX_SYSROOT "$SDKROOT")
            set(CMAKE_C_FLAGS "${deploymentFlag}")
            set(CMAKE_CXX_FLAGS "${deploymentFlag}")
            EOF

            # Unset SDKROOT so it doesn't leak into host-side tool builds during cmake checks
            unset SDKROOT
          '';
          cmakeFlags = [
            "-DCMAKE_TOOLCHAIN_FILE=ios-toolchain.cmake"
          ]
          ++ buildFlags;
        }
      else if buildSystem == "meson" then
        pkgs.stdenv.mkDerivation {
          name = "${name}-ios";
          inherit src patches;
          nativeBuildInputs = with buildPackages; [
            meson
            ninja
            pkg-config
            (python3.withPackages (
              ps: with ps; [
                setuptools
                pip
                packaging
                mako
                pyyaml
              ]
            ))
            bison
            flex
          ];
          buildInputs = [ ];
          preConfigure = ''
                          ${setupIOSBuildEnv}
                          export NIX_CFLAGS_COMPILE=""
                          export NIX_CXXFLAGS_COMPILE=""
                          export MACOS_SDK_PATH="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
                          cat > ios-cross-file.txt <<EOF
            [binaries]
            c = '$XCODE_CLANG'
            cpp = '$XCODE_CLANGXX'
            c_for_build = '${buildPackages.clang}/bin/clang'
            cpp_for_build = '${buildPackages.clang}/bin/clang++'
            ar = 'ar'
            strip = 'strip'
            pkgconfig = '${buildPackages.pkg-config}/bin/pkg-config'

            [host_machine]
            system = 'darwin'
            cpu_family = 'aarch64'
            cpu = 'aarch64'
            endian = 'little'

            [built-in options]
            c_args = ['-arch', '$IOS_ARCH', '-isysroot', '$SDKROOT', '${deploymentFlag}', '-fPIC']
            cpp_args = ['-arch', '$IOS_ARCH', '-isysroot', '$SDKROOT', '${deploymentFlag}', '-fPIC']
            c_link_args = ['-arch', '$IOS_ARCH', '-isysroot', '$SDKROOT', '${deploymentFlag}']
            cpp_link_args = ['-arch', '$IOS_ARCH', '-isysroot', '$SDKROOT', '${deploymentFlag}']
            EOF

            # Unset SDKROOT so it doesn't leak into host-side tool builds during meson checks
            unset SDKROOT
          '';
          configurePhase = ''
            runHook preConfigure
            meson setup build \
              --prefix=$out \
              --libdir=$out/lib \
              --cross-file=ios-cross-file.txt \
              ${lib.concatMapStringsSep " \\\n  " (flag: flag) buildFlags}
            runHook postConfigure
          '';
          buildPhase = ''
            runHook preBuild
            meson compile -C build
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            meson install -C build
            runHook postInstall
          '';
        }
      else if buildSystem == "cargo" || buildSystem == "rust" then
        pkgs.rustPlatform.buildRustPackage {
          pname = name;
          version = entry.rev or entry.tag or "unknown";
          inherit src patches;
          cargoHash = if entry ? cargoHash && entry.cargoHash != null then entry.cargoHash else lib.fakeHash;
          cargoSha256 = entry.cargoSha256 or null;
          cargoLock = entry.cargoLock or null;
          nativeBuildInputs = with buildPackages; [ pkg-config ];
          buildInputs = [ ];
          CARGO_BUILD_TARGET = "aarch64-apple-ios";
        }
      else
        pkgs.stdenv.mkDerivation {
          name = "${name}-ios";
          inherit src patches;
          nativeBuildInputs = with buildPackages; [
            autoconf
            automake
            libtool
            pkg-config
          ];
          buildInputs = [ ];
          preConfigure = ''
            ${setupIOSBuildEnv}
            if [ ! -f ./configure ]; then
              autoreconf -fi || autogen.sh || true
            fi
            export NIX_CFLAGS_COMPILE=""
            export NIX_CXXFLAGS_COMPILE=""
            export MACOS_SDK_PATH="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
            export CC="$XCODE_CLANG"
            export CXX="$XCODE_CLANGXX"
            export CFLAGS="-arch $IOS_ARCH -isysroot $SDKROOT ${deploymentFlag} -fPIC"
            export CXXFLAGS="-arch $IOS_ARCH -isysroot $SDKROOT ${deploymentFlag} -fPIC"
            export LDFLAGS="-arch $IOS_ARCH -isysroot $SDKROOT ${deploymentFlag}"

            # Unset SDKROOT so it doesn't leak into host-side tool builds during configure
            unset SDKROOT
          '';
          configurePhase = ''
            runHook preConfigure
            ./configure --prefix=$out --host=arm-apple-darwin ${
              lib.concatMapStringsSep " " (flag: flag) buildFlags
            }
            runHook postConfigure
          '';
          configureFlags = buildFlags;
        };
}
