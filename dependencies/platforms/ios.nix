{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  simulator ? false,
}:

let
  getBuildSystem = common.getBuildSystem;
  fetchSource = common.fetchSource;
  xcodeUtils = import ../utils/xcode-wrapper.nix { inherit lib pkgs; };
in

{
  buildForIOS =
    name: entry:
    if name == "libwayland" then
      (import ../libs/libwayland/ios.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          buildModule
          simulator
          ;
      }
    else if name == "expat" then
      (import ../libs/expat/ios.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          buildModule
          simulator
          ;
      }
    else if name == "libffi" then
      (import ../libs/libffi/ios.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          buildModule
          simulator
          ;
      }
    else if name == "libxml2" then
      (import ../libs/libxml2/ios.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          buildModule
          simulator
          ;
      }
    else if name == "waypipe" then
      (import ../libs/waypipe/ios.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          buildModule
          simulator
          ;
      }
    else if name == "zlib" then
      (import ../libs/zlib/ios.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          buildModule
          simulator
          ;
      }
    else if name == "zstd" then
      (import ../libs/zstd/ios.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          buildModule
          simulator
          ;
      }
    else if name == "lz4" then
      (import ../libs/lz4/ios.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          buildModule
          simulator
          ;
      }
    else if name == "ffmpeg" then
      (import ../libs/ffmpeg/ios.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          buildModule
          simulator
          ;
      }
    else if name == "spirv-llvm-translator" then
      (import ../libs/spirv-llvm-translator/ios.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          buildModule
          simulator
          ;
      }
    else if name == "spirv-tools" then
      (import ../libs/spirv-tools/ios.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          buildModule
          simulator
          ;
      }
    else if name == "libclc" then
      (import ../libs/libclc/ios.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          buildModule
          simulator
          ;
      }
    else if name == "xkbcommon" then
      (import ../libs/xkbcommon/ios.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          buildModule
          simulator
          ;
      }
    # Note: libssh2 removed - using OpenSSH binary instead
    else if name == "mbedtls" then
      (import ../libs/mbedtls/ios.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          buildModule
          simulator
          ;
      }
    else if name == "sshpass" then
      (import ../libs/sshpass/ios.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          buildModule
          simulator
          ;
      }
    else
      let
        src = if entry.source == "system" then null else fetchSource entry;
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
                            XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
                            if [ -n "$XCODE_APP" ]; then
                              export XCODE_APP
                              export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
                              export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
                              # Use iPhoneSimulator SDK for simulator builds
                              export SDKROOT="$DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
                            fi
                          fi
                          if [ -d expat ]; then
                            cd expat
                          fi
                          export NIX_CFLAGS_COMPILE=""
                          export NIX_CXXFLAGS_COMPILE=""
                          export MACOS_SDK_PATH="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
                          if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
                            IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
                            IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
                          else
                            IOS_CC="${buildPackages.clang}/bin/clang"
                            IOS_CXX="${buildPackages.clang}/bin/clang++"
                          fi
                          # Determine architecture for simulator
                          SIMULATOR_ARCH="arm64"
                          if [ "$(uname -m)" = "x86_64" ]; then
                            SIMULATOR_ARCH="x86_64"
                          fi
                          cat > ios-toolchain.cmake <<EOF
            set(CMAKE_SYSTEM_NAME iOS)
            set(CMAKE_OSX_ARCHITECTURES $SIMULATOR_ARCH)
            set(CMAKE_OSX_DEPLOYMENT_TARGET 26.0)
            set(CMAKE_C_COMPILER "$IOS_CC")
            set(CMAKE_CXX_COMPILER "$IOS_CXX")
            set(CMAKE_SYSROOT "$SDKROOT")
            set(CMAKE_OSX_SYSROOT "$SDKROOT")
            set(CMAKE_C_FLAGS "-m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0")
            set(CMAKE_CXX_FLAGS "-m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0")
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
                          if [ -z "''${XCODE_APP:-}" ]; then
                            XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
                            if [ -n "$XCODE_APP" ]; then
                              export XCODE_APP
                              export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
                              export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
                              # Use iPhoneSimulator SDK for simulator builds
                              export SDKROOT="$DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
                            fi
                          fi
                          export NIX_CFLAGS_COMPILE=""
                          export NIX_CXXFLAGS_COMPILE=""
                          export MACOS_SDK_PATH="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
                          if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
                            IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
                            IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
                          else
                            IOS_CC="${buildPackages.clang}/bin/clang"
                            IOS_CXX="${buildPackages.clang}/bin/clang++"
                          fi
                          # Determine architecture for simulator
                          SIMULATOR_ARCH="arm64"
                          if [ "$(uname -m)" = "x86_64" ]; then
                            SIMULATOR_ARCH="x86_64"
                          fi
                          cat > ios-cross-file.txt <<EOF
            [binaries]
            c = '$IOS_CC'
            cpp = '$IOS_CXX'
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
            c_args = ['-arch', '$SIMULATOR_ARCH', '-isysroot', '$SDKROOT', '-mios-simulator-version-min=26.0', '-fPIC']
            cpp_args = ['-arch', '$SIMULATOR_ARCH', '-isysroot', '$SDKROOT', '-mios-simulator-version-min=26.0', '-fPIC']
            c_link_args = ['-arch', '$SIMULATOR_ARCH', '-isysroot', '$SDKROOT', '-mios-simulator-version-min=26.0']
            cpp_link_args = ['-arch', '$SIMULATOR_ARCH', '-isysroot', '$SDKROOT', '-m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0']
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
            if [ -z "''${XCODE_APP:-}" ]; then
              XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
              if [ -n "$XCODE_APP" ]; then
                export XCODE_APP
                export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
                export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
                # Use iPhoneSimulator SDK for simulator builds
                export SDKROOT="$DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
              fi
            fi
            if [ ! -f ./configure ]; then
              autoreconf -fi || autogen.sh || true
            fi
            export NIX_CFLAGS_COMPILE=""
            export NIX_CXXFLAGS_COMPILE=""
            export MACOS_SDK_PATH="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
            if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
              IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
              IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
            else
              IOS_CC="${buildPackages.clang}/bin/clang"
              IOS_CXX="${buildPackages.clang}/bin/clang++"
            fi
            # Determine architecture for simulator
            SIMULATOR_ARCH="arm64"
            if [ "$(uname -m)" = "x86_64" ]; then
              SIMULATOR_ARCH="x86_64"
            fi
            export CC="$IOS_CC"
            export CXX="$IOS_CXX"
            export CFLAGS="-arch $SIMULATOR_ARCH -isysroot $SDKROOT -mios-simulator-version-min=26.0 -fPIC"
            export CXXFLAGS="-arch $SIMULATOR_ARCH -isysroot $SDKROOT -mios-simulator-version-min=26.0 -fPIC"
            export LDFLAGS="-arch $SIMULATOR_ARCH -isysroot $SDKROOT -m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0"

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
