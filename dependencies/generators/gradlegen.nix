{ pkgs
, stdenv
, lib
, wawonaAndroidProject ? null
, wawonaSrc ? null
, wawonaVersion ? "v1.0"
, iconAssets ? "AUTO"
, androidSdkRoot ? null
, westonSimpleShmSrc ? null
, westonAndroidSignalPolyfill ? null
, nixDepIncludes ? ""
, nixDepLibs ? ""
, rustBackendLib ? ""
, rustBackendSharedLib ? ""
, runtimeLibDirs ? ""
, opensshBinaryPath ? ""
, sshpassBinaryPath ? ""
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

  # Single openable Gradle tree at ./Wawona-gradle-project (parallel to ./Wawona.xcodeproj).
  projectPath = if wawonaAndroidProject != null then toString wawonaAndroidProject else "";
  projectIconStorePath =
    if wawonaSrc != null && builtins.pathExists (wawonaSrc + "/src/resources/Wawona.icon/wayland.png") then
      toString (wawonaSrc + "/src/resources/Wawona.icon/wayland.png")
    else if wawonaSrc != null && builtins.pathExists (wawonaSrc + "/src/resources/Wawona.icon/Assets/wayland.png") then
      toString (wawonaSrc + "/src/resources/Wawona.icon/Assets/wayland.png")
    else
      "";
  projectDir = "Wawona-gradle-project";
  legacyOutDir = "dependencies/generators/gradlegen/output/Wawona-gradle-project";
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
  opensshBinaryPathEscaped = lib.escapeShellArg opensshBinaryPath;
  sshpassBinaryPathEscaped = lib.escapeShellArg sshpassBinaryPath;
  westonShmPath = if westonSimpleShmSrc != null then toString westonSimpleShmSrc else "";
  westonPolyfillPath =
    if westonAndroidSignalPolyfill != null then toString westonAndroidSignalPolyfill else "";
  generateScript = pkgs.writeShellScriptBin "gradlegen" ''
    set -euo pipefail
    find_repo_root() {
      local dir="$PWD"
      while [ "$dir" != "/" ]; do
        if [ -f "$dir/flake.nix" ]; then
          printf '%s\n' "$dir"
          return 0
        fi
        dir="$(dirname "$dir")"
      done
      return 1
    }
    REPO_ROOT="$(find_repo_root || true)"
    if [ -z "$REPO_ROOT" ]; then
      echo "Error: could not locate repo root (missing flake.nix in parent chain)." >&2
      exit 1
    fi
    cd "$REPO_ROOT"
    echo "Using repo root: $REPO_ROOT"
    OUT="$REPO_ROOT/${projectDir}"
    LEGACY_OUT="$REPO_ROOT/${legacyOutDir}"

    # Remove mistaken repo-root flatten from an older gradlegen layout.
    cleanup_repo_root_flatten() {
      if [ -d "$REPO_ROOT/android/app" ] && [ -d "$REPO_ROOT/app" ]; then
        rm -rf "$REPO_ROOT/app"
        echo "Removed stray repo-root app/ (use android/ sources + ${projectDir}/)"
      fi
      if [ -d "$REPO_ROOT/deps" ]; then
        rm -rf "$REPO_ROOT/deps"
        echo "Removed stray repo-root deps/"
      fi
      for stray in settings.gradle.kts build.gradle.kts gradle.properties local.properties; do
        if [ -f "$REPO_ROOT/$stray" ] && [ -f "$REPO_ROOT/android/$stray" ]; then
          rm -f "$REPO_ROOT/$stray"
          echo "Removed stray repo-root $stray"
        fi
      done
      if [ -d "$REPO_ROOT/.idea" ] && [ ! -d "$OUT/.idea" ]; then
        rm -rf "$REPO_ROOT/.idea"
        echo "Removed stray repo-root .idea/"
      fi
      for stray in gradlew gradlew.bat; do
        if [ -f "$REPO_ROOT/$stray" ] && [ -f "$REPO_ROOT/android/$stray" ]; then
          rm -f "$REPO_ROOT/$stray"
          echo "Removed stray repo-root $stray (wrapper lives under android/)"
        fi
      done
      if [ -d "$REPO_ROOT/gradle/wrapper" ] && [ -d "$REPO_ROOT/android/gradle/wrapper" ]; then
        rm -rf "$REPO_ROOT/gradle"
        echo "Removed stray repo-root gradle/ (wrapper lives under android/)"
      elif [ -d "$REPO_ROOT/gradle" ] && [ ! -d "$REPO_ROOT/gradle/wrapper" ]; then
        rm -rf "$REPO_ROOT/gradle"
        echo "Removed stray repo-root gradle/ (not the Android wrapper)"
      fi
    }
    cleanup_repo_root_flatten

    # Preserve Android Studio linkage (modules, run configs) across regen.
    # Do not preserve gradle.xml: stale gradleJvm (#GRADLE_LOCAL_JAVA_HOME, Nix
    # JAVA_HOME, etc.) breaks sync with "Invalid Gradle JDK configuration".
    IDE_STATE_DIR=""
    if [ -d "$OUT/.idea" ]; then
      IDE_STATE_DIR="$(mktemp -d)"
      mkdir -p "$IDE_STATE_DIR/.idea"
      for idea_file in runConfigurations.xml modules.xml deploymentTargetSelector.xml; do
        if [ -f "$OUT/.idea/$idea_file" ]; then
          cp "$OUT/.idea/$idea_file" "$IDE_STATE_DIR/.idea/$idea_file"
        fi
      done
      if [ -d "$OUT/.idea/runConfigurations" ]; then
        mkdir -p "$IDE_STATE_DIR/.idea/runConfigurations"
        cp -r "$OUT/.idea/runConfigurations/"* "$IDE_STATE_DIR/.idea/runConfigurations/" 2>/dev/null || true
      fi
      if [ -d "$OUT/.idea/modules" ]; then
        mkdir -p "$IDE_STATE_DIR/.idea/modules"
        cp -r "$OUT/.idea/modules/"* "$IDE_STATE_DIR/.idea/modules/" 2>/dev/null || true
      fi
    fi

    if [ -d "$LEGACY_OUT" ]; then
      chmod -R u+w "$LEGACY_OUT" 2>/dev/null || true
      rm -rf "$LEGACY_OUT"
      echo "Removed legacy nested output: ${legacyOutDir}"
    fi

    if [ -d "$OUT" ]; then
      chmod -R u+w "$OUT" 2>/dev/null || true
      rm -rf "$OUT"
    fi
    mkdir -p "$OUT"

    # Prefer the live checkout at runtime so uncommitted Kotlin/C++ edits sync into
    # Wawona-gradle-project (Darwin gradlegen bakes a git-filtered wawonaSrc at build time).
    ANDROID_SRC="$REPO_ROOT/android"
    if [ ! -f "$ANDROID_SRC/settings.gradle.kts" ]; then
      if [ -n "${toString wawonaSrc}" ] && [ -d "${toString wawonaSrc}/android" ]; then
        ANDROID_SRC="${toString wawonaSrc}/android"
      else
        ANDROID_SRC=""
      fi
    fi

    if [ -n "${projectPath}" ] && [ -d "${projectPath}" ]; then
      echo "Copying full Android project (backend + native libs) to $OUT/..."
      cp -r ${projectPath}/* "$OUT/"
      chmod -R u+w "$OUT" 2>/dev/null || true
      if [ -n "$ANDROID_SRC" ] && [ -d "$ANDROID_SRC/app/src/main/java" ]; then
        echo "Overlaying live Kotlin sources from $ANDROID_SRC/..."
        rm -rf "$OUT/app/src/main/java"
        cp -r "$ANDROID_SRC/app/src/main/java" "$OUT/app/src/main/"
        chmod -R u+w "$OUT/app/src/main/java" 2>/dev/null || true
      fi
      echo ""
      echo "Project ready at $OUT"
      echo "Open $OUT in Android Studio and select device/emulator."
    else
      if [ -n "$ANDROID_SRC" ]; then
        echo "Copying repository Android project to $OUT/..."
        cp -r "$ANDROID_SRC"/* "$OUT/"
        chmod -R u+w "$OUT" 2>/dev/null || true
        ${if androidIconAssets != null then ''
          if [ -d "${androidIconAssets}/res" ]; then
            mkdir -p "$OUT/app/src/main/res"
            cp -r ${androidIconAssets}/res/* "$OUT/app/src/main/res/"
            chmod -R u+w "$OUT/app/src/main/res" 2>/dev/null || true
            echo "Merged Wawona launcher icon assets"
          fi
        '' else ""}
        echo "Generated Android Studio project at $OUT from repository sources."
      else
        echo "ERROR: Could not locate android project sources under wawonaSrc."
        exit 1
      fi
    fi

    # CMakeLists.txt expects <project>/app, <project>/src, <project>/deps/weston-simple-shm.
    WAWONA_SRC="$REPO_ROOT"
    if [ ! -f "$OUT/src/stubs/egl_buffer_handler.c" ]; then
      if [ -f "$WAWONA_SRC/src/stubs/egl_buffer_handler.c" ]; then
        ln -sfn "$WAWONA_SRC/src" "$OUT/src"
        echo "Linked $OUT/src -> $WAWONA_SRC/src (native CMake)"
      else
        echo "Warning: Wawona src/ not found; CMake will not resolve C sources."
      fi
    fi
    # Ensure shader_spv.h is always freshly generated and syntactically valid.
    if [ -f "$WAWONA_SRC/scripts/embed-android-shaders.sh" ]; then
      TMP_SHADER_DIR="$(mktemp -d)"
      NIX_GLSLANG_BIN="${pkgs.glslang}/bin" bash "$WAWONA_SRC/scripts/embed-android-shaders.sh" "$WAWONA_SRC" "$TMP_SHADER_DIR"
      if [ -f "$TMP_SHADER_DIR/shader_spv.h" ]; then
        GENERATED_SHADER_DIR="$OUT/dependencies/generators/gradlegen/generated"
        mkdir -p "$GENERATED_SHADER_DIR"
        cp "$TMP_SHADER_DIR/shader_spv.h" "$GENERATED_SHADER_DIR/shader_spv.h"
        chmod u+w "$GENERATED_SHADER_DIR/shader_spv.h" 2>/dev/null || true
        echo "Regenerated $GENERATED_SHADER_DIR/shader_spv.h"
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
      WWN_SHM_POLY="${westonPolyfillPath}"
      if [ -f "$WWN_SHM_POLY" ]; then
        cp -f "$WWN_SHM_POLY" "$OUT/deps/weston-simple-shm/wwn-android-signal-polyfill.h"
      fi
      echo "Copied Weston simple-shm sources to $OUT/deps/weston-simple-shm"
    elif [ ! -f "$OUT/deps/weston-simple-shm/clients/simple-shm.c" ]; then
      echo "Warning: Weston simple-shm sources missing; native CMake will fail until deps are present."
    fi

    # Mirror Nix runtime libs into jniLibs for Android Studio builds.
    RUNTIME_LIB_DIRS=${runtimeLibDirsEscaped}
    RUST_BACKEND_SO=${rustBackendSharedLibEscaped}
    OPENSSH_BIN=${opensshBinaryPathEscaped}
    SSHPASS_BIN=${sshpassBinaryPathEscaped}
    if [ -n "$RUNTIME_LIB_DIRS" ] || [ -n "$RUST_BACKEND_SO" ] || [ -n "$OPENSSH_BIN" ] || [ -n "$SSHPASS_BIN" ]; then
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
      if [ -n "$OPENSSH_BIN" ] && [ -f "$OPENSSH_BIN" ]; then
        cp -L "$OPENSSH_BIN" "$JNI_LIB_DIR/libssh_bin.so"
        chmod +x "$JNI_LIB_DIR/libssh_bin.so"
      fi
      if [ -n "$SSHPASS_BIN" ] && [ -f "$SSHPASS_BIN" ]; then
        cp -L "$SSHPASS_BIN" "$JNI_LIB_DIR/libsshpass_bin.so"
        chmod +x "$JNI_LIB_DIR/libsshpass_bin.so"
      fi
      chmod -R u+w "$JNI_LIB_DIR" 2>/dev/null || true
      echo "Mirrored Nix runtime .so libs into $JNI_LIB_DIR"
    fi

    if [ -f "$REPO_ROOT/android/gradlew" ] && [ -d "$REPO_ROOT/android/gradle/wrapper" ]; then
      cp -f "$REPO_ROOT/android/gradlew" "$OUT/gradlew"
      chmod +x "$OUT/gradlew"
      if [ -f "$REPO_ROOT/android/gradlew.bat" ]; then
        cp -f "$REPO_ROOT/android/gradlew.bat" "$OUT/gradlew.bat"
      fi
      rm -rf "$OUT/gradle"
      mkdir -p "$OUT/gradle"
      cp -r "$REPO_ROOT/android/gradle/wrapper" "$OUT/gradle/wrapper"
      chmod -R u+w "$OUT/gradle" 2>/dev/null || true
      echo "Synced Gradle wrapper into $OUT/"
    fi

    # Android Studio JDK: pin Project + Gradle JVM to embedded JBR 21 ("21" in the IDE
    # JDK table). Avoid #USE_PROJECT_JDK without project-jdk-name and avoid
    # #GRADLE_LOCAL_JAVA_HOME (stale Nix JAVA_HOME breaks sync).
    mkdir -p "$OUT/.idea"
    if [ -f "$REPO_ROOT/android/studio/misc.xml" ]; then
      cp "$REPO_ROOT/android/studio/misc.xml" "$OUT/.idea/misc.xml"
    else
      cat > "$OUT/.idea/misc.xml" <<'IDEAEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="ExternalStorageConfigurationManager" enabled="true" />
  <component name="ProjectRootManager" version="2" languageLevel="JDK_17" default="true" project-jdk-name="21" project-jdk-type="JavaSDK" />
</project>
IDEAEOF
    fi
    if [ -f "$REPO_ROOT/android/studio/gradle.xml" ]; then
      cp "$REPO_ROOT/android/studio/gradle.xml" "$OUT/.idea/gradle.xml"
    else
      rm -f "$OUT/.idea/gradle.xml"
    fi

    # Seed default Android App run/debug config (module :Wawona -> Wawona.Wawona.main).
    if [ ! -d "$OUT/.idea/runConfigurations" ] || [ -z "$(ls -A "$OUT/.idea/runConfigurations" 2>/dev/null)" ]; then
      if [ -d "$REPO_ROOT/android/studio/runConfigurations" ]; then
        mkdir -p "$OUT/.idea/runConfigurations"
        cp -r "$REPO_ROOT/android/studio/runConfigurations/"* "$OUT/.idea/runConfigurations/"
        echo "Installed default Android Studio run configuration (Wawona)"
      fi
    fi

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

    # Copy Nix store headers/static libs into the project so Android Studio builds
    # survive store GC after weston/toolchain rebuilds (absolute /nix/store paths go stale).
    materialize_nix_native_deps() {
      local deps_root="$OUT/.nix-deps"
      local deps_lib="$deps_root/lib"
      local deps_inc="$deps_root/include"
      if [ -d "$deps_root" ]; then
        chmod -R u+w "$deps_root" 2>/dev/null || true
      fi
      rm -rf "$deps_root"
      mkdir -p "$deps_lib" "$deps_inc"

      copy_include_path() {
        local src="$1"
        [ -d "$src" ] || return 0
        local store_root="''${src#/nix/store/}"
        store_root="/nix/store/$(printf '%s' "$store_root" | cut -d/ -f1)"
        local rel="''${src#"$store_root"/}"
        local dest="$deps_inc/$(basename "$store_root")/$rel"
        if [ -d "$dest" ]; then
          return 0
        fi
        mkdir -p "$dest"
        cp -R "$src"/. "$dest/"
        chmod -R u+w "$dest"
      }

      local new_includes=""
      local inc path store_root rel
      for inc in $NIX_DEP_INCLUDES; do
        case "$inc" in
          -I/nix/store/*)
            path="''${inc#-I}"
            store_root="/nix/store/$(printf '%s' "$path" | sed 's|^/nix/store/||' | cut -d/ -f1)"
            rel="''${path#"$store_root"/}"
            copy_include_path "$path"
            new_includes="$new_includes -I$deps_inc/$(basename "$store_root")/$rel"
            ;;
          *)
            new_includes="$new_includes $inc"
            ;;
        esac
      done

      local new_libs=""
      local lib arg base
      for lib in $NIX_DEP_LIBS; do
        case "$lib" in
          -L/nix/store/*)
            path="''${lib#-L}"
            if [ -d "$path" ]; then
              for arg in "$path"/*.a "$path"/*.so; do
                [ -f "$arg" ] || continue
                base="$(basename "$arg")"
                cp -f "$arg" "$deps_lib/$base"
                chmod u+w "$deps_lib/$base"
              done
            fi
            ;;
          /nix/store/*.a)
            if [ -f "$lib" ]; then
              cp -f "$lib" "$deps_lib/$(basename "$lib")"
              chmod u+w "$deps_lib/$(basename "$lib")"
            fi
            ;;
          *)
            case "$lib" in
              /*/*.a)
                if [ -f "$lib" ]; then
                  cp -f "$lib" "$deps_lib/$(basename "$lib")"
                  chmod u+w "$deps_lib/$(basename "$lib")"
                fi
                ;;
            esac
            ;;
        esac
      done

      for lib in $NIX_DEP_LIBS; do
        case "$lib" in
          -L/nix/store/*) ;;
          /nix/store/*.a)
            new_libs="$new_libs $deps_lib/$(basename "$lib")"
            ;;
          /*/*.a)
            if [ -f "$lib" ]; then
              new_libs="$new_libs $deps_lib/$(basename "$lib")"
            else
              new_libs="$new_libs $lib"
            fi
            ;;
          *)
            new_libs="$new_libs $lib"
            ;;
        esac
      done
      if [ -n "$(ls -A "$deps_lib" 2>/dev/null)" ]; then
        new_libs="-L$deps_lib $new_libs"
      fi

      if [ -n "$RUST_BACKEND_LIB" ] && [ -f "$RUST_BACKEND_LIB" ]; then
        cp -f "$RUST_BACKEND_LIB" "$deps_lib/libwawona.a"
        chmod u+w "$deps_lib/libwawona.a"
        RUST_BACKEND_LIB="$deps_lib/libwawona.a"
      fi

      NIX_DEP_INCLUDES="$(printf '%s' "$new_includes" | sed 's/^ //')"
      NIX_DEP_LIBS="$(printf '%s' "$new_libs" | sed 's/^ //')"
      echo "Materialized Nix native deps under $deps_root"
    }
    if [ -n "$NIX_DEP_INCLUDES" ] || [ -n "$NIX_DEP_LIBS" ]; then
      materialize_nix_native_deps
    fi

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
      for idea_file in runConfigurations.xml modules.xml deploymentTargetSelector.xml; do
        if [ -f "$IDE_STATE_DIR/.idea/$idea_file" ]; then
          cp "$IDE_STATE_DIR/.idea/$idea_file" "$OUT/.idea/$idea_file"
          chmod u+w "$OUT/.idea/$idea_file" 2>/dev/null || true
        fi
      done
      if [ -d "$IDE_STATE_DIR/.idea/runConfigurations" ]; then
        mkdir -p "$OUT/.idea/runConfigurations"
        cp -r "$IDE_STATE_DIR/.idea/runConfigurations/"* "$OUT/.idea/runConfigurations/" 2>/dev/null || true
        chmod -R u+w "$OUT/.idea/runConfigurations" 2>/dev/null || true
      fi
      if [ -d "$IDE_STATE_DIR/.idea/modules" ]; then
        mkdir -p "$OUT/.idea/modules"
        cp -r "$IDE_STATE_DIR/.idea/modules/"* "$OUT/.idea/modules/" 2>/dev/null || true
        chmod -R u+w "$OUT/.idea/modules" 2>/dev/null || true
      fi
      rm -rf "$IDE_STATE_DIR"
      echo "Restored Android Studio local run/debug state"
    fi

    echo ""
    echo "Android Studio project ready at: $OUT"
    echo "Open that folder in Android Studio (File → Open), like Wawona.xcodeproj for Xcode."
  '';

in {
  inherit generateScript;
}
