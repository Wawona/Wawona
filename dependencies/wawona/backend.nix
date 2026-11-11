# The Wawona Rust backend for one slice, built by scripts/build-backend.sh.
#
# The derivation writes the script's environment to $out/env and runs the
# script with it. `nix run .#deps -- <slice>` links $out into .deps/<slice>,
# so `scripts/build-backend.sh <slice>` in a checkout builds with the same
# vendored crates, native libraries and features.
#
# slice is an Xcode PLATFORM_NAME (macosx, iphoneos, iphonesimulator,
# appletvos, ...), iphoneos-modeb, android or linux.
{ pkgs
, lib
, wawonaVersion
, workspaceSrc
, slice
, nativeDeps ? { }
, features
, minOS ? null
, release ? true
, rustToolchain ? pkgs.rustToolchain
  # Extra `export` lines (Android NDK compilers and linker).
, extraEnv ? { }
}:

let
  appleMobile = builtins.elem slice [
    "iphoneos" "iphoneos-modeb" "iphonesimulator" "xros" "xrsimulator"
    "appletvos" "appletvsimulator" "watchos" "watchsimulator"
  ];
  # tvOS and watchOS libc has no fork/exec*.
  noExec = builtins.elem slice [ "appletvos" "appletvsimulator" "watchos" "watchsimulator" ];
  appleTargets = ''any(target_os = "macos", target_os = "ios", target_os = "tvos", target_os = "visionos", target_os = "watchos")'';

  vendor =
    let raw = pkgs.rustPlatform.importCargoLock {
      lockFile = ../../Cargo.lock;
      allowBuiltinFetchGit = true;
    };
    in if !appleMobile then raw else pkgs.runCommand "wawona-vendor-apple" { } ''
      mkdir $out
      for d in ${raw}/*; do ln -s "$(readlink -f "$d")" "$out/''${d##*/}"; done
      patched() { rm "$out/$1"; cp -rL ${raw}/$1 "$out/$1"; chmod -R u+w "$out/$1"; cd "$out/$1"; }
      # libc omits sockaddr_ctl outside macOS and fork/exec* on tvOS/watchOS.
      for n in ${raw}/nix-0.*; do
        patched "''${n##*/}"
        patch -p1 < ${../patches/nix-0.30.1-watchos-tvos-no-fork-sysctl.patch}
      done
      patched wayland-backend-0.3.17
      find . -name '*.rs' -exec sed -i 's/target_os[[:space:]]*=[[:space:]]*"macos"/${appleTargets}/g' {} +
      cp -r ${raw}/.cargo $out/.cargo
    '';

  src = if !noExec then workspaceSrc else pkgs.runCommand "wawona-workspace-noexec" { } ''
    cp -r ${workspaceSrc} $out
    chmod -R u+w $out
    (cd $out/coreutils/src/uu/env && patch -p1 < ${../patches/uu_env-0.12.0-watchos-tvos-no-execvp.patch})
    # waypipe gates pipe2/ppoll on iOS; tvOS has the same APIs.
    find $out/waypipe/src -name '*.rs' -exec sed -i \
      's/target_os = "ios"/any(target_os = "ios", target_os = "tvos")/g' {} +
  '';

  deps = lib.filter (d: d != null) (lib.attrValues nativeDeps);
  dev = d: d.dev or d;
  uniffiBindgen = pkgs.callPackage ../generators/uniffi-bindgen.nix { };

  env = {
    WWN_FEATURES = lib.concatStringsSep " " features;
    WWN_PROFILE = if release then "release" else "dev";
    WWN_MIN_OS = toString minOS;
    WWN_VENDOR = vendor;
    WWN_PATH_CRATES = src;
    WWN_UNIFFI_BINDGEN = "${uniffiBindgen}/bin/uniffi-bindgen";
    WWN_LIB_DIRS = lib.concatMapStringsSep " " (d: "${lib.getLib d}/lib") deps;
    WWN_CFLAGS = lib.concatMapStringsSep " " (d: "-I${dev d}/include") (deps ++ [ pkgs.vulkan-headers ]);
    LIBCLANG_PATH = "${lib.getLib pkgs.llvmPackages.libclang}/lib";
    PKG_CONFIG_PATH = lib.concatMapStringsSep ":" (d: "${dev d}/lib/pkgconfig:${dev d}/share/pkgconfig") deps;
    PKG_CONFIG_ALLOW_CROSS = "1";
    PATH_PREPEND = lib.makeBinPath [ rustToolchain pkgs.pkg-config pkgs.rust-bindgen ];
  } // lib.optionalAttrs (nativeDeps ? openssl) {
    OPENSSL_DIR = dev nativeDeps.openssl;
    OPENSSL_LIB_DIR = "${lib.getLib nativeDeps.openssl}/lib";
    OPENSSL_INCLUDE_DIR = "${dev nativeDeps.openssl}/include";
    OPENSSL_STATIC = "1";
    OPENSSL_NO_VENDOR = "1";
  } // lib.optionalAttrs (nativeDeps ? zlib) {
    DEP_Z_INCLUDE = "${dev nativeDeps.zlib}/include";
  } // extraEnv;

  envFile = pkgs.writeText "wawona-backend-${slice}.env"
    (lib.concatStrings (lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}\n") env));
in
pkgs.stdenv.mkDerivation {
  pname = "wawona-backend-${slice}";
  version = wawonaVersion;
  inherit src;
  # Apple SDKs come from the installed Xcode through xcrun.
  __noChroot = appleMobile || slice == "macosx";
  dontConfigure = true;
  dontInstall = true;
  # Host archive tools corrupt cross static archives.
  dontFixup = true;
  buildPhase = ''
    export HOME=$TMPDIR WWN_SRC=$PWD WWN_OUT=$out
    . ${envFile}
    bash ${../../scripts/build-backend.sh} ${slice}
    cp ${envFile} $out/env
  '';
  passthru = { inherit vendor envFile; };
  meta.platforms = lib.platforms.all;
}
