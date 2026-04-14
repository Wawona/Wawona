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
      inherit iosDevice iosSim ipadosDevice ipadosSim watchosDevice watchosSim visionosDevice visionosSim androidDevice androidEmulator wearosDevice wearosEmulator linuxNative;
      # Compatibility attrs
      ios = entry.ios or iosDevice;
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
    ipados = ../../libs/libwayland/ipados.nix;
    watchos = ../../libs/libwayland/watchos.nix;
    macos = ../../libs/libwayland/macos.nix;
  };
  expat = withPlatformVariants {
    android = ../../libs/expat/android.nix;
    wearos = ../../libs/expat/wearos.nix;
    ios = ../../libs/expat/ios.nix;
    ipados = ../../libs/expat/ipados.nix;
    watchos = ../../libs/expat/watchos.nix;
    macos = ../../libs/expat/macos.nix;
  };
  libffi = withPlatformVariants {
    android = ../../libs/libffi/android.nix;
    wearos = ../../libs/libffi/wearos.nix;
    ios = ../../libs/libffi/ios.nix;
    ipados = ../../libs/libffi/ipados.nix;
    watchos = ../../libs/libffi/watchos.nix;
    macos = ../../libs/libffi/macos.nix;
  };
  libxml2 = withPlatformVariants {
    android = ../../libs/libxml2/android.nix;
    wearos = ../../libs/libxml2/wearos.nix;
    ios = ../../libs/libxml2/ios.nix;
    ipados = ../../libs/libxml2/ipados.nix;
    watchos = ../../libs/libxml2/watchos.nix;
    macos = ../../libs/libxml2/macos.nix;
  };
  waypipe = withPlatformVariants {
    android = ../../libs/waypipe/android.nix;
    wearos = ../../libs/waypipe/wearos.nix;
    ios = ../../libs/waypipe/ios.nix;
    ipados = ../../libs/waypipe/ipados.nix;
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
    ipados = ../../libs/zlib/ipados.nix;
    watchos = ../../libs/zlib/watchos.nix;
    macos = null;
  };
  zstd = withPlatformVariants {
    android = ../../libs/zstd/android.nix;
    wearos = ../../libs/zstd/wearos.nix;
    ios = ../../libs/zstd/ios.nix;
    ipados = ../../libs/zstd/ipados.nix;
    watchos = ../../libs/zstd/watchos.nix;
    macos = ../../libs/zstd/macos.nix;
  };
  lz4 = withPlatformVariants {
    android = ../../libs/lz4/android.nix;
    wearos = ../../libs/lz4/wearos.nix;
    ios = ../../libs/lz4/ios.nix;
    ipados = ../../libs/lz4/ipados.nix;
    watchos = ../../libs/lz4/watchos.nix;
    macos = ../../libs/lz4/macos.nix;
  };
  ffmpeg = withPlatformVariants {
    android = ../../libs/ffmpeg/android.nix;
    wearos = ../../libs/ffmpeg/wearos.nix;
    ios = ../../libs/ffmpeg/ios.nix;
    ipados = ../../libs/ffmpeg/ipados.nix;
    watchos = ../../libs/ffmpeg/watchos.nix;
    macos = ../../libs/ffmpeg/macos.nix;
  };
  spirv-tools = withPlatformVariants {
    android = null;
    ios = ../../libs/spirv-tools/ios.nix;
    ipados = ../../libs/spirv-tools/ipados.nix;
    watchos = ../../libs/spirv-tools/watchos.nix;
    macos = ../../libs/spirv-tools/macos.nix;
  };
  pixman = withPlatformVariants {
    android = ../../libs/pixman/android.nix;
    wearos = ../../libs/pixman/wearos.nix;
    ios = ../../libs/pixman/ios.nix;
    ipados = ../../libs/pixman/ipados.nix;
    watchos = ../../libs/pixman/watchos.nix;
    macos = null; # uses pkgs.pixman
  };
  xkbcommon = withPlatformVariants {
    android = ../../libs/xkbcommon/android.nix;
    wearos = ../../libs/xkbcommon/wearos.nix;
    ios = ../../libs/xkbcommon/ios.nix;
    ipados = ../../libs/xkbcommon/ipados.nix;
    watchos = ../../libs/xkbcommon/watchos.nix;
    macos = ../../libs/xkbcommon/macos.nix;
  };
  openssl = withPlatformVariants {
    android = ../../libs/openssl/android.nix;
    wearos = ../../libs/openssl/wearos.nix;
    ios = ../../libs/openssl/ios.nix;
    ipados = ../../libs/openssl/ipados.nix;
    watchos = ../../libs/openssl/watchos.nix;
    macos = null; # uses pkgs.openssl
  };
  libssh2 = withPlatformVariants {
    android = ../../libs/libssh2/android.nix;
    wearos = ../../libs/libssh2/wearos.nix;
    ios = ../../libs/libssh2/ios.nix;
    ipados = ../../libs/libssh2/ipados.nix;
    watchos = ../../libs/libssh2/watchos.nix;
    macos = null;
  };
  mbedtls = withPlatformVariants {
    android = ../../libs/mbedtls/android.nix;
    wearos = ../../libs/mbedtls/wearos.nix;
    ios = ../../libs/mbedtls/ios.nix;
    ipados = ../../libs/mbedtls/ipados.nix;
    watchos = ../../libs/mbedtls/watchos.nix;
    macos = null;
  };
  openssh = withPlatformVariants {
    android = ../../libs/openssh/android.nix;
    wearos = ../../libs/openssh/wearos.nix;
    ios = ../../libs/openssh/ios.nix;
    ipados = ../../libs/openssh/ipados.nix;
    watchos = ../../libs/openssh/watchos.nix;
    macos = null;
  };
  sshpass = withPlatformVariants {
    android = ../../libs/sshpass/android.nix;
    wearos = ../../libs/sshpass/wearos.nix;
    ios = ../../libs/sshpass/ios.nix;
    ipados = ../../libs/sshpass/ipados.nix;
    watchos = ../../libs/sshpass/watchos.nix;
    macos = ../../libs/sshpass/macos.nix;
  };
  epoll-shim = withPlatformVariants {
    android = null; # bionic has epoll
    ios = ../../libs/epoll-shim/ios.nix;
    ipados = ../../libs/epoll-shim/ipados.nix;
    watchos = ../../libs/epoll-shim/watchos.nix;
    macos = ../../libs/epoll-shim/macos.nix;
  };
  weston = withPlatformVariants {
    android = ../../clients/weston/android.nix;
    wearos = ../../clients/weston/wearos.nix;
    ios = ../../clients/weston/ios.nix;
    ipados = ../../clients/weston/ipados.nix;
    watchos = ../../clients/weston/watchos.nix;
    macos = ../../clients/weston/macos.nix;
  };
  weston-simple-shm = withPlatformVariants {
    android = null;
    ios = ../../libs/weston-simple-shm/ios.nix;
    ipados = ../../libs/weston-simple-shm/ipados.nix;
    watchos = ../../libs/weston-simple-shm/watchos.nix;
    macos = ../../libs/weston-simple-shm/macos.nix;
  };
  foot = withPlatformVariants {
    android = ../../clients/foot/android.nix;
    wearos = ../../clients/foot/wearos.nix;
    ios = ../../clients/foot/ios.nix;
    ipados = ../../clients/foot/ipados.nix;
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
}
