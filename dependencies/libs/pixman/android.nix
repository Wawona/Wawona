{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  androidToolchain ? (import ../../toolchains/android.nix { inherit lib pkgs; }),
  ...
}:

let
  fetchSource = common.fetchSource;
  # androidToolchain passed from caller
  # Use pixman from nixpkgs source
  pixmanSource = pkgs.pixman.src;
  src = pixmanSource;
  buildFlags = [
    "-Dopenmp=disabled"
    "-Dgtk=disabled"
    "-Dtests=disabled"
    "-Ddemos=disabled"
  ];
  patches = [ ];
in
pkgs.stdenv.mkDerivation {
  name = "pixman-android";
  inherit src patches;
  nativeBuildInputs = with buildPackages; [
    meson
    ninja
    pkg-config
    (python3.withPackages (
      ps: with ps; [
        setuptools
        pip
        packaging
        mako
        pyyaml
      ]
    ))
  ] ++ lib.optionals buildPackages.stdenv.hostPlatform.isLinux [ patchelf ];
  buildInputs = [ ];
  preConfigure = ''
        export CC="${androidToolchain.androidCC}"
        export CXX="${androidToolchain.androidCXX}"
        export AR="${androidToolchain.androidAR}"
        export STRIP="${androidToolchain.androidSTRIP}"
        export RANLIB="${androidToolchain.androidRANLIB}"
        
        # Create Android cross-file for Meson
        cat > android-cross-file.txt <<EOF
    [binaries]
    c = '${androidToolchain.androidCC}'
    cpp = '${androidToolchain.androidCXX}'
    ar = '${androidToolchain.androidAR}'
    strip = '${androidToolchain.androidSTRIP}'
    pkgconfig = '${buildPackages.pkg-config}/bin/pkg-config'

    [host_machine]
    system = 'linux'
    cpu_family = 'aarch64'
    cpu = 'aarch64'
    endian = 'little'

    [built-in options]
    c_args = ['-fPIC']
    cpp_args = ['-fPIC']
    c_link_args = []
    cpp_link_args = []
    EOF
  '';
  configurePhase = ''
    runHook preConfigure
    meson setup build \
      --prefix=$out \
      --libdir=$out/lib \
      --cross-file=android-cross-file.txt \
      --buildtype=release \
      --default-library=static \
      ${lib.concatMapStringsSep " " (flag: flag) buildFlags}
    runHook postConfigure
  '';
  buildPhase = ''
    runHook preBuild
    meson compile -C build
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    meson install -C build
    PIXMAN_SO_REAL="$(readlink -f "$out/lib/libpixman-1.so")"
    if command -v patchelf >/dev/null 2>&1 && [ -n "$PIXMAN_SO_REAL" ] && [ -f "$PIXMAN_SO_REAL" ]; then
      patchelf --set-soname libpixman-1.so "$PIXMAN_SO_REAL"
    fi
    runHook postInstall
  '';
}
