# Shared GN cross-compile recipe for ANGLE (OpenGL ES over Metal/Vulkan).
# Source and gclient deps match nixpkgs#angle (Chromium ANGLE checkout).
{
  lib,
  pkgs,
  buildPackages,
  pname,
  gnExtraFlags,
  preConfigureHook ? "",
  installHook ? "",
  nativeBuildInputsExtra ? [ ],
  buildInputsExtra ? [ ],
  ...
}:

let
  llvmPackages = pkgs.llvmPackages_21;
  llvmMajorVersion = lib.versions.major llvmPackages.llvm.version;
  hostArch = pkgs.stdenv.hostPlatform.parsed.cpu.name;
  hostTriplet = lib.optionalString pkgs.stdenv.hostPlatform.isLinux (lib.getAttr hostArch {
    "x86_64" = "x86_64-unknown-linux-gnu";
    "aarch64" = "aarch64-unknown-linux-gnu";
  });

  clang = pkgs.symlinkJoin {
    name = "angle-clang-llvm-join";
    paths = [
      llvmPackages.llvm
      llvmPackages.clang
    ];
    postBuild = ''
      mkdir -p $out/lib/clang/${llvmMajorVersion}/lib/darwin
      ln -s $out/resource-root/lib/darwin/libclang_rt.osx.a \
        $out/lib/clang/${llvmMajorVersion}/lib/darwin/libclang_rt.osx.a
      ln -s $out/resource-root/lib/darwin/libclang_rt.osx.a \
        $out/lib/clang/${llvmMajorVersion}/lib/darwin/libclang_rt.osx-${hostArch}.a
    '';
  };

  anglePatch = "${pkgs.path}/pkgs/by-name/an/angle/fix-uninitialized-const-pointer-error-001.patch";
  gclientInfo = "${pkgs.path}/pkgs/by-name/an/angle/info.json";
in
pkgs.stdenv.mkDerivation (finalAttrs: {
  inherit pname;
  version = pkgs.angle.version;

  gclientDeps = pkgs.gclient2nix.importGclientDeps gclientInfo;
  sourceRoot = "src";
  strictDeps = true;

  __noChroot = true;

  nativeBuildInputs = [
    pkgs.gn
    pkgs.ninja
    pkgs.gclient2nix.gclientUnpackHook
    pkgs.pkg-config
    pkgs.python3
    llvmPackages.bintools
    pkgs.xcbuild
  ]
  ++ nativeBuildInputsExtra;

  buildInputs = [
    pkgs.apple-sdk_15
  ]
  ++ buildInputsExtra;

  gnFlags = [
    "is_debug=false"
    "use_sysroot=false"
    "clang_base_path=\"${clang}\""
    "angle_build_tests=false"
    "concurrent_links=1"
    "use_custom_libcxx=true"
    "angle_enable_swiftshader=false"
    "angle_enable_wgpu=false"
    "is_component_build=false"
    "treat_warnings_as_errors=false"
    "angle_enable_d3d9=false"
    "angle_enable_d3d11=false"
    "angle_enable_gl=false"
  ]
  ++ gnExtraFlags;

  patches = [ anglePatch ];

  postPatch = ''
    ${lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
      substituteInPlace build/config/clang/BUILD.gn \
        --replace-fail \
          "_dir = \"${hostTriplet}\"" \
          "_dir = \"${hostTriplet}\"
      _suffix = \"-${hostArch}\""
    ''}

    # Don't precompile Metal shaders (needs proprietary Xcode metal CLI).
    substituteInPlace src/libANGLE/renderer/metal/metal_backend.gni \
      --replace-fail \
        "metal_internal_shader_compilation_supported =" \
        "metal_internal_shader_compilation_supported = false &&"

    cat > build/config/gclient_args.gni <<'EOF'
    checkout_angle_internal = false
    checkout_angle_mesa = false
    checkout_angle_restricted_traces = false
    generate_location_tags = false
    EOF

    patchShebangs build/toolchain/apple || true
  '';

  preConfigure = preConfigureHook;

  configurePhase = ''
    runHook preConfigure
    echo "gn flags: ${lib.concatStringsSep " " finalAttrs.gnFlags}"
    gn gen out --args=${lib.escapeShellArg (lib.concatStringsSep " " finalAttrs.gnFlags)}
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    ninja -C out angle angle_util angle_common libEGL libGLESv2
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    ${installHook}
    runHook postInstall
  '';

  meta = with lib; {
    description = "ANGLE OpenGL ES (cross-compiled ${pname})";
    homepage = "https://angleproject.org";
    license = licenses.bsd3;
    platforms = platforms.darwin;
  };
})
