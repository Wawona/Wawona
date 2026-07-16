{
  lib,
  pkgs,
  buildModule,
  wawonaSrc,
  # Filtered source for the APK derivation `src` (cleanSourceWith). Defaults to
  # wawonaSrc for callers that don't pass it, but the flake passes the filtered
  # `srcFor pkgs` so working-tree churn (target/, .git/, editor dirs) does not
  # force a full APK rebuild. Path lookups (VERSION, subdirs) stay on wawonaSrc.
  srcFiltered ? wawonaSrc,
  wawonaVersion ? null,
  androidSDK ? null,
  androidUtils ? null,
  androidToolchain ? null,
  rustBackend ? null,
  glslang ? pkgs.glslang,
  jdk17 ? pkgs.jdk17,
  gradle ? pkgs.gradle,
  targetPkgs,
  androidToolchainNix,
  westonSimpleShmPatchedSrcNix,
  westonToytoolkitLdflagsNix,
  westonCompositorLdflagsNix,
  ilandGlAndroidLdflagsNix,
  androidConfigNix,
  westonAndroidSignalPolyfill ? null,
  releaseArtifact ? "debug",
  ...
}:

let
  common = import ./common.nix { inherit lib pkgs wawonaSrc; };
  androidConfig = import androidConfigNix {
    inherit lib androidSDK;
    system = pkgs.stdenv.buildPlatform.system;
  };
  provisionScript = if androidUtils != null then "${androidUtils.provisionAndroidScript}/bin/provision-android" else "";

  androidToolchainResolved = if androidToolchain != null then androidToolchain else import androidToolchainNix { inherit lib androidSDK; pkgs = targetPkgs; };
  
  projectVersion =
    if (wawonaVersion != null && wawonaVersion != "") then wawonaVersion
    else
      let v = lib.removeSuffix "\n" (lib.fileContents (wawonaSrc + "/VERSION"));
      in if v == "" then "0.0.1" else v;
  gradleSupport = pkgs.callPackage ../gradle-deps.nix {
    inherit wawonaSrc androidSDK androidConfigNix;
    inherit (pkgs) gradle jdk17;
  };

  westonSimpleShmSrc = pkgs.callPackage westonSimpleShmPatchedSrcNix {};
  libwaylandAndroid = buildModule.buildForAndroid "libwayland" { };
  opensshBin = buildModule.buildForAndroid "openssh" { };
  sshpassBin = buildModule.buildForAndroid "sshpass" { };
  # Real local shell for Android (fork/exec allowed); spawned by the PTY shim.
  zshAndroid = buildModule.buildForAndroid "zsh" { };
  footAndroid = buildModule.buildForAndroid "foot" { };
  fastfetchAndroid = buildModule.buildForAndroid "fastfetch" { };
  neovimAndroid = buildModule.buildForAndroid "neovim" { };
  waypipeAndroid = buildModule.buildForAndroid "waypipe" { };
  # niri (wwn-niri): nested scrollable-tiling compositor (Wayland client of
  # the Wawona compositor); ships as lib/libniri_bin.so (exec'd, waypipe pattern).
  niriAndroid = buildModule.buildForAndroid "niri" { };
  # fuzzel (wwn-niri): niri Mod+D launcher; PIE libfuzzel_bin.so (waypipe pattern).
  fuzzelAndroid = buildModule.buildForAndroid "fuzzel" { };
  # Freedesktop .desktop + hicolor icons for nested-niri fuzzel (issue #78).
  applicationsCatalog = pkgs.callPackage ../generators/applications-catalog.nix {
    inherit pkgs lib;
    wawonaSrc = wawonaSrc;
  };
  # anowaW app bridge: libanowaw.so + staged Kotlin/JNI shims (share/anowaw).
  anowawAndroid = buildModule.buildForAndroid "anowaw" { };
  mobileToytoolkitDeps = import ./mobile-toytoolkit-deps.nix {
    buildFn = buildModule.buildForAndroid;
  };
  westonAndroid = buildModule.buildForAndroid "weston" { enableGlClients = true; };
  westonSimpleShmAndroid = buildModule.buildForAndroid "weston-simple-shm" { };
  libintlAndroid = buildModule.buildForAndroid "libintl" { };
  westonToytoolkitLdflags = import westonToytoolkitLdflagsNix {
    inherit (pkgs) lib;
    deps = mobileToytoolkitDeps // {
      weston = westonAndroid;
      libintl = libintlAndroid;
    };
    forceLoadWeston = true;
    linkMode = "whole_archive";
  };
  westonCompositorAndroid = buildModule.buildForAndroid "weston-compositor" { };
  ilandAndroid = buildModule.buildForAndroid "iland" { };
  angleAndroid = buildModule.buildForAndroid "angle" { };
  kmscubeAndroid = buildModule.buildForAndroid "kmscube" { };
  westonCompositorLdflags = import westonCompositorLdflagsNix {
    inherit (pkgs) lib;
    deps = {
      weston-compositor = westonCompositorAndroid;
      libwayland = libwaylandAndroid;
      expat = buildModule.buildForAndroid "expat" { };
    };
    forceLoadCompositor = false;
    linkMode = "whole_archive";
  };
  ilandGlLdflags = import ilandGlAndroidLdflagsNix {
    inherit (pkgs) lib;
    deps = {
      iland = ilandAndroid;
      angle = angleAndroid;
      kmscube = kmscubeAndroid;
      "iland-gl-clients" = kmscubeAndroid;
    };
  };
  rustBackendPath = if rustBackend != null then toString rustBackend else "";
  androidQuadVert = ../../src/platform/android/rendering/shaders/android_quad.vert;
  androidQuadFrag = ../../src/platform/android/rendering/shaders/android_quad.frag;

  shellTools = import ./android-shell-tools.nix {
    inherit lib zshAndroid fastfetchAndroid neovimAndroid waypipeAndroid niriAndroid fuzzelAndroid footAndroid applicationsCatalog;
  };
  westonData = import ./android-weston-data.nix { inherit lib pkgs; };
  bundledClients = import ./android-bundled-clients.nix {
    androidCC = androidToolchainResolved.androidCC;
    inherit libwaylandAndroid westonAndroid footAndroid;
  };

  androidDeps = common.commonDeps ++ [
    "swiftshader"
    "pixman"
    "libwayland"
    "expat"
    "libffi"
    "libxml2"
    "xkbcommon"
    "openssl"
    "anowaw"
  ] ++ (lib.attrNames mobileToytoolkitDeps) ++ [
    "weston"
    "weston-compositor"
    "libintl"
    "iland"
    "angle"
    "kmscube"
    "iland-gl-clients"
  ];
  gradleTask =
    if releaseArtifact == "release-aab" then ":Wawona:bundleRelease"
    else if releaseArtifact == "release-apk" then ":Wawona:assembleRelease"
    else ":Wawona:assembleDebug";
  isReleaseBuild = releaseArtifact == "release-aab" || releaseArtifact == "release-apk";

  getDeps =
    platform: depNames:
    map (
      name:
      if name == "pixman" then
        if platform == "android" then
          buildModule.buildForAndroid "pixman" { }
        else
          pkgs.pixman
      else if name == "vulkan-headers" then
        pkgs.vulkan-headers
      else if name == "vulkan-loader" then
        pkgs.vulkan-loader
      else if name == "xkbcommon" then
        buildModule.buildForAndroid "xkbcommon" { }
      else if name == "openssl" then
        buildModule.buildForAndroid "openssl" { }
      else if name == "libssh2" then
        buildModule.buildForAndroid "libssh2" { }
      else
        buildModule.buildForAndroid name { }
    ) depNames;

  # Filter commonSources for Android: remove .m files and Apple-only headers
  androidCommonSources =
    lib.filter (
      f:
      !(lib.hasSuffix ".m" f)
      && f != "src/compositor_implementations/wayland_color_management.c"
      && f != "src/compositor_implementations/wayland_color_management.h"
      && f != "src/stubs/egl_buffer_handler.h"
      && f != "src/core/main.m"
    ) common.commonSources;

  # Android-specific sources (not filtered by pathExists since some are
  # generated at build time by postPatch, or are shared .c files that
  # filterSources may fail to resolve on Nix store paths)
  androidExtraSources = [
    "src/stubs/egl_buffer_handler.c"
    "src/platform/android/android_jni.c"
    "src/platform/android/input_android.c"
    "src/platform/android/rendering/renderer_android.c"
    "src/platform/android/rendering/renderer_android.h"
    "src/platform/android/iland_presenter_android.c"
    "src/platform/android/iland_presenter_android.h"
    "src/platform/macos/WWNSettings.c"
    "src/platform/macos/WWNSettings.h"
  ];

  androidSourcesFiltered = (common.filterSources androidCommonSources) ++ androidExtraSources;

  nixSdkPath = lib.makeBinPath (
    [
      androidSDK.platformTools
      androidSDK.cmdlineTools
      androidSDK.androidsdk
      pkgs.util-linux
      pkgs.jdk17
      pkgs.lldb
    ]
    ++ lib.optionals androidConfig.emulatorSupported [ androidSDK.emulator ]
  );

  nixSdkRoot = androidConfig.sdkRoot;

  runnerScript = import ./android-runner.nix {
    inherit pkgs nixSdkPath nixSdkRoot provisionScript;
    androidndkRoot = androidToolchainResolved.androidndkRoot;
    systemImageId = androidConfig.systemImageId;
  };


  # Impure Release Beta: read secrets at eval time (daemon builders do not
  # see the client's impureEnvVars). Paths/passwords stay out of flake.lock;
  # only `--impure` CI/local release builds set them.
  releaseKeystorePath = builtins.getEnv "ANDROID_KEYSTORE_PATH";
  releaseKeystoreBase64 = builtins.getEnv "ANDROID_KEYSTORE_BASE64";
  releaseKeystorePassword = builtins.getEnv "ANDROID_KEYSTORE_PASSWORD";
  releaseKeyAlias = builtins.getEnv "ANDROID_KEY_ALIAS";
  releaseKeyPassword = builtins.getEnv "ANDROID_KEY_PASSWORD";
  # Play requires monotonically increasing versionCode; bake at impure eval.
  releaseBuildNumber =
    let bn = builtins.getEnv "WAWONA_BUILD_NUMBER";
    in if bn == "" then "1" else bn;
  releaseVersionName =
    let v = builtins.getEnv "WAWONA_VERSION";
    in if v == "" then projectVersion else lib.removePrefix "v" v;

