# Per-product Settings → Dependencies inventory.
#
# Settings must list packages actually linked into THAT product. Never paste
# another platform's list (no OpenSSH on Apple mobile, no MoltenVK on Android).
# Adding a flake/package to a product updates that product's inventory in the
# same change. Canonical rule: docs/agent-rules/wawona-settings-dependencies.md
#
# JSON snapshots live under src/resources/settings-deps/<target>/ and
# android/app/src/main/assets/, src/linux/ui/settings_dependencies.json.
# Keep those files in lockstep with this attrset.

rec {
  # Versions must match xcodegen.nix depVersions / the linked store path.
  versions = {
    wayland = "1.23.0";
    xkbcommon = "1.7.0";
    lz4 = "1.10.0";
    zstd = "1.5.7";
    libffi = "3.5.2";
    sshpass = "1.10";
    waypipe = "0.11.0";
    libssh2 = "1.11.1";
    openssl = "3.4.1";
    pixman = "0.44.2";
    angle = "chromium";
    moltenvk = "1.3";
    swiftshader = "2024";
    weston = "14";
    niri = "25";
    zsh = "5.9";
    foot = "1.21";
    fuzzel = "1.11";
    openssh = "9.9p2";
  };

  # Shared substrate (L0) that every Apple/Android/Linux client actually links.
  substrate = versions: [
    { name = "libwayland"; version = versions.wayland; role = "Wayland protocol library"; }
    { name = "xkbcommon"; version = versions.xkbcommon; role = "Keyboard handling library"; }
    { name = "LZ4"; version = versions.lz4; role = "Fast compression"; }
    { name = "Zstd"; version = versions.zstd; role = "Zstandard compression"; }
    { name = "libffi"; version = versions.libffi; role = "Foreign function interface"; }
    { name = "pixman"; version = versions.pixman; role = "Software 2D compositor"; }
  ];

  # Product inventories. Only packages in that target's link/bundle closure.
  inventories = rec {
    ios = versions: (substrate versions) ++ [
      { name = "Waypipe"; version = versions.waypipe; role = "Remote Wayland display proxy"; }
      { name = "libssh2"; version = versions.libssh2; role = "In-process SSH (Apple mobile)"; }
      { name = "epoll-shim"; version = "0.0.20240608"; role = "epoll compatibility layer"; }
      { name = "ANGLE"; version = versions.angle; role = "OpenGL ES on Metal"; }
      { name = "MoltenVK"; version = versions.moltenvk; role = "Vulkan on Metal"; }
      { name = "iland"; version = "userland"; role = "Userspace DRM/KMS/GBM (Mode A)"; }
      { name = "Weston"; version = versions.weston; role = "Bundled nested compositor"; }
      { name = "Niri"; version = versions.niri; role = "Bundled nested compositor"; }
      { name = "zsh"; version = versions.zsh; role = "In-process local shell"; }
      { name = "Foot"; version = versions.foot; role = "Wayland terminal"; }
      { name = "Fuzzel"; version = versions.fuzzel; role = "Wayland launcher"; }
    ];
    ipados = ios;
    macos = versions: (substrate versions) ++ [
      { name = "Waypipe"; version = versions.waypipe; role = "Remote Wayland display proxy"; }
      { name = "OpenSSH"; version = versions.openssh; role = "Secure shell client"; }
      { name = "sshpass"; version = versions.sshpass; role = "Non-interactive SSH password auth"; }
      { name = "ANGLE"; version = versions.angle; role = "OpenGL ES on Metal"; }
      { name = "MoltenVK"; version = versions.moltenvk; role = "Vulkan on Metal"; }
      { name = "KosmicKrisp"; version = "sdk"; role = "Vulkan on Metal (Apple Silicon)"; }
      { name = "SwiftShader"; version = versions.swiftshader; role = "CPU Vulkan ICD"; }
      { name = "iland"; version = "userland"; role = "Userspace DRM/KMS/GBM (Mode A)"; }
      { name = "Weston"; version = versions.weston; role = "Bundled nested compositor"; }
      { name = "Niri"; version = versions.niri; role = "Bundled nested compositor"; }
      { name = "zsh"; version = versions.zsh; role = "Bundled local shell"; }
      { name = "Foot"; version = versions.foot; role = "Wayland terminal"; }
      { name = "Fuzzel"; version = versions.fuzzel; role = "Wayland launcher"; }
    ];
    tvos = versions: (substrate versions) ++ [
      { name = "Waypipe"; version = versions.waypipe; role = "Remote Wayland display proxy"; }
      { name = "libssh2"; version = versions.libssh2; role = "In-process SSH (Apple mobile)"; }
      { name = "epoll-shim"; version = "0.0.20240608"; role = "epoll compatibility layer"; }
      { name = "ANGLE", version = versions.angle; role = "OpenGL ES on Metal"; }
      { name = "MoltenVK"; version = versions.moltenvk; role = "Vulkan on Metal"; }
      { name = "iland"; version = "userland"; role = "Userspace DRM/KMS/GBM (Mode A)"; }
      { name = "Weston"; version = versions.weston; role = "Bundled nested compositor"; }
      { name = "Niri"; version = versions.niri; role = "Bundled nested compositor"; }
      { name = "zsh"; version = versions.zsh; role = "In-process local shell"; }
      { name = "Foot"; version = versions.foot; role = "Wayland terminal"; }
    ];
    watchos = versions: (substrate versions) ++ [
      { name = "Waypipe"; version = versions.waypipe; role = "Remote Wayland display proxy"; }
      { name = "libssh2"; version = versions.libssh2; role = "In-process SSH (Apple mobile)"; }
      { name = "epoll-shim"; version = "0.0.20240608"; role = "epoll compatibility layer"; }
      { name = "iland"; version = "cpu"; role = "SHM/CPU present (watchOS GPU blocked)"; }
      { name = "Weston"; version = versions.weston; role = "Bundled nested compositor"; }
      { name = "Niri"; version = versions.niri; role = "Bundled nested compositor"; }
      { name = "zsh"; version = versions.zsh; role = "In-process local shell"; }
      { name = "Foot"; version = versions.foot; role = "Wayland terminal"; }
    ];
    visionos = ios;
    android = versions: (substrate versions) ++ [
      { name = "Waypipe"; version = versions.waypipe; role = "Remote Wayland display proxy"; }
      { name = "OpenSSH"; version = versions.openssh; role = "SSH client (portable jniLibs)"; }
      { name = "OpenSSL"; version = versions.openssl; role = "Cryptography library"; }
      { name = "ANGLE"; version = versions.angle; role = "OpenGL ES on Vulkan/EGL"; }
      { name = "SwiftShader"; version = versions.swiftshader; role = "CPU Vulkan ICD"; }
      { name = "iland"; version = "userland"; role = "Userspace DRM/KMS/GBM over AHardwareBuffer"; }
      { name = "Weston"; version = versions.weston; role = "Bundled nested compositor"; }
      { name = "Niri"; version = versions.niri; role = "Bundled nested compositor"; }
      { name = "zsh"; version = versions.zsh; role = "In-process local shell"; }
    ];
    linux = versions: (substrate versions) ++ [
      { name = "Waypipe"; version = versions.waypipe; role = "Remote Wayland display proxy"; }
      { name = "OpenSSH"; version = versions.openssh; role = "Host SSH client"; }
      { name = "Weston"; version = versions.weston; role = "Bundled nested compositor"; }
      { name = "Niri"; version = versions.niri; role = "Bundled nested compositor"; }
      { name = "Foot"; version = versions.foot; role = "Wayland terminal"; }
      { name = "zsh"; version = versions.zsh; role = "Bundled local shell"; }
      { name = "kmscube"; version = "mesa"; role = "GLES/Vulkan KMS demo"; }
      { name = "neovim"; version = "0.11"; role = "Bundled editor"; }
      { name = "fastfetch"; version = "2"; role = "System info client"; }
    ];
  };

  toJSON = packages: builtins.toJSON { packages = packages; };
}
