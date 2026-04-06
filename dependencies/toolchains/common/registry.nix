{
  libwayland = {
    android = ../../libs/libwayland/android.nix;
    ios = ../../libs/libwayland/ios.nix;
    macos = ../../libs/libwayland/macos.nix;
  };
  expat = {
    android = ../../libs/expat/android.nix;
    ios = ../../libs/expat/ios.nix;
    macos = ../../libs/expat/macos.nix;
  };
  libffi = {
    android = ../../libs/libffi/android.nix;
    ios = ../../libs/libffi/ios.nix;
    macos = ../../libs/libffi/macos.nix;
  };
  libxml2 = {
    android = ../../libs/libxml2/android.nix;
    ios = ../../libs/libxml2/ios.nix;
    macos = ../../libs/libxml2/macos.nix;
  };
  waypipe = {
    android = ../../libs/waypipe/android.nix;
    ios = ../../libs/waypipe/ios.nix;
    macos = ../../libs/waypipe/macos.nix;
  };
  pixman = {
    android = ../../libs/pixman/android.nix;
    ios = ../../libs/pixman/ios.nix;
    macos = null; # uses pkgs.pixman
  };
  xkbcommon = {
    android = ../../libs/xkbcommon/android.nix;
    ios = ../../libs/xkbcommon/ios.nix;
    macos = ../../libs/xkbcommon/macos.nix;
  };
  openssl = {
    android = ../../libs/openssl/android.nix;
    ios = ../../libs/openssl/ios.nix;
    macos = null; # uses pkgs.openssl
  };
  libssh2 = {
    android = ../../libs/libssh2/android.nix;
    ios = ../../libs/libssh2/ios.nix;
    macos = null;
  };
  mbedtls = {
    android = ../../libs/mbedtls/android.nix;
    ios = ../../libs/mbedtls/ios.nix;
    macos = null;
  };
  openssh = {
    android = ../../libs/openssh/android.nix;
    ios = ../../libs/openssh/ios.nix;
    macos = null;
  };
  sshpass = {
    android = ../../libs/sshpass/android.nix;
    ios = ../../libs/sshpass/ios.nix;
    macos = ../../libs/sshpass/macos.nix;
  };
  vulkan-cts = {
    android = ../../libs/vulkan-cts/android.nix;
    ios = ../../libs/vulkan-cts/ios.nix;
    macos = ../../libs/vulkan-cts/macos.nix;
  };
  gl-cts = {
    android = ../../libs/vulkan-cts/gl-cts-android.nix;
    ios = ../../libs/vulkan-cts/ios.nix; # with buildTargets = "glcts"
    macos = ../../libs/vulkan-cts/gl-cts-macos.nix;
  };
  epoll-shim = {
    android = null; # bionic has epoll
    ios = ../../libs/epoll-shim/ios.nix;
    macos = ../../libs/epoll-shim/macos.nix;
  };
  weston = {
    android = ../../clients/weston/android.nix;
    ios = ../../clients/weston/ios.nix;
    macos = ../../clients/weston/macos.nix;
  };
  weston-simple-shm = {
    android = null;
    ios = ../../libs/weston-simple-shm/ios.nix;
    macos = ../../libs/weston-simple-shm/macos.nix;
  };
}
