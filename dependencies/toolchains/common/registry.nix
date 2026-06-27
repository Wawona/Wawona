let
  firstNonNull = values:
    let
      filtered = builtins.filter (value: value != null) values;
    in
    if filtered == [ ] then null else builtins.head filtered;

  withPlatformVariants = entry:
    let
      iosDevice = firstNonNull [ (entry.iosDevice or null) (entry.ios or null) ];
      iosSim = firstNonNull [ (entry.iosSim or null) iosDevice ];
      tvosDevice = firstNonNull [ (entry.tvosDevice or null) (entry.tvos or null) ];
      tvosSim = firstNonNull [ (entry.tvosSim or null) tvosDevice ];
      ipadosDevice = firstNonNull [ (entry.ipadosDevice or null) (entry.ipados or null) ];
      ipadosSim = firstNonNull [ (entry.ipadosSim or null) ipadosDevice ];
      watchosDevice = firstNonNull [ (entry.watchosDevice or null) (entry.watchos or null) ];
      watchosSim = firstNonNull [ (entry.watchosSim or null) watchosDevice ];
      visionosDevice = firstNonNull [ (entry.visionosDevice or null) (entry.visionos or null) ];
      visionosSim = firstNonNull [ (entry.visionosSim or null) visionosDevice ];
      androidDevice = firstNonNull [ (entry.androidDevice or null) (entry.android or null) ];
      androidEmulator = firstNonNull [ (entry.androidEmulator or null) androidDevice ];
      wearosDevice = firstNonNull [ (entry.wearosDevice or null) (entry.wearos or null) androidDevice ];
      wearosEmulator = firstNonNull [ (entry.wearosEmulator or null) wearosDevice ];
      linuxNative = firstNonNull [ (entry.linuxNative or null) (entry.linux or null) ];
    in
    entry
    // {
      # Explicit target attrs
      inherit iosDevice iosSim tvosDevice tvosSim ipadosDevice ipadosSim watchosDevice watchosSim visionosDevice visionosSim androidDevice androidEmulator wearosDevice wearosEmulator linuxNative;
      # Compatibility attrs
      ios = entry.ios or iosDevice;
      tvos = entry.tvos or tvosDevice;
      ipados = entry.ipados or ipadosDevice;
      watchos = entry.watchos or watchosDevice;
      visionos = entry.visionos or visionosDevice;
      android = entry.android or androidDevice;
      wearos = entry.wearos or wearosDevice;
      linux = entry.linux or linuxNative;
    };
