# Bundled interactive shell tools (zsh, fastfetch, neovim, waypipe) for the Android APK.
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
  '';
}
