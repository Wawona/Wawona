# The Android slice of .deps: what the committed Gradle project reads that is
# not in git. `nix run .#deps -- android` links .deps/android here.
#   wawona.properties   wawona.nixDepIncludes / nixDepLibs / rustBackendLib (CMake)
#   jniLibs/arm64-v8a   runtime .so files and the lib*_bin.so executables android_jni.c runs
#   assets/             zsh, xkb, fonts, Weston PNGs, Vulkan ICD, applications catalog
#   cpp/                shader_spv.h and weston-simple-shm sources (CMake)
{
  lib,
  pkgs,
  buildModule,
  wawonaSrc,
  rustBackend,
  androidCC,
  coreutilsAndroid ? null,
  westonSimpleShmPatchedSrcNix,
  westonAndroidSignalPolyfill ? null,
  westonToytoolkitLdflagsNix,
  westonCompositorLdflagsNix,
  ilandGlAndroidLdflagsNix,
}:
let
  dep = name: buildModule.buildForAndroid name { };
  libwayland = dep "libwayland";
  # GL clients: the toytoolkit link and the bundled clients compile against it.
  weston = buildModule.buildForAndroid "weston" { enableGlClients = true; };
  zsh = dep "zsh";
  fastfetch = dep "fastfetch";
  wasm = dep "wawona-wasm";
  openssh = dep "openssh";
  foot = (dep "foot").overrideAttrs (old: {
    # NDK lld treats Darwin-indexed static archives as warnings; Meson's
    # fatal warnings promote them to link errors.
    preConfigure = (old.preConfigure or "") + ''
      if [ -f android-cross-file.txt ]; then
        sed -i "s|c_link_args = \[|c_link_args = \['-Wl,--no-fatal-warnings', |" android-cross-file.txt || true
        sed -i "s|cpp_link_args = \[|cpp_link_args = \['-Wl,--no-fatal-warnings', |" android-cross-file.txt || true
      fi
    '';
  });
  toytoolkit = import ./mobile-toytoolkit-deps.nix { buildFn = buildModule.buildForAndroid; };
  catalog = pkgs.callPackage ../generators/applications-catalog.nix { inherit pkgs lib wawonaSrc; };
  linked = map dep ([ "waypipe" "zstd" "lz4" "swiftshader" "pixman" "libwayland" "expat" "libffi" "libxml2" "xkbcommon" "openssl" "anowaw" ]
    ++ lib.attrNames toytoolkit
    ++ [ "weston" "weston-compositor" "libintl" "iland" "angle" "kmscube" "gbm-es2-demo" "iland-gl-clients" ]);
  ldflags =
    import westonToytoolkitLdflagsNix {
      inherit lib;
      deps = toytoolkit // { inherit weston; libintl = dep "libintl"; };
      forceLoadWeston = true;
      linkMode = "whole_archive";
    }
    ++ import westonCompositorLdflagsNix {
      inherit lib;
      deps = { weston-compositor = dep "weston-compositor-gl"; inherit libwayland; expat = dep "expat"; };
      forceLoadCompositor = false;
      linkMode = "whole_archive";
    }
    ++ import ilandGlAndroidLdflagsNix {
      inherit lib;
      deps = {
        iland = dep "iland"; angle = dep "angle"; kmscube = dep "kmscube"; "iland-gl-clients" = dep "kmscube";
        "gbm-es2-demo" = dep "gbm-es2-demo"; "opengl-cube" = dep "opengl-cube"; vkcube = dep "vkcube";
      };
    };
  includes = map (d: "-I${d}/include") linked ++ [ "-I${dep "pixman"}/include/pixman-1" "-I${weston}/include/weston-gen" ];  libs = map (d: "-L${d}/lib") linked ++ ldflags ++ [
    "-L${wasm}/lib" "-Wl,-u,wawona_wasm_run" "-Wl,-u,wawona_wasm_can_run"
    "-Wl,-u,wawona_wasm_request_interrupt" "-Wl,-u,wawona_wasm_is_running" "-lwawona_wasm" "-Wl,--allow-multiple-definition"
  ];

  shellTools = import ./android-shell-tools.nix {
    inherit lib coreutilsAndroid;
    zshAndroid = zsh;
    fastfetchAndroid = fastfetch;
    phoonAndroid = dep "phoon";
    wasmAndroid = wasm;
    waypipeAndroid = dep "waypipe";
    niriAndroid = dep "niri";
    fuzzelAndroid = dep "fuzzel";
    footAndroid = foot;
    applicationsCatalog = catalog;
  };
  westonData = import ./android-weston-data.nix { inherit lib pkgs; };
  bundledClients = import ./android-bundled-clients.nix {
    inherit androidCC;
    libwaylandAndroid = libwayland;
    westonAndroid = weston;
    footAndroid = foot;
  };