in
{
  libwayland = withPlatformVariants {
    android = ../../libs/libwayland/android.nix;
    wearos = ../../libs/libwayland/wearos.nix;
    ios = ../../libs/libwayland/ios.nix;
    tvos = ../../libs/libwayland/tvos.nix;
    ipados = ../../libs/libwayland/ios.nix;
    visionos = ../../libs/libwayland/visionos.nix;
    watchos = ../../libs/libwayland/watchos.nix;
    macos = ../../libs/libwayland/macos.nix;
  };
  expat = withPlatformVariants {
    android = ../../libs/expat/android.nix;
    wearos = ../../libs/expat/wearos.nix;
    ios = ../../libs/expat/ios.nix;
    tvos = ../../libs/expat/tvos.nix;
    ipados = ../../libs/expat/ios.nix;
    visionos = ../../libs/expat/visionos.nix;
    watchos = ../../libs/expat/watchos.nix;
    macos = ../../libs/expat/macos.nix;
  };
  libffi = withPlatformVariants {
    android = ../../libs/libffi/android.nix;
    wearos = ../../libs/libffi/wearos.nix;
    ios = ../../libs/libffi/ios.nix;
    tvos = ../../libs/libffi/tvos.nix;
    ipados = ../../libs/libffi/ios.nix;
    visionos = ../../libs/libffi/visionos.nix;
    watchos = ../../libs/libffi/watchos.nix;
    macos = ../../libs/libffi/macos.nix;
  };
  libintl = withPlatformVariants {
    android = ../../libs/libintl/android.nix;
    ios = ../../libs/libintl/ios.nix;
    ipados = ../../libs/libintl/ios.nix;
    tvos = ../../libs/libintl/tvos.nix;
    visionos = ../../libs/libintl/visionos.nix;
    watchos = ../../libs/libintl/watchos.nix;
    macos = null;
  };
  libxml2 = withPlatformVariants {
    android = ../../libs/libxml2/android.nix;
    wearos = ../../libs/libxml2/wearos.nix;
    ios = ../../libs/libxml2/ios.nix;
    tvos = ../../libs/libxml2/tvos.nix;
    ipados = ../../libs/libxml2/ios.nix;
    visionos = ../../libs/libxml2/visionos.nix;
    watchos = ../../libs/libxml2/watchos.nix;
    macos = ../../libs/libxml2/macos.nix;
  };
  waypipe = withPlatformVariants {
    android = ../../libs/waypipe/android.nix;
    wearos = ../../libs/waypipe/wearos.nix;
    ios = ../../libs/waypipe/ios.nix;
    tvos = ../../libs/waypipe/tvos.nix;
    ipados = ../../libs/waypipe/ios.nix;
    visionos = ../../libs/waypipe/visionos.nix;
    watchos = ../../libs/waypipe/watchos.nix;
    macos = ../../libs/waypipe/macos.nix;
  };
  swiftshader = withPlatformVariants {
    android = ../../libs/swiftshader/android.nix;
    wearos = ../../libs/swiftshader/wearos.nix;
    ios = null;
    macos = null;
  };
  zlib = withPlatformVariants {
    android = null;
    ios = ../../libs/zlib/ios.nix;
    tvos = ../../libs/zlib/tvos.nix;
    ipados = ../../libs/zlib/ios.nix;
    visionos = ../../libs/zlib/visionos.nix;
    watchos = ../../libs/zlib/watchos.nix;
    macos = null;
  };
  zstd = withPlatformVariants {
    android = ../../libs/zstd/android.nix;
    wearos = ../../libs/zstd/wearos.nix;
    ios = ../../libs/zstd/ios.nix;
    tvos = ../../libs/zstd/tvos.nix;
    ipados = ../../libs/zstd/ios.nix;
    visionos = ../../libs/zstd/visionos.nix;
    watchos = ../../libs/zstd/watchos.nix;
    macos = ../../libs/zstd/macos.nix;
  };
  lz4 = withPlatformVariants {
    android = ../../libs/lz4/android.nix;
    wearos = ../../libs/lz4/wearos.nix;
    ios = ../../libs/lz4/ios.nix;
    tvos = ../../libs/lz4/tvos.nix;
    ipados = ../../libs/lz4/ios.nix;
    visionos = ../../libs/lz4/visionos.nix;
    watchos = ../../libs/lz4/watchos.nix;
    macos = ../../libs/lz4/macos.nix;
  };
  ffmpeg = withPlatformVariants {
    android = ../../libs/ffmpeg/android.nix;
    wearos = ../../libs/ffmpeg/wearos.nix;
    ios = ../../libs/ffmpeg/ios.nix;
    tvos = ../../libs/ffmpeg/tvos.nix;
    ipados = ../../libs/ffmpeg/ios.nix;
    visionos = ../../libs/ffmpeg/visionos.nix;
    watchos = ../../libs/ffmpeg/watchos.nix;
    macos = ../../libs/ffmpeg/macos.nix;
  };
  spirv-tools = withPlatformVariants {
    android = null;
    ios = ../../libs/spirv-tools/ios.nix;
    tvos = ../../libs/spirv-tools/tvos.nix;
    ipados = ../../libs/spirv-tools/ios.nix;
    visionos = ../../libs/spirv-tools/visionos.nix;
    watchos = ../../libs/spirv-tools/watchos.nix;
    macos = ../../libs/spirv-tools/macos.nix;
  };
  pixman = withPlatformVariants {
    android = ../../libs/pixman/android.nix;
    wearos = ../../libs/pixman/wearos.nix;
    ios = ../../libs/pixman/ios.nix;
    tvos = ../../libs/pixman/tvos.nix;
    ipados = ../../libs/pixman/ios.nix;
    visionos = ../../libs/pixman/visionos.nix;
    watchos = ../../libs/pixman/watchos.nix;
    macos = null; # uses pkgs.pixman
  };
  freetype = withPlatformVariants {
    android = ../../libs/freetype/android.nix;
    ios = ../../libs/freetype/ios.nix;
    ipados = ../../libs/freetype/ios.nix;
    tvos = ../../libs/freetype/ios.nix;
    visionos = ../../libs/freetype/ios.nix;
    watchos = ../../libs/freetype/ios.nix;
    macos = null; # uses pkgs.freetype
  };
  fribidi = withPlatformVariants {
    android = ../../libs/fribidi/android.nix;
    ios = ../../libs/fribidi/ios.nix;
    ipados = ../../libs/fribidi/ios.nix;
    tvos = ../../libs/fribidi/ios.nix;
    visionos = ../../libs/fribidi/ios.nix;
    watchos = ../../libs/fribidi/ios.nix;
    macos = null; # uses pkgs.fribidi
  };
  pcre2 = withPlatformVariants {
    android = ../../libs/pcre2/android.nix;
    ios = ../../libs/pcre2/ios.nix;
    ipados = ../../libs/pcre2/ios.nix;
    tvos = ../../libs/pcre2/ios.nix;
    visionos = ../../libs/pcre2/ios.nix;
    watchos = ../../libs/pcre2/ios.nix;
    macos = null; # uses pkgs.pcre2
  };
  fontconfig = withPlatformVariants {
    android = ../../libs/fontconfig/android.nix;
    ios = ../../libs/fontconfig/ios.nix;
    ipados = ../../libs/fontconfig/ios.nix;
    tvos = ../../libs/fontconfig/ios.nix;
    visionos = ../../libs/fontconfig/ios.nix;
    watchos = ../../libs/fontconfig/ios.nix;
    macos = null; # uses pkgs.fontconfig
  };
  glib = withPlatformVariants {
    android = ../../libs/glib/android.nix;
    ios = ../../libs/glib/ios.nix;
    ipados = ../../libs/glib/ios.nix;
    tvos = ../../libs/glib/ios.nix;
    visionos = ../../libs/glib/ios.nix;
    watchos = ../../libs/glib/ios.nix;
    macos = null; # uses pkgs.glib
  };
  harfbuzz = withPlatformVariants {
    android = ../../libs/harfbuzz/android.nix;
    ios = ../../libs/harfbuzz/ios.nix;
    ipados = ../../libs/harfbuzz/ios.nix;
    tvos = ../../libs/harfbuzz/ios.nix;
    visionos = ../../libs/harfbuzz/ios.nix;
    watchos = ../../libs/harfbuzz/ios.nix;
    macos = null; # uses pkgs.harfbuzz
  };
  cairo = withPlatformVariants {
    android = ../../libs/cairo/android.nix;
    ios = ../../libs/cairo/ios.nix;
    ipados = ../../libs/cairo/ios.nix;
    tvos = ../../libs/cairo/ios.nix;
    visionos = ../../libs/cairo/ios.nix;
    watchos = ../../libs/cairo/ios.nix;
    macos = null; # uses pkgs.cairo
  };
  pango = withPlatformVariants {
    android = ../../libs/pango/android.nix;
    ios = ../../libs/pango/ios.nix;
    ipados = ../../libs/pango/ios.nix;
    tvos = ../../libs/pango/ios.nix;
    visionos = ../../libs/pango/ios.nix;
    watchos = ../../libs/pango/ios.nix;
    macos = null; # uses pkgs.pango
  };
  libpng = withPlatformVariants {
    android = ../../libs/libpng/android.nix;
    ios = ../../libs/libpng/ios.nix;
    ipados = ../../libs/libpng/ios.nix;
    tvos = ../../libs/libpng/ios.nix;
    visionos = ../../libs/libpng/ios.nix;
    watchos = ../../libs/libpng/ios.nix;
    macos = null; # uses pkgs.libpng
  };
  xkbcommon = withPlatformVariants {
    android = ../../libs/xkbcommon/android.nix;
    wearos = ../../libs/xkbcommon/wearos.nix;
    ios = ../../libs/xkbcommon/ios.nix;
    tvos = ../../libs/xkbcommon/tvos.nix;
    ipados = ../../libs/xkbcommon/ios.nix;
    visionos = ../../libs/xkbcommon/visionos.nix;
    watchos = ../../libs/xkbcommon/watchos.nix;
    macos = ../../libs/xkbcommon/macos.nix;
  };
  openssl = withPlatformVariants {
    android = ../../libs/openssl/android.nix;
    wearos = ../../libs/openssl/wearos.nix;
    ios = ../../libs/openssl/ios.nix;
    tvos = ../../libs/openssl/tvos.nix;
    ipados = ../../libs/openssl/ios.nix;
    visionos = ../../libs/openssl/visionos.nix;
    watchos = ../../libs/openssl/watchos.nix;
    macos = null; # uses pkgs.openssl
  };
  libssh2 = withPlatformVariants {
    android = ../../libs/libssh2/android.nix;
    wearos = ../../libs/libssh2/wearos.nix;
    ios = ../../libs/libssh2/ios.nix;
    tvos = ../../libs/libssh2/tvos.nix;
    ipados = ../../libs/libssh2/ios.nix;
    visionos = ../../libs/libssh2/visionos.nix;
    watchos = ../../libs/libssh2/watchos.nix;
    macos = null;
  };
  mbedtls = withPlatformVariants {
    android = ../../libs/mbedtls/android.nix;
    wearos = ../../libs/mbedtls/wearos.nix;
    ios = ../../libs/mbedtls/ios.nix;
    tvos = ../../libs/mbedtls/tvos.nix;
    ipados = ../../libs/mbedtls/ios.nix;
    visionos = ../../libs/mbedtls/visionos.nix;
    watchos = ../../libs/mbedtls/watchos.nix;
    macos = null;
  };
  openssh = withPlatformVariants {
    android = ../../libs/openssh/android.nix;
    wearos = ../../libs/openssh/wearos.nix;
    ios = ../../libs/openssh/ios.nix;
    tvos = ../../libs/openssh/tvos.nix;
    ipados = ../../libs/openssh/ios.nix;
    visionos = ../../libs/openssh/visionos.nix;
    watchos = ../../libs/openssh/watchos.nix;
    macos = null;
  };
  sshpass = withPlatformVariants {
    android = ../../libs/sshpass/android.nix;
    wearos = ../../libs/sshpass/wearos.nix;
    ios = ../../libs/sshpass/ios.nix;
    tvos = ../../libs/sshpass/tvos.nix;
    ipados = ../../libs/sshpass/ios.nix;
    visionos = ../../libs/sshpass/visionos.nix;
    watchos = ../../libs/sshpass/watchos.nix;
    macos = ../../libs/sshpass/macos.nix;
  };
  epoll-shim = withPlatformVariants {
    android = null; # bionic has epoll
    ios = ../../libs/epoll-shim/ios.nix;
    tvos = ../../libs/epoll-shim/tvos.nix;
    ipados = ../../libs/epoll-shim/ios.nix;
    visionos = ../../libs/epoll-shim/visionos.nix;
    watchos = ../../libs/epoll-shim/watchos.nix;
    macos = ../../libs/epoll-shim/macos.nix;
  };
  weston = withPlatformVariants {
    android = ../../clients/weston/android.nix;
    wearos = ../../clients/weston/wearos.nix;
    ios = ../../clients/weston/ios.nix;
    tvos = ../../clients/weston/tvos.nix;
    ipados = ../../clients/weston/ios.nix;
    visionos = ../../clients/weston/visionos.nix;
    watchos = ../../clients/weston/watchos.nix;
    macos = ../../clients/weston/macos.nix;
  };
  weston-compositor = withPlatformVariants {
    android = ../../clients/weston/compositor-android.nix;
    ios = ../../clients/weston/compositor-ios.nix;
    tvos = ../../clients/weston/compositor-tvos.nix;
    ipados = ../../clients/weston/compositor-ios.nix;
    visionos = ../../clients/weston/compositor-visionos.nix;
    watchos = ../../clients/weston/compositor-watchos.nix;
    macos = null;
  };
  weston-compositor-drm = withPlatformVariants {
    android = null;
    ios = ../../clients/weston/compositor-ios-drm.nix;
    tvos = null;
    ipados = ../../clients/weston/compositor-ios-drm.nix;
    visionos = null;
    watchos = null;
    macos = null;
  };
  weston-simple-shm = withPlatformVariants {
    android = null;
    ios = ../../libs/weston-simple-shm/ios.nix;
    tvos = ../../libs/weston-simple-shm/tvos.nix;
    ipados = ../../libs/weston-simple-shm/ios.nix;
    visionos = ../../libs/weston-simple-shm/visionos.nix;
    watchos = ../../libs/weston-simple-shm/watchos.nix;
    macos = ../../libs/weston-simple-shm/macos.nix;
  };
  foot = withPlatformVariants {
    android = ../../clients/foot/android.nix;
    wearos = ../../clients/foot/wearos.nix;
    ios = ../../clients/foot/ios.nix;
    tvos = ../../clients/foot/tvos.nix;
    ipados = ../../clients/foot/ios.nix;
    visionos = ../../clients/foot/visionos.nix;
    watchos = ../../clients/foot/watchos.nix;
    macos = ../../clients/foot/macos.nix;
  };
  fcft = withPlatformVariants {
    android = null;
    ios = null;
    macos = ../../libs/fcft/macos.nix;
  };
  tllist = withPlatformVariants {
    android = null;
    ios = null;
    macos = ../../libs/tllist/macos.nix;
  };
  utf8proc = withPlatformVariants {
    android = null;
    ios = null;
    macos = ../../libs/utf8proc/macos.nix;
  };
  # ANGLE: OpenGL ES (GLES2/3) over Metal. macOS uses nixpkgs#angle (cached).
  # iOS/Android cross-compiled via GN (see dependencies/libs/angle/).
  angle = withPlatformVariants {
    android = ../../libs/angle/android.nix;
    ios = ../../libs/angle/ios.nix;
    ipados = ../../libs/angle/ios.nix;
    tvos = ../../libs/angle/ios.nix;
    visionos = ../../libs/angle/ios.nix;
    watchos = ../../libs/angle/ios.nix;
    macos = ../../libs/angle/macos.nix;
  };
  # iland: userland in-window Linux-graphics compat layer (GBM/EGL/DRM) for
  # Wayland/Weston GL clients. macOS + Apple mobile cross (Mode A).
  iland = withPlatformVariants {
    android = null;
    ios = ../../libs/iland/ios.nix;
    ipados = ../../libs/iland/ios.nix;
    tvos = ../../libs/iland/tvos.nix;
    visionos = ../../libs/iland/visionos.nix;
    watchos = ../../libs/iland/watchos.nix;
    macos = ../../libs/iland/macos.nix;
  };
  "wawona-pty" = withPlatformVariants {
    android = null;
    ios = ../../libs/wawona-pty/ios.nix;
    ipados = ../../libs/wawona-pty/ios.nix;
    tvos = ../../libs/wawona-pty/ios.nix;
    visionos = null;
    watchos = null;
    macos = null;
  };
  zsh = withPlatformVariants {
    android = null;
    ios = ../../libs/zsh/ios.nix;
    ipados = ../../libs/zsh/ios.nix;
    tvos = null;
    visionos = null;
    watchos = null;
    macos = null;
  };
  "wawona-rootfs" = withPlatformVariants {
    android = null;
    ios = ../../wawona/ios-rootfs.nix;
    ipados = ../../wawona/ios-rootfs.nix;
    tvos = null;
    visionos = null;
    watchos = null;
    macos = null;
  };
}