in
  pkgs.stdenv.mkDerivation (finalAttrs: rec {
    name = "wawona-android";
    version = projectVersion;
    src = srcFiltered;

    outputs = [ "out" "project" ];

    # Skip fixup phase - Android binaries can't execute on macOS
    dontFixup = true;
    dontUseGradleBuild = true;
    dontUseGradleCheck = true;
    __darwinAllowLocalNetworking = true;

    mitmCache = gradleSupport.mitmCache;
    gradleFlags = gradleSupport.gradleFlags;
    gradleUpdateTask = ":Wawona:assembleDebug";
    enableParallelUpdating = false;

    nativeBuildInputs = (with pkgs; [
      clang
      pkg-config
      jdk17 # Full JDK needed for Gradle
      gradle
      unzip
      zip
      file
      util-linux # Provides setsid for creating new process groups
      glslang # For compiling Vulkan shaders to SPIR-V
    ]) ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.patchelf ];

    buildInputs = (getDeps "android" androidDeps) ++ [
      pkgs.mesa
    ];

    # Files are now tracked directly in the repository, so we only need to
    # verify they exist before the build begins.
    prePatch = ''
      if [ ! -f src/platform/android/input_android.h ] || [ ! -f src/platform/android/input_android.c ]; then
        echo "ERROR: Missing input_android files in src/platform/android/"
        exit 1
      fi
      if [ ! -f android/app/src/main/java/com/aspauldingcode/wawona/ScreencopyHelper.kt ]; then
        echo "ERROR: Missing ScreencopyHelper.kt"
        exit 1
      fi
      if [ ! -f android/app/src/main/java/com/aspauldingcode/wawona/ModifierAccessoryBar.kt ]; then
        echo "ERROR: Missing ModifierAccessoryBar.kt"
        exit 1
      fi
    '';

    # Fix egl_buffer_handler for Android (create Android-compatible stubs)
    postPatch = ''
      if [ ! -f src/stubs/egl_buffer_handler.h ] || [ ! -f src/stubs/egl_buffer_handler.c ]; then
        echo "ERROR: Missing egl_buffer_handler stubs"
        exit 1
      fi
    '';

    preBuild = ''
      ndk_root="${androidToolchainResolved.androidndkRoot}"

      # Embed Vulkan shaders as C byte arrays for textured quad pipeline
      mkdir -p build/shaders
      if [ -f "${androidQuadVert}" ] && [ -f "${androidQuadFrag}" ]; then
        ${glslang}/bin/glslangValidator -V "${androidQuadVert}" -o build/shaders/quad.vert.spv
        ${glslang}/bin/glslangValidator -V "${androidQuadFrag}" -o build/shaders/quad.frag.spv
        echo '/* Auto-generated - do not edit */' > build/shaders/shader_spv.h
        echo '#pragma once' >> build/shaders/shader_spv.h
        echo '#include <stddef.h>' >> build/shaders/shader_spv.h
        echo '#include <stdint.h>' >> build/shaders/shader_spv.h
        echo 'static const unsigned char g_quad_vert_spv[] = {' >> build/shaders/shader_spv.h
        od -A n -t x1 -v build/shaders/quad.vert.spv | awk '{for(i=1;i<=NF;i++) printf " 0x%s,", $i}' | sed '$ s/,$//' >> build/shaders/shader_spv.h
        echo '};' >> build/shaders/shader_spv.h
        echo 'static const size_t g_quad_vert_spv_len = sizeof(g_quad_vert_spv);' >> build/shaders/shader_spv.h
        echo "" >> build/shaders/shader_spv.h
        echo 'static const unsigned char g_quad_frag_spv[] = {' >> build/shaders/shader_spv.h
        od -A n -t x1 -v build/shaders/quad.frag.spv | awk '{for(i=1;i<=NF;i++) printf " 0x%s,", $i}' | sed '$ s/,$//' >> build/shaders/shader_spv.h
        echo '};' >> build/shaders/shader_spv.h
        echo 'static const size_t g_quad_frag_spv_len = sizeof(g_quad_frag_spv);' >> build/shaders/shader_spv.h
        mkdir -p dependencies/generators/gradlegen/generated
        cp build/shaders/shader_spv.h dependencies/generators/gradlegen/generated/shader_spv.h
      else
        echo "ERROR: Shader sources not found at ${androidQuadVert} / ${androidQuadFrag}."
        exit 1
      fi

      # Setup Weston Simple SHM (CMakeLists.txt expects this)
      mkdir -p deps/weston-simple-shm
      cp -r ${westonSimpleShmSrc}/* deps/weston-simple-shm/
      chmod -R u+w deps/weston-simple-shm
      ${lib.optionalString (westonAndroidSignalPolyfill != null) ''
        cp ${westonAndroidSignalPolyfill} deps/weston-simple-shm/wwn-android-signal-polyfill.h
      ''}

      # Flatten the Android project into the repo root so the CMake relative
      # paths still point at the Nix-filtered source tree.
      echo "=== Phase 25: Preparing Android Project ==="
      ${gradleSupport.prepareProject}
      ${gradleSupport.prepareEnvironment}

      # Offline-only Maven: HTTPS through MITM still SocketExceptions in the
      # Darwin sandbox and disables repos mid-resolve (kotlin via mavenCentral
      # after AGP already resolved). Rewrite settings to file:// mirrors only.
      GOOGLE_MAVEN_FS="${mitmCache}/https/dl.google.com/dl/android/maven2"
      PORTAL_MAVEN_FS="${mitmCache}/https/plugins.gradle.org/m2"
      CENTRAL_MAVEN_FS="${mitmCache}/https/repo.maven.apache.org/maven2"
      if [ -d "$GOOGLE_MAVEN_FS" ] && [ -d "$CENTRAL_MAVEN_FS" ]; then
        cat > settings.gradle.kts <<EOF
pluginManagement {
    repositories {
        maven { url = uri("file://$GOOGLE_MAVEN_FS") }
        maven { url = uri("file://$PORTAL_MAVEN_FS") }
        maven { url = uri("file://$CENTRAL_MAVEN_FS") }
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        maven { url = uri("file://$GOOGLE_MAVEN_FS") }
        maven { url = uri("file://$CENTRAL_MAVEN_FS") }
    }
}

rootProject.name = "Wawona"
include(":Wawona")
project(":Wawona").projectDir = file("app")
EOF
        echo "Rewrote settings.gradle.kts to offline file:// maven mirrors"
      fi

      # Normalize daemon/jvmargs so --no-daemon stays in-process. A mismatched
      # jvmargs profile forks a single-use daemon that needs localhost TCP and
      # fails in the Nix sandbox (DaemonConnectionException / Operation not permitted).
      # Re-append matching jvmargs + daemon=false; heap must match GRADLE_OPTS below
      # (defaults are only 512m and OOM on assembleDebug).
      if [ -f gradle.properties ]; then
        grep -v -E '^org\.gradle\.(jvmargs|daemon)=' gradle.properties > gradle.properties.nix
        mv gradle.properties.nix gradle.properties
        echo 'org.gradle.daemon=false' >> gradle.properties
        # Include -Xms64m: the gradle launcher always sets it on the client JVM;
        # omit it from Wanted and Gradle forks a single-use daemon.
        echo 'org.gradle.jvmargs=-Xms64m -Xmx6144m -XX:MaxMetaspaceSize=1g -Dfile.encoding=UTF-8' >> gradle.properties
      fi

      # Bundle Nix-built shared libraries into the APK so the Android loader
      # can resolve libwawona.so runtime dependencies on-device.
      JNI_LIB_DIR="app/src/main/jniLibs/arm64-v8a"
      mkdir -p "$JNI_LIB_DIR"
      rm -f "$JNI_LIB_DIR"/*.so "$JNI_LIB_DIR"/*.so.*
      shopt -s nullglob
      for libdir in ${lib.concatMapStringsSep " " (d: "${d}/lib") (getDeps "android" androidDeps)}; do
        for so in "$libdir"/*.so "$libdir"/*.so.*; do
          base_so="$(basename "$so")"
          case "$base_so" in
            # These upstream prebuilts are not 16KB-page aligned.
            # Do not bundle them; Android provides Vulkan/SwiftShader runtime paths.
            libvk_swiftshader.so|libSPIRV-Tools-shared.so)
              continue
              ;;
          esac
          cp -L "$so" "$JNI_LIB_DIR/$(basename "$so")"
        done
      done
      shopt -u nullglob

      # ANGLE ships as libEGL.so / libGLESv2.so but with SONAMEs
      # libEGL_angle.so / libGLESv2_angle.so; libwawona.so links against the
      # SONAME, so stage SONAME-named copies too or the loader fails at launch.
      [ -f "$JNI_LIB_DIR/libEGL.so" ] && cp -f "$JNI_LIB_DIR/libEGL.so" "$JNI_LIB_DIR/libEGL_angle.so"
      [ -f "$JNI_LIB_DIR/libGLESv2.so" ] && cp -f "$JNI_LIB_DIR/libGLESv2.so" "$JNI_LIB_DIR/libGLESv2_angle.so"

      # Bundle SSH client helpers with stable names expected by android_jni.c.
      # We ship Dropbear dbclient as libssh_bin.so and sshpass as libsshpass_bin.so
      # in jniLibs so runtime path resolution can execute them directly.
      if [ -f "${opensshBin}/bin/ssh" ]; then
        cp -L "${opensshBin}/bin/ssh" "$JNI_LIB_DIR/libssh_bin.so"
        chmod +x "$JNI_LIB_DIR/libssh_bin.so"
      else
        echo "WARNING: Missing Android ssh binary at ${opensshBin}/bin/ssh"
      fi

      # Key management (wwn-ssh): dropbearkey ships as ssh-keygen (same
      # -t/-f/-y CLI for ed25519), plus scp and dropbearconvert.
      if [ -f "${opensshBin}/bin/ssh-keygen" ]; then
        cp -L "${opensshBin}/bin/ssh-keygen" "$JNI_LIB_DIR/libssh_keygen_bin.so"
        chmod +x "$JNI_LIB_DIR/libssh_keygen_bin.so"
      else
        echo "WARNING: Missing Android ssh-keygen binary at ${opensshBin}/bin/ssh-keygen"
      fi

      if [ -f "${opensshBin}/bin/scp" ]; then
        cp -L "${opensshBin}/bin/scp" "$JNI_LIB_DIR/libscp_bin.so"
        chmod +x "$JNI_LIB_DIR/libscp_bin.so"
      fi

      if [ -f "${opensshBin}/bin/dropbearconvert" ]; then
        cp -L "${opensshBin}/bin/dropbearconvert" "$JNI_LIB_DIR/libdropbearconvert_bin.so"
        chmod +x "$JNI_LIB_DIR/libdropbearconvert_bin.so"
      fi

      if [ -f "${sshpassBin}/bin/sshpass" ]; then
        cp -L "${sshpassBin}/bin/sshpass" "$JNI_LIB_DIR/libsshpass_bin.so"
        chmod +x "$JNI_LIB_DIR/libsshpass_bin.so"
      else
        echo "WARNING: Missing Android sshpass binary at ${sshpassBin}/bin/sshpass"
      fi

      # Bundled interactive shell tools (zsh, fastfetch, neovim); see
      # android-shell-tools.nix.
      ${shellTools.preBuildFragment}

      # xkeyboard-config: extracted from assets into wawona-rootfs by WawonaShellRootfs.
      mkdir -p app/src/main/assets/xkb
      cp -RL ${pkgs.xkeyboard_config}/share/X11/xkb/. app/src/main/assets/xkb/
      chmod -R u+w app/src/main/assets/xkb

      # DejaVu fonts for the in-process weston toytoolkit clients (cairo/
      # fontconfig text rendering). iOS embeds the same tree under share/fonts;
      # android_jni.c writes a fonts.conf pointing here at runtime.
      mkdir -p app/src/main/assets/fonts/truetype
      cp -L ${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans.ttf \
            ${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans-Bold.ttf \
            ${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSansMono.ttf \
            ${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSansMono-Bold.ttf \
            app/src/main/assets/fonts/truetype/
      chmod -R u+w app/src/main/assets/fonts

      # Weston toytoolkit PNGs (sign_close.png, icon_window.png, …) for CSD clients.
      ${westonData.preBuildFragment}

      # In-process Wayland clients (weston-simple-shm, foot); see
      # android-bundled-clients.nix.
      ${bundledClients.preBuildFragment}

      # anowaW app bridge: stage the Kotlin shims into the app sourceSet and the
      # JNI glue next to android_jni.c so CMake picks it up. libanowaw.so is
      # bundled into jniLibs by the androidDeps .so copy loop above.
      if [ -d "${anowawAndroid}/share/anowaw/kotlin" ]; then
        ANOWAW_KT_DIR="app/src/main/kotlin/com/aspauldingcode/wawona/anowaw"
        mkdir -p "$ANOWAW_KT_DIR"
        cp -L ${anowawAndroid}/share/anowaw/kotlin/*.kt "$ANOWAW_KT_DIR/"
        chmod -R u+w "$ANOWAW_KT_DIR"
      fi
      if [ -f "${anowawAndroid}/share/anowaw/jni/anowaw_jni.c" ]; then
        cp -L ${anowawAndroid}/share/anowaw/jni/anowaw_jni.c \
              src/platform/android/anowaw_jni.c
        chmod u+w src/platform/android/anowaw_jni.c
        # CMake compiles anowaw_jni.c with src/platform/android on the include
        # path; stage the ABI header beside it so parity/Gradle builds that
        # omit anowaw from DEP_INCLUDES still resolve #include "anowaw.h".
        if [ -f "${anowawAndroid}/include/anowaw.h" ]; then
          cp -L ${anowawAndroid}/include/anowaw.h \
                src/platform/android/anowaw.h
          chmod u+w src/platform/android/anowaw.h
        fi
      fi

      # Prefer the Rust shared library for Android linking; the static archive
      # can be malformed on some host toolchain combinations.
      RUST_BACKEND_LINK_LIB="${rustBackendPath}/lib/libwawona.a"
      if [ -f "${rustBackendPath}/lib/libwawona_core.so" ]; then
        cp -L "${rustBackendPath}/lib/libwawona_core.so" "$JNI_LIB_DIR/libwawona_core.so"
        RUST_BACKEND_LINK_LIB="${rustBackendPath}/lib/libwawona_core.so"
      fi

      # Inject Nix dependencies via Environment Variables for Gradle/CMake
      export ANDROID_NDK_ROOT="$ndk_root"
      export ANDROID_NDK_HOME="$ndk_root"
      export DEP_INCLUDES="${lib.concatMapStringsSep " " (d: "-I${d}/include") (getDeps "android" androidDeps)} -I${buildModule.buildForAndroid "pixman" { }}/include/pixman-1 -I${westonAndroid}/include/weston-gen"
      export DEP_LIBS="${lib.concatMapStringsSep " " (d: "-L${d}/lib") (getDeps "android" androidDeps)} ${lib.concatStringsSep " " (westonToytoolkitLdflags ++ westonCompositorLdflags ++ ilandGlLdflags)}"
      export RUST_BACKEND_LIB="$RUST_BACKEND_LINK_LIB"
    '';

    buildPhase = ''
      runHook preBuild

      if [ "${if isReleaseBuild then "1" else "0"}" = "1" ]; then
        export ANDROID_KEYSTORE_PASSWORD="${releaseKeystorePassword}"
        export ANDROID_KEY_ALIAS="${releaseKeyAlias}"
        export ANDROID_KEY_PASSWORD="${releaseKeyPassword}"
        export WAWONA_BUILD_NUMBER="${releaseBuildNumber}"
        export WAWONA_VERSION="${releaseVersionName}"
        # Prefer BASE64 baked at impure eval - host RUNNER_TEMP paths are
        # not readable inside the Nix build sandbox (Permission denied).
        if [ -n "${releaseKeystoreBase64}" ]; then
          KEYSTORE_PATH="$TMPDIR/wawona-upload.jks"
          printf '%s' "${releaseKeystoreBase64}" | base64 -d > "$KEYSTORE_PATH"
          export ANDROID_KEYSTORE_PATH="$KEYSTORE_PATH"
        elif [ -n "${releaseKeystorePath}" ] && [ -f "${releaseKeystorePath}" ]; then
          export ANDROID_KEYSTORE_PATH="${releaseKeystorePath}"
        fi
        : "''${ANDROID_KEYSTORE_PATH:?Set ANDROID_KEYSTORE_BASE64 (preferred) or a sandbox-readable ANDROID_KEYSTORE_PATH}"
        : "''${ANDROID_KEYSTORE_PASSWORD:?Missing ANDROID_KEYSTORE_PASSWORD}"
        : "''${ANDROID_KEY_ALIAS:?Missing ANDROID_KEY_ALIAS}"
        : "''${ANDROID_KEY_PASSWORD:?Missing ANDROID_KEY_PASSWORD}"
      fi

      # Build APK/AAB using Gradle.
      # Always use Nix gradle here: ./gradlew forceFetches the wrapper zip and
      # fails in the sandbox (SocketException: Operation not permitted).
      #
      # Keep --no-daemon truly in-process: client GRADLE_OPTS must match
      # org.gradle.jvmargs (above) plus mitm trustStore that gradle-setup-hook
      # injects via -D flags. Do not pass -Dorg.gradle.jvmargs on the CLI
      # (that forces a mismatch/fork → DaemonConnectionException in CI).
      GRADLE_OPTS="-Xms64m -Xmx6144m -XX:MaxMetaspaceSize=1g -Dfile.encoding=UTF-8"
      if [ -n "''${MITM_CACHE_KEYSTORE-}" ] && [ -n "''${MITM_CACHE_KS_PWD-}" ]; then
        GRADLE_OPTS="''${GRADLE_OPTS} -Djavax.net.ssl.trustStore=''${MITM_CACHE_KEYSTORE} -Djavax.net.ssl.trustStorePassword=''${MITM_CACHE_KS_PWD}"
      fi
      export GRADLE_OPTS
      gradle ${gradleTask} --no-build-cache --no-watch-fs --no-daemon --max-workers=1 \
        -Dorg.gradle.parallel=false \
        -Dorg.gradle.workers.max=1 \
        -Dorg.gradle.daemon=false \
        -Dkotlin.daemon.enabled=false \
        -Dkotlin.compiler.execution.strategy=in-process \
        -Dkotlin.incremental=false \
        --info --stacktrace || {
        echo "=== Gradle Build Failed! Accessing Diagnostic Reports ==="
        REPORT_PATH="app/build/outputs/logs/manifest-merger-debug-report.txt"
        if [ -f "$REPORT_PATH" ]; then
          echo "=== Manifest Merger Debug Report ==="
          cat "$REPORT_PATH"
        fi
        exit 1
      }
      
      # Verify bundled client .so files are packaged; see android-bundled-clients.nix.
      ${bundledClients.verifyApkFragment}

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin
      mkdir -p $out/lib

      ${if releaseArtifact == "release-aab" then ''
      AAB_PATH=""
      shopt -s nullglob globstar
      for candidate in \
        app/build/outputs/bundle/**/*.aab \
        android/app/build/outputs/bundle/**/*.aab \
        build/outputs/bundle/**/*.aab
      do
        if [ -f "$candidate" ]; then
          AAB_PATH="$candidate"
          break
        fi
      done
      shopt -u nullglob globstar
      if [ -z "$AAB_PATH" ]; then
        echo "Error: No AAB found!"
        exit 1
      fi
      mkdir -p $out/share/android
      cp "$AAB_PATH" $out/share/android/Wawona.aab
      ln -sf ../share/android/Wawona.aab $out/bin/Wawona.aab
      '' else ''
      # Gradle builds from the flattened root project in Nix, but some callers
      # still expect the nested `android/` layout. Probe both to find the APK.
      APK_PATH=""
      shopt -s nullglob globstar
      for candidate in \
        app/build/outputs/apk/**/*.apk \
        android/app/build/outputs/apk/**/*.apk \
        build/outputs/apk/**/*.apk
      do
        if [ -f "$candidate" ]; then
          APK_PATH="$candidate"
          break
        fi
      done
      shopt -u nullglob globstar

      if [ -z "$APK_PATH" ]; then
        echo "Error: No APK found!"
        exit 1
      fi
      cp "$APK_PATH" $out/bin/Wawona.apk
      
      # Copy the runner script
      cp ${runnerScript} $out/bin/wawona-android-run
      chmod +x $out/bin/wawona-android-run
      ''}

      # Expose full project for gradlegen (IDE support)
      mkdir -p $project
      cp -r . "$project/"
      
      runHook postInstall
    '';
  })
