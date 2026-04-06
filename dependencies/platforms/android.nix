{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  androidSDK ? null,
  androidToolchain ? (import ../toolchains/android.nix { inherit lib pkgs androidSDK; }),
}:

let
  getBuildSystem = common.getBuildSystem;
  fetchSource = common.fetchSource;
in

{
  buildForAndroid =
    name: entry:
    if name == "libwayland" then
      (import ../libs/libwayland/android.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          ;
        inherit androidToolchain;
        buildModule = buildModule;
      }
    else if name == "expat" then
      (import ../libs/expat/android.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          ;
        inherit androidToolchain;
        buildModule = buildModule;
      }
    else if name == "libffi" then
      (import ../libs/libffi/android.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          ;
        inherit androidToolchain;
        buildModule = buildModule;
      }
    else if name == "libxml2" then
      (import ../libs/libxml2/android.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          ;
        inherit androidToolchain;
        buildModule = buildModule;
      }
    else if name == "waypipe" then
      (import ../libs/waypipe/android.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          ;
        inherit androidToolchain;
        buildModule = buildModule;
      }
    else if name == "swiftshader" then
      (import ../libs/swiftshader/android.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          ;
        inherit androidToolchain;
        buildModule = buildModule;
      }
    else if name == "zstd" then
      (import ../libs/zstd/android.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          ;
        inherit androidToolchain;
        buildModule = buildModule;
      }
    else if name == "lz4" then
      (import ../libs/lz4/android.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          ;
        inherit androidToolchain;
        buildModule = buildModule;
      }
    else if name == "ffmpeg" then
      (import ../libs/ffmpeg/android.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          ;
        inherit androidToolchain;
        buildModule = buildModule;
      }
    else if name == "xkbcommon" then
      (import ../libs/xkbcommon/android.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          ;
        inherit androidToolchain;
        buildModule = buildModule;
      }
    else if name == "openssl" then
      (import ../libs/openssl/android.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          ;
        inherit androidToolchain;
        buildModule = buildModule;
      }
    else if name == "libssh2" then
      (import ../libs/libssh2/android.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          ;
        inherit androidToolchain;
        buildModule = buildModule;
      }
    else if name == "mbedtls" then
      (import ../libs/mbedtls/android.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          ;
        inherit androidToolchain;
        buildModule = buildModule;
      }
    else if name == "openssh" then
      (import ../libs/openssh/android.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          ;
        inherit androidToolchain;
        buildModule = buildModule;
      }
    else if name == "sshpass" then
      (import ../libs/sshpass/android.nix) {
        inherit
          lib
          pkgs
          buildPackages
          common
          ;
        inherit androidToolchain;
        buildModule = buildModule;
      }
    else
      let
        src = fetchSource entry;
        buildSystem = getBuildSystem entry;
        buildFlags = entry.buildFlags.android or [ ];
        patches = lib.filter (p: p != null && builtins.pathExists (toString p)) (
          entry.patches.android or [ ]
        );
      in
      if buildSystem == "cmake" then
        pkgs.stdenv.mkDerivation {
          name = "${name}-android";
          inherit src patches;
          nativeBuildInputs = with buildPackages; [
            cmake
            pkg-config
          ];
          buildInputs = [ ];
          preConfigure = ''
            if [ -d expat ]; then
              cd expat
            fi
            export CC="${androidToolchain.androidCC}"
            export CXX="${androidToolchain.androidCXX}"
            export AR="${androidToolchain.androidAR}"
            export STRIP="${androidToolchain.androidSTRIP}"
            export RANLIB="${androidToolchain.androidRANLIB}"
            export CFLAGS="--target=${androidToolchain.androidTarget} --sysroot=${androidToolchain.androidNdkSysroot} -fPIC ${androidToolchain.androidNdkCflags}"
            export CXXFLAGS="--target=${androidToolchain.androidTarget} --sysroot=${androidToolchain.androidNdkSysroot} -fPIC ${androidToolchain.androidNdkCflags}"
            export LDFLAGS="--target=${androidToolchain.androidTarget} --sysroot=${androidToolchain.androidNdkSysroot} -L${androidToolchain.androidNdkAbiLibDir}"
            _ANDROID_LINK_FLAGS="--target=${androidToolchain.androidTarget} --sysroot=${androidToolchain.androidNdkSysroot} -L${androidToolchain.androidNdkAbiLibDir}"
            cmakeFlagsArray+=(
              "-DCMAKE_C_FLAGS:STRING=--target=${androidToolchain.androidTarget} --sysroot=${androidToolchain.androidNdkSysroot} -fPIC ${androidToolchain.androidNdkCflags}"
              "-DCMAKE_CXX_FLAGS:STRING=--target=${androidToolchain.androidTarget} --sysroot=${androidToolchain.androidNdkSysroot} -fPIC ${androidToolchain.androidNdkCflags}"
              "-DCMAKE_EXE_LINKER_FLAGS:STRING=$_ANDROID_LINK_FLAGS"
              "-DCMAKE_SHARED_LINKER_FLAGS:STRING=$_ANDROID_LINK_FLAGS"
              "-DCMAKE_MODULE_LINKER_FLAGS:STRING=$_ANDROID_LINK_FLAGS"
            )
          '';
          cmakeFlags = [
            "-DCMAKE_SYSTEM_NAME=Android"
            "-DCMAKE_ANDROID_ARCH_ABI=arm64-v8a"
            "-DCMAKE_ANDROID_NDK=${androidToolchain.androidndkRoot}"
            "-DCMAKE_C_COMPILER=${androidToolchain.androidCC}"
            "-DCMAKE_CXX_COMPILER=${androidToolchain.androidCXX}"
          ]
          ++ buildFlags;
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
          CARGO_BUILD_TARGET = "aarch64-linux-android";
          CC = androidToolchain.androidCC;
          CXX = androidToolchain.androidCXX;
        }
      else
        pkgs.stdenv.mkDerivation {
          name = "${name}-android";
          inherit src patches;
          nativeBuildInputs = with buildPackages; [
            autoconf
            automake
            libtool
            pkg-config
            texinfo
          ];
          buildInputs = [ ];
          preConfigure = ''
            if [ ! -f ./configure ]; then
              if [ -x ./autogen.sh ]; then
                autoreconf -fi || ./autogen.sh
              else
                autoreconf -fi
              fi
            fi
            [ -f ./configure ] || { echo "configure script is missing for ${name}"; exit 1; }
            export CC="${androidToolchain.androidCC} --target=${androidToolchain.androidTarget}"
            export CXX="${androidToolchain.androidCXX} --target=${androidToolchain.androidTarget}"
            export AR="${androidToolchain.androidAR}"
            export STRIP="${androidToolchain.androidSTRIP}"
            export RANLIB="${androidToolchain.androidRANLIB}"
            export CFLAGS="-fPIC --sysroot=${androidToolchain.androidNdkSysroot} ${androidToolchain.androidNdkCflags}"
            export CXXFLAGS="-fPIC --sysroot=${androidToolchain.androidNdkSysroot} ${androidToolchain.androidNdkCflags}"
            export LDFLAGS="--target=${androidToolchain.androidTarget} --sysroot=${androidToolchain.androidNdkSysroot} -L${androidToolchain.androidNdkAbiLibDir}"
          '';
          configurePhase = ''
            runHook preConfigure
            ./configure --prefix=/usr --host=${androidToolchain.androidTarget} ${
              lib.concatMapStringsSep " " (flag: flag) buildFlags
            }
            runHook postConfigure
          '';
          buildPhase = ''
            runHook preBuild
            make -j$NIX_BUILD_CORES
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            make install DESTDIR=$out || make install-data-am install-exec-am DESTDIR=$out
            if [ -d "$out/usr" ]; then
              if [ -d "$out/usr/lib" ]; then
                mkdir -p $out/lib
                cp -r $out/usr/lib/. $out/lib/
              fi
              if [ -d "$out/usr/lib/pkgconfig" ]; then
                mkdir -p $out/lib/pkgconfig
                cp -r $out/usr/lib/pkgconfig/. $out/lib/pkgconfig/
              fi
              if [ -d "$out/usr/include" ]; then
                mkdir -p $out/include
                cp -r $out/usr/include/. $out/include/
              fi
            fi
            runHook postInstall
          '';
          CC = "${androidToolchain.androidCC} --target=${androidToolchain.androidTarget}";
          CXX = "${androidToolchain.androidCXX} --target=${androidToolchain.androidTarget}";
          NIX_CFLAGS_COMPILE = "-fPIC";
          NIX_CXXFLAGS_COMPILE = "-fPIC";
          __impureHostDeps = [ "/bin/sh" ];
        };
}
