{ pkgs
, stdenv
, lib
, wawonaAndroidProject ? null
, wawonaSrc ? null
, wawonaVersion ? "v1.0"
, iconAssets ? "AUTO"
, androidSdkRoot ? null
, westonSimpleShmSrc ? null
, nixDepIncludes ? ""
, nixDepLibs ? ""
, rustBackendLib ? ""
, rustBackendSharedLib ? ""
, runtimeLibDirs ? ""
}:

let
  # Resolve icon assets:
  # 1. If explicitly null, use null (breaks recursion)
  # 2. If explicitly provided (not "AUTO"), use that derivation
  # 3. If "AUTO", try to resolve locally from wawonaSrc
  androidIconAssets = 
    if iconAssets == null then null
    else if iconAssets != "AUTO" then iconAssets
    else if wawonaSrc != null && builtins.pathExists ./android-icon-assets.nix then
      import ./android-icon-assets.nix { inherit pkgs lib wawonaSrc; }
    else
      null;

  # Script to generate Android Studio project in Wawona-gradle-project/ (gitignored).
  # When wawonaAndroidProject is available (pre-built Android project with jniLibs),
  # copies the full project. Otherwise falls back to gradle files + sources only.
  projectPath = if wawonaAndroidProject != null then toString wawonaAndroidProject else "";
  projectIconStorePath =
    if wawonaSrc != null && builtins.pathExists (wawonaSrc + "/src/resources/Wawona.icon/wayland.png") then
      toString (wawonaSrc + "/src/resources/Wawona.icon/wayland.png")
    else if wawonaSrc != null && builtins.pathExists (wawonaSrc + "/src/resources/Wawona.icon/Assets/wayland.png") then
      toString (wawonaSrc + "/src/resources/Wawona.icon/Assets/wayland.png")
    else
      "";
  outDir = "Wawona-gradle-project";
  sdkDirInit =
    if androidSdkRoot != null then
      "SDK_DIR=${lib.escapeShellArg (toString androidSdkRoot)}"
    else
      ''SDK_DIR=""'';
  nixDepIncludesEscaped = lib.escapeShellArg nixDepIncludes;
  nixDepLibsEscaped = lib.escapeShellArg nixDepLibs;
  rustBackendLibEscaped = lib.escapeShellArg rustBackendLib;
  rustBackendSharedLibEscaped = lib.escapeShellArg rustBackendSharedLib;
  runtimeLibDirsEscaped = lib.escapeShellArg runtimeLibDirs;
  westonShmPath = if westonSimpleShmSrc != null then toString westonSimpleShmSrc else "";
  generateScript = pkgs.writeShellScriptBin "gradlegen" ''
    set -e
    OUT="${outDir}"

    # Preserve only run configurations across regen.
    # Do not preserve workspace/module model files; stale model can hide run target.
    IDE_STATE_DIR=""
    if [ -f "$OUT/.idea/runConfigurations.xml" ] || [ -d "$OUT/.idea/runConfigurations" ]; then
      IDE_STATE_DIR="$(mktemp -d)"
      mkdir -p "$IDE_STATE_DIR/.idea"
      if [ -f "$OUT/.idea/runConfigurations.xml" ]; then
        cp "$OUT/.idea/runConfigurations.xml" "$IDE_STATE_DIR/.idea/runConfigurations.xml"
      fi
      if [ -d "$OUT/.idea/runConfigurations" ]; then
        mkdir -p "$IDE_STATE_DIR/.idea/runConfigurations"
        cp -r "$OUT/.idea/runConfigurations/"* "$IDE_STATE_DIR/.idea/runConfigurations/" 2>/dev/null || true
      fi
    fi

    # Clean previous run (handles read-only Nix store copies).
    if [ -d "$OUT" ]; then
      chmod -R u+w "$OUT" 2>/dev/null || true
      rm -rf "$OUT"
    fi
    mkdir -p "$OUT"

    if [ -n "${projectPath}" ] && [ -d "${projectPath}" ]; then
      echo "Copying full Android project (backend + native libs) to $OUT/..."
      cp -r ${projectPath}/* "$OUT/"
      chmod -R u+w "$OUT" 2>/dev/null || true
      echo ""
      echo "Project ready at $OUT/"
      echo "Open $OUT/ in Android Studio and select device/emulator."
    else
      if [ -n "${toString wawonaSrc}" ] && [ -d "${toString wawonaSrc}/android" ]; then
        echo "Copying repository Android project to $OUT/..."
        cp -r ${toString wawonaSrc}/android/* "$OUT/"
        chmod -R u+w "$OUT" 2>/dev/null || true
        ${if androidIconAssets != null then ''
          if [ -d "${androidIconAssets}/res" ]; then
            mkdir -p "$OUT/app/src/main/res"
            cp -r ${androidIconAssets}/res/* "$OUT/app/src/main/res/"
            chmod -R u+w "$OUT/app/src/main/res" 2>/dev/null || true
            echo "Merged Wawona launcher icon assets"
          fi
        '' else ""}
        echo "Generated Android Studio project in $OUT/ from repository sources."
      else
        echo "ERROR: Could not locate android project sources under wawonaSrc."
        exit 1
      fi
    fi

    # CMakeLists.txt expects repo-root layout (see dependencies/gradle-deps.nix prepareProject):
    # <root>/app, <root>/src, <root>/deps/weston-simple-shm — same as Nix after `cp -r android/* .`.
    if [ ! -f "$OUT/src/stubs/egl_buffer_handler.c" ]; then
      REPO_ROOT=""
      if [ -f "$PWD/src/stubs/egl_buffer_handler.c" ]; then
        REPO_ROOT="$(cd "$PWD" && pwd)"
      elif [ -n "${toString wawonaSrc}" ] && [ -f "${toString wawonaSrc}/src/stubs/egl_buffer_handler.c" ]; then
        REPO_ROOT="${toString wawonaSrc}"
      fi
      if [ -n "$REPO_ROOT" ]; then
        ln -sfn "$REPO_ROOT/src" "$OUT/src"
        echo "Linked $OUT/src -> $REPO_ROOT/src (native CMake)"
      else
        echo "Warning: Wawona src/ not found; CMake will not resolve C sources. Run from the repository root."
      fi
    fi
    # Ensure shader_spv.h is always freshly generated and syntactically valid.
    # Prevent stale/partial headers causing CMake compile errors in Studio.
    if [ -z "''${REPO_ROOT:-}" ]; then
      if [ -f "$PWD/src/stubs/egl_buffer_handler.c" ]; then
        REPO_ROOT="$(cd "$PWD" && pwd)"
      elif [ -n "${toString wawonaSrc}" ] && [ -f "${toString wawonaSrc}/src/stubs/egl_buffer_handler.c" ]; then
        REPO_ROOT="${toString wawonaSrc}"
      fi
    fi
    if [ -n "''${REPO_ROOT:-}" ] && [ -f "$REPO_ROOT/scripts/embed-android-shaders.sh" ]; then
      TMP_SHADER_DIR="$(mktemp -d)"
      NIX_GLSLANG_BIN="${pkgs.glslang}/bin" bash "$REPO_ROOT/scripts/embed-android-shaders.sh" "$REPO_ROOT" "$TMP_SHADER_DIR"
      if [ -f "$TMP_SHADER_DIR/shader_spv.h" ]; then
        cp "$TMP_SHADER_DIR/shader_spv.h" "$REPO_ROOT/src/platform/android/rendering/shader_spv.h"
        chmod u+w "$REPO_ROOT/src/platform/android/rendering/shader_spv.h" 2>/dev/null || true
        echo "Regenerated $REPO_ROOT/src/platform/android/rendering/shader_spv.h"
      fi
      rm -rf "$TMP_SHADER_DIR"
    else
      echo "Warning: shader embed script not found; keeping existing shader_spv.h"
    fi
    if [ ! -f "$OUT/deps/weston-simple-shm/clients/simple-shm.c" ] && [ -n "${westonShmPath}" ] && [ -d "${westonShmPath}" ]; then
      mkdir -p "$OUT/deps"
      rm -rf "$OUT/deps/weston-simple-shm"
      cp -r "${westonShmPath}" "$OUT/deps/weston-simple-shm"
      chmod -R u+w "$OUT/deps/weston-simple-shm" 2>/dev/null || true
      echo "Copied Weston simple-shm sources to $OUT/deps/weston-simple-shm"
    elif [ ! -f "$OUT/deps/weston-simple-shm/clients/simple-shm.c" ]; then
      echo "Warning: Weston simple-shm sources missing; native CMake will fail until deps are present."
    fi

    # Mirror Nix runtime libs into jniLibs for Android Studio builds.
    RUNTIME_LIB_DIRS=${runtimeLibDirsEscaped}
    RUST_BACKEND_SO=${rustBackendSharedLibEscaped}
    if [ -n "$RUNTIME_LIB_DIRS" ] || [ -n "$RUST_BACKEND_SO" ]; then
      JNI_LIB_DIR="$OUT/app/src/main/jniLibs/arm64-v8a"
      mkdir -p "$JNI_LIB_DIR"
      if [ -n "$RUNTIME_LIB_DIRS" ]; then
        OLD_IFS="$IFS"
        IFS=':'
        for libdir in $RUNTIME_LIB_DIRS; do
          if [ -d "$libdir" ]; then
            for so in "$libdir"/*.so "$libdir"/*.so.*; do
              if [ -f "$so" ]; then
                base_so="$(basename "$so")"
                case "$base_so" in
                  # Upstream prebuilts currently fail 16KB page-size checks.
                  # Keep APK clean for Android 15+/Play requirements.
                  libvk_swiftshader.so|libSPIRV-Tools-shared.so)
                    continue
                    ;;
                esac
                cp -L "$so" "$JNI_LIB_DIR/$base_so"
              fi
            done
          fi
        done
        IFS="$OLD_IFS"
      fi
      if [ -n "$RUST_BACKEND_SO" ] && [ -f "$RUST_BACKEND_SO" ]; then
        cp -L "$RUST_BACKEND_SO" "$JNI_LIB_DIR/libwawona_core.so"
      fi
      chmod -R u+w "$JNI_LIB_DIR" 2>/dev/null || true
      echo "Mirrored Nix runtime .so libs into $JNI_LIB_DIR"
    fi

    # Ensure generated project has up-to-date wrapper regardless of source layout.
    # Android Studio reads wrapper from opened project directory.
    if [ -f "$PWD/gradlew" ] && [ -d "$PWD/gradle/wrapper" ]; then
      cp "$PWD/gradlew" "$OUT/gradlew"
      chmod +x "$OUT/gradlew"
      if [ -f "$PWD/gradlew.bat" ]; then
        cp "$PWD/gradlew.bat" "$OUT/gradlew.bat"
      fi
      rm -rf "$OUT/gradle"
      mkdir -p "$OUT/gradle"
      cp -r "$PWD/gradle/wrapper" "$OUT/gradle/wrapper"
      chmod -R u+w "$OUT/gradle" 2>/dev/null || true
      echo "Synced Gradle wrapper into $OUT/ (uses repo wrapper version)"
    fi

    # Android Studio: Gradle defaults to #USE_PROJECT_JDK; without a project JDK the IDE
    # warns and falls back. Pin to the bundled JetBrains Runtime (major 21) while keeping
    # language level JDK_17 to match app/build.gradle.kts compileOptions.
    mkdir -p "$OUT/.idea"
    cat > "$OUT/.idea/misc.xml" <<'IDEAEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="ProjectRootManager" version="2" languageLevel="JDK_17" default="true" project-jdk-name="jbr-21" project-jdk-type="JavaSDK" />
</project>
IDEAEOF
    # Do not pre-generate .idea/gradle.xml.
    # Android Studio owns this file and may mark modules as non-Gradle when
    # linkedExternalProjectsSettings is incomplete, leading to "Unable to find
    # Gradle tasks to build: [:Wawona]".
    rm -f "$OUT/.idea/gradle.xml"

    # Gradle needs sdk.dir in local.properties; Android Studio often runs without ANDROID_HOME.
    ${sdkDirInit}
    if [ -z "$SDK_DIR" ] || [ ! -d "$SDK_DIR" ]; then
      if [ -n "''${ANDROID_HOME:-}" ] && [ -d "''${ANDROID_HOME}" ]; then
        SDK_DIR="''${ANDROID_HOME}"
      elif [ -n "''${ANDROID_SDK_ROOT:-}" ] && [ -d "''${ANDROID_SDK_ROOT}" ]; then
        SDK_DIR="''${ANDROID_SDK_ROOT}"
      fi
    fi
    if [ -n "$SDK_DIR" ] && [ -d "$SDK_DIR" ]; then
      {
        echo "## Generated by gradlegen; do not commit."
        printf 'sdk.dir=%s\n' "$SDK_DIR"
      } > "$OUT/local.properties"
      chmod u+w "$OUT/local.properties" 2>/dev/null || true
      echo "Wrote $OUT/local.properties (sdk.dir=$SDK_DIR)"

      # Also keep repo android/local.properties in sync so opening ./android
      # directly in Android Studio uses the same hermetic SDK automatically.
      if [ -d "$PWD/android" ] && [ -f "$PWD/android/settings.gradle.kts" ]; then
        {
          echo "## Generated by gradlegen; do not commit."
          printf 'sdk.dir=%s\n' "$SDK_DIR"
        } > "$PWD/android/local.properties"
        chmod u+w "$PWD/android/local.properties" 2>/dev/null || true
        echo "Wrote $PWD/android/local.properties (sdk.dir=$SDK_DIR)"
      fi

      ${if pkgs.stdenv.hostPlatform.isLinux then ''
        # NixOS: AGP-downloaded AAPT2 binary often fails dynamic loader.
        # Force AGP to use Nix SDK build-tools AAPT2 from sdk.dir.
        AAPT2_BIN="$SDK_DIR/build-tools/36.1.0/aapt2"
        if [ -f "$AAPT2_BIN" ]; then
          if [ -f "$OUT/gradle.properties" ]; then
            awk '!/^android\.aapt2FromMavenOverride=/' "$OUT/gradle.properties" > "$OUT/gradle.properties.tmp"
            mv "$OUT/gradle.properties.tmp" "$OUT/gradle.properties"
          fi
          printf '\n# Generated by gradlegen for NixOS Android Studio sync\nandroid.aapt2FromMavenOverride=%s\n' "$AAPT2_BIN" >> "$OUT/gradle.properties"
          chmod u+w "$OUT/gradle.properties" 2>/dev/null || true
          echo "Configured android.aapt2FromMavenOverride=$AAPT2_BIN"
        fi
      '' else ""}
    else
      echo "Warning: Android SDK not found. Re-run from a dev shell that provides the flake SDK, or set ANDROID_HOME / ANDROID_SDK_ROOT, or add sdk.dir to local.properties."
    fi

    # Keep Studio builds aligned with nix build memory budget so D8/R8/mergeDex
    # do not OOM on larger debug variants.
    if [ -f "$OUT/gradle.properties" ]; then
      awk '!/^org\.gradle\.daemon=|^org\.gradle\.parallel=|^org\.gradle\.workers\.max=|^org\.gradle\.jvmargs=|^kotlin\.daemon\.enabled=|^kotlin\.compiler\.execution\.strategy=|^kotlin\.incremental=/' "$OUT/gradle.properties" > "$OUT/gradle.properties.tmp"
      mv "$OUT/gradle.properties.tmp" "$OUT/gradle.properties"
    fi
    {
      echo ""
      echo "# Generated by gradlegen for Android Studio build stability"
      echo "org.gradle.daemon=false"
      echo "org.gradle.parallel=false"
      echo "org.gradle.workers.max=1"
      echo "org.gradle.jvmargs=-Xmx6144m -XX:MaxMetaspaceSize=1g -Dfile.encoding=UTF-8"
      echo "kotlin.daemon.enabled=false"
      echo "kotlin.compiler.execution.strategy=in-process"
      echo "kotlin.incremental=false"
    } >> "$OUT/gradle.properties"
    chmod u+w "$OUT/gradle.properties" 2>/dev/null || true
    echo "Configured Gradle/Kotlin memory and worker limits in $OUT/gradle.properties"

    # Persist Nix native args so Android Studio matches nix build inputs.
    NIX_DEP_INCLUDES=${nixDepIncludesEscaped}
    NIX_DEP_LIBS=${nixDepLibsEscaped}
    RUST_BACKEND_LIB=${rustBackendLibEscaped}
    RUST_BACKEND_SO=${rustBackendSharedLibEscaped}
    if [ -n "$RUST_BACKEND_SO" ] && [ -f "$RUST_BACKEND_SO" ]; then
      RUST_BACKEND_LINK="$RUST_BACKEND_SO"
    else
      RUST_BACKEND_LINK="$RUST_BACKEND_LIB"
    fi
    if [ -n "$NIX_DEP_INCLUDES" ] || [ -n "$NIX_DEP_LIBS" ] || [ -n "$RUST_BACKEND_LINK" ]; then
      if [ -f "$OUT/gradle.properties" ]; then
        awk '!/^wawona\.nixDepIncludes=|^wawona\.nixDepLibs=|^wawona\.rustBackendLib=/' "$OUT/gradle.properties" > "$OUT/gradle.properties.tmp"
        mv "$OUT/gradle.properties.tmp" "$OUT/gradle.properties"
      fi
      {
        echo ""
        echo "# Generated by gradlegen for Android Studio native parity"
        printf 'wawona.nixDepIncludes=%s\n' "$NIX_DEP_INCLUDES"
        printf 'wawona.nixDepLibs=%s\n' "$NIX_DEP_LIBS"
        printf 'wawona.rustBackendLib=%s\n' "$RUST_BACKEND_LINK"
      } >> "$OUT/gradle.properties"
      chmod u+w "$OUT/gradle.properties" 2>/dev/null || true
      echo "Configured Nix native args in $OUT/gradle.properties"
    fi

    # Set Android Studio project icon (.idea/icon*.png) from Wawona icon source.
    # Prefer workspace path to preserve the direct link the user requested.
    ICON_SRC=""
    if [ -f "$PWD/src/resources/Wawona.icon/wayland.png" ]; then
      ICON_SRC="$PWD/src/resources/Wawona.icon/wayland.png"
    elif [ -f "$PWD/src/resources/Wawona.icon/Assets/wayland.png" ]; then
      ICON_SRC="$PWD/src/resources/Wawona.icon/Assets/wayland.png"
    elif [ -n "${projectIconStorePath}" ] && [ -f "${projectIconStorePath}" ]; then
      ICON_SRC="${projectIconStorePath}"
    fi

    if [ -n "$ICON_SRC" ] && [ -f "$ICON_SRC" ]; then
      ln -snf "$ICON_SRC" "$OUT/.idea/icon.png"
      ln -snf "$ICON_SRC" "$OUT/.idea/icon_dark.png"
      chmod u+w "$OUT/.idea/icon.png" "$OUT/.idea/icon_dark.png" 2>/dev/null || true
      echo "Configured Android Studio project icon from $ICON_SRC"
    else
      echo "Warning: Android Studio project icon source not found; skipped .idea icon setup."
    fi

    # Restore user-local IDE state after fresh project generation.
    if [ -n "$IDE_STATE_DIR" ] && [ -d "$IDE_STATE_DIR/.idea" ]; then
      mkdir -p "$OUT/.idea"
      if [ -f "$IDE_STATE_DIR/.idea/runConfigurations.xml" ]; then
        cp "$IDE_STATE_DIR/.idea/runConfigurations.xml" "$OUT/.idea/runConfigurations.xml"
        chmod u+w "$OUT/.idea/runConfigurations.xml" 2>/dev/null || true
      fi
      if [ -d "$IDE_STATE_DIR/.idea/runConfigurations" ]; then
        mkdir -p "$OUT/.idea/runConfigurations"
        cp -r "$IDE_STATE_DIR/.idea/runConfigurations/"* "$OUT/.idea/runConfigurations/" 2>/dev/null || true
        chmod -R u+w "$OUT/.idea/runConfigurations" 2>/dev/null || true
      fi
      rm -rf "$IDE_STATE_DIR"
      echo "Restored Android Studio local run/debug state"
    fi
  '';

in {
  inherit generateScript;
}
