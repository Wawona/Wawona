# Bundled interactive shell tools (zsh, fastfetch, neovim, waypipe, niri, fuzzel)
# for the Android APK.
#
# Extracted from android.nix to keep that file under its maintainability budget.
# `preBuildFragment` is spliced into the APK derivation's preBuild after
# JNI_LIB_DIR is populated; it copies each tool into jniLibs under the stable
# lib*_bin.so names android_jni.c resolves at runtime, plus the zsh share tree
# as an APK asset so $fpath resolves on-device.
{
  lib,
  zshAndroid ? null,
  fastfetchAndroid ? null,
  neovimAndroid ? null,
  waypipeAndroid ? null,
  niriAndroid ? null,
  fuzzelAndroid ? null,
  applicationsCatalog ? null,
}:
{
  preBuildFragment = ''
    ${lib.optionalString (zshAndroid != null) ''
    # Real zsh as libzsh_bin.so (jniLibs executables run from app data dir; the
    # PTY shim posix_spawn()s this) + the share tree (Functions/Completion) as
    # an APK asset so $fpath resolves on-device (laid out by android_jni.c).
    if [ -f "${zshAndroid}/bin/zsh" ]; then
      cp -L "${zshAndroid}/bin/zsh" "$JNI_LIB_DIR/libzsh_bin.so"
      chmod +x "$JNI_LIB_DIR/libzsh_bin.so"
      mkdir -p app/src/main/assets/zsh
      [ -d "${zshAndroid}/share/zsh" ] && cp -RL "${zshAndroid}/share/zsh/." app/src/main/assets/zsh/ && chmod -R u+w app/src/main/assets/zsh
    else
      echo "WARNING: Missing Android zsh binary at ${zshAndroid}/bin/zsh"
    fi
    ''}

    ${lib.optionalString (fastfetchAndroid != null) ''
    if [ -f "${fastfetchAndroid}/bin/fastfetch" ]; then
      cp -L "${fastfetchAndroid}/bin/fastfetch" "$JNI_LIB_DIR/libfastfetch_bin.so"
      chmod +x "$JNI_LIB_DIR/libfastfetch_bin.so"
    else
      echo "WARNING: Missing Android fastfetch binary at ${fastfetchAndroid}/bin/fastfetch"
    fi
    ''}

    ${lib.optionalString (neovimAndroid != null) ''
    if [ -f "${neovimAndroid}/bin/nvim" ]; then
      cp -L "${neovimAndroid}/bin/nvim" "$JNI_LIB_DIR/libnvim_bin.so"
      chmod +x "$JNI_LIB_DIR/libnvim_bin.so"
    else
      echo "WARNING: Missing Android neovim binary at ${neovimAndroid}/bin/nvim"
    fi
    ''}

    ${lib.optionalString (waypipeAndroid != null) ''
    # Use the real ELF binary (not the Vulkan wrapper script in $out/bin/waypipe).
    if [ -f "${waypipeAndroid}/bin/waypipe.real" ]; then
      cp -L "${waypipeAndroid}/bin/waypipe.real" "$JNI_LIB_DIR/libwaypipe_bin.so"
      chmod +x "$JNI_LIB_DIR/libwaypipe_bin.so"
    elif [ -f "${waypipeAndroid}/bin/waypipe" ]; then
      cp -L "${waypipeAndroid}/bin/waypipe" "$JNI_LIB_DIR/libwaypipe_bin.so"
      chmod +x "$JNI_LIB_DIR/libwaypipe_bin.so"
    else
      echo "WARNING: Missing Android waypipe binary at ${waypipeAndroid}/bin/waypipe"
    fi
    ''}

    ${lib.optionalString (niriAndroid != null) ''
    # niri (wwn-niri): nested scrollable-tiling compositor. Shipped as a
    # JNI-named PIE executable so the installer extracts it into the
    # exec-allowed nativeLibraryDir (waypipe pattern); android_jni.c execs it
    # with NIRI_BACKEND=nested against the Wawona Wayland socket.
    if [ -f "${niriAndroid}/lib/libniri_bin.so" ]; then
      cp -L "${niriAndroid}/lib/libniri_bin.so" "$JNI_LIB_DIR/libniri_bin.so"
      chmod +x "$JNI_LIB_DIR/libniri_bin.so"
    else
      echo "WARNING: Missing Android niri binary at ${niriAndroid}/lib/libniri_bin.so"
    fi
    ''}

    ${lib.optionalString (fuzzelAndroid != null) ''
    # fuzzel (wwn-niri): niri Mod+D launcher. Same waypipe/jniLibs PIE pattern
    # as niri — PATH symlink usr/bin/fuzzel → libfuzzel_bin.so (issue #78).
    if [ -f "${fuzzelAndroid}/lib/libfuzzel_bin.so" ]; then
      cp -L "${fuzzelAndroid}/lib/libfuzzel_bin.so" "$JNI_LIB_DIR/libfuzzel_bin.so"
      chmod +x "$JNI_LIB_DIR/libfuzzel_bin.so"
    elif [ -f "${fuzzelAndroid}/bin/fuzzel" ]; then
      cp -L "${fuzzelAndroid}/bin/fuzzel" "$JNI_LIB_DIR/libfuzzel_bin.so"
      chmod +x "$JNI_LIB_DIR/libfuzzel_bin.so"
    else
      echo "WARNING: Missing Android fuzzel binary at ${fuzzelAndroid}"
    fi
    ''}

    ${lib.optionalString (applicationsCatalog != null) ''
    # Freedesktop applications catalog for fuzzel (share/applications + hicolor).
    # Extracted into wawona-rootfs/usr/share by WawonaShellRootfs (issue #78).
    if [ -d "${applicationsCatalog}/share/applications" ]; then
      mkdir -p app/src/main/assets/applications app/src/main/assets/icons
      cp -R "${applicationsCatalog}/share/applications/." app/src/main/assets/applications/
      cp -R "${applicationsCatalog}/share/icons/hicolor" app/src/main/assets/icons/
      chmod -R u+w app/src/main/assets/applications app/src/main/assets/icons
      echo "Bundled fuzzel applications catalog into APK assets"
    fi
    ''}
  '';
}