in
pkgs.runCommand "wawona-deps-android" { nativeBuildInputs = [ pkgs.glslang ]; } ''
  JNI_LIB_DIR=$out/jniLibs/arm64-v8a
  mkdir -p $JNI_LIB_DIR $out/assets/vulkan/icd.d $out/assets/xkb $out/assets/fonts/truetype $out/cpp
  # The helper fragments write app/src/main/assets and deps/ relative to the project.
  mkdir -p work/app/src/main && cd work
  ln -s $out/assets app/src/main/assets
  ln -s $out/cpp deps

  for libdir in ${lib.concatMapStringsSep " " (d: "${d}/lib") linked}; do
    for so in "$libdir"/*.so "$libdir"/*.so.*; do
      [ -f "$so" ] || continue
      case "$(basename "$so")" in libSPIRV-Tools-shared.so) continue ;; esac
      cp -L "$so" $JNI_LIB_DIR/
    done
    if [ -f "$libdir/vulkan/icd.d/vk_swiftshader_icd.json" ]; then
      cp -L "$libdir/vulkan/icd.d/vk_swiftshader_icd.json" $out/assets/vulkan/icd.d/
    fi
  done
  # ANGLE's SONAMEs are libEGL_angle.so / libGLESv2_angle.so (libwawona's NEEDED).
  # Shipping the archive names too loads two ANGLE images.
  mv $JNI_LIB_DIR/libEGL.so $JNI_LIB_DIR/libEGL_angle.so
  mv $JNI_LIB_DIR/libGLESv2.so $JNI_LIB_DIR/libGLESv2_angle.so
  cp -L ${rustBackend}/lib/libwawona_core.so $JNI_LIB_DIR/

  # OpenSSH portable (wwn-ssh) under the jniLibs names android_jni.c execs.
  for t in ssh:ssh ssh-keygen:ssh_keygen scp:scp; do
    cp -L ${openssh}/bin/''${t%%:*} $JNI_LIB_DIR/lib''${t#*:}_bin.so
  done
  cp -L ${dep "sshpass"}/bin/sshpass $JNI_LIB_DIR/libsshpass_bin.so
  chmod -R u+w $out
  ${shellTools.preBuildFragment}
  cp -RL ${pkgs.callPackage ../libs/xkb-trimmed.nix { }}/share/X11/xkb/. $out/assets/xkb/
  cp -L ${pkgs.callPackage ../libs/fonts { }}/share/fonts/truetype/*.ttf $out/assets/fonts/truetype/
  ${westonData.preBuildFragment}

  cp -r ${pkgs.callPackage westonSimpleShmPatchedSrcNix { }} $out/cpp/weston-simple-shm
  chmod -R u+w $out/cpp
  ${lib.optionalString (westonAndroidSignalPolyfill != null) "cp ${westonAndroidSignalPolyfill} $out/cpp/weston-simple-shm/wwn-android-signal-polyfill.h"}
  ${bundledClients.preBuildFragment}
  NIX_GLSLANG_BIN=${pkgs.glslang}/bin bash ${../../scripts/embed-android-shaders.sh} ${lib.fileset.toSource {
    root = ../..;
    fileset = ../../src/platform/android/rendering/shaders;
  }} $TMPDIR/shaders
  cp $TMPDIR/shaders/shader_spv.h $out/cpp/

  chmod -R u+w $out

  cat > $out/wawona.properties <<'EOF'
  wawona.nixDepIncludes=${lib.concatStringsSep " " includes}
  wawona.nixDepLibs=${lib.concatStringsSep " " libs}
  wawona.rustBackendLib=${rustBackend}/lib/libwawona_core.so
  EOF
''
