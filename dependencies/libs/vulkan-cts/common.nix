# Shared configuration for VK-GL-CTS (Vulkan and OpenGL Conformance Test Suites)
# Used by macos.nix, ios.nix, android.nix
{ pkgs, version ? "1.4.5.0" }:
let
  sources = import ./sources.nix {
    inherit (pkgs) fetchurl fetchFromGitHub libpng zlib;
  };
in
rec {
  inherit version sources;

  src = pkgs.fetchFromGitHub {
    owner = "KhronosGroup";
    repo = "VK-GL-CTS";
    rev = "vulkan-cts-${version}";
    hash = "sha256-cbXSelRPCCH52xczWaxqftbimHe4PyIKZqySQSFTHos=";
  };

  # Vulkan-only build targets (minimal, fast)
  vulkanTargets = "deqp-vk";

  # GL CTS build target (includes ES2, ES3, ES31, EGL)
  glTargets = "glcts";

  # Combined Vulkan + GL (full suite)
  fullTargets = "deqp-vk glcts";

  prePatch = sources.prePatch;
}
