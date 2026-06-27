{
  lib,
  pkgs,
  buildPackages,
  iosToolchain,
  simulator ? false,
}:

let
  platformInfo = import ../../toolchains/apple-mobile-platform.nix;
  mobile = platformInfo { inherit iosToolchain simulator; };
  src = pkgs.zsh.src;
in
pkgs.stdenv.mkDerivation {
  name = "zsh-ios${if simulator then "-sim" else ""}";
  inherit src;

  __noChroot = true;

  nativeBuildInputs = with buildPackages; [
    autoconf
    automake
  ];

  preConfigure = ''
    ${iosToolchain.mkIOSBuildEnv { inherit simulator; minVersion = mobile.minVersion; }}
    unset MACOSX_DEPLOYMENT_TARGET IPHONEOS_DEPLOYMENT_TARGET
    export NIX_CFLAGS_COMPILE=""
    export NIX_LDFLAGS=""
    cp ${./termcap-stub.h} termcap-stub.h
    export CC="$CC"
    export CXX="$CXX"
    export CFLAGS="-arch arm64 -isysroot $SDKROOT ${mobile.minVerFlag} -fPIC -O2"
    export LDFLAGS="-arch arm64 -isysroot $SDKROOT ${mobile.minVerFlag}"
  '';

  configurePhase = ''
    runHook preConfigure
    AR="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ar"
    cp ${./termcap-stub.c} termcap-stub.c
    $CC -c termcap-stub.c $CFLAGS -o termcap-stub.o
    $AR rcs libtermcap.a termcap-stub.o
    cp libtermcap.a libcurses.a
    export LDFLAGS="-L$PWD $LDFLAGS"
    export LIBS="-L$PWD $LIBS"
    export ac_cv_search_tigetstr=-lcurses
    export ac_cv_search_tigetflag=-lcurses
    export ac_cv_search_tgetent=-lcurses
    ./configure \
      --host=aarch64-apple-darwin \
      --build=${buildPackages.stdenv.hostPlatform.config} \
      --prefix=$out \
      --enable-static \
      --disable-nls \
      --disable-gdbm \
      --disable-pcre \
      --disable-cap \
      --disable-etcdir \
      --disable-ldconfig \
      --with-tcset=termios \
      ac_cv_func_getpwuid=no \
      ac_cv_func_getpwnam=no \
      ac_cv_func_getgrgid=no \
      ac_cv_func_getgrnam=no \
      zsh_cv_sys_dev_fd=no \
      zsh_cv_sys_dev_fd_63=no
    runHook postConfigure
    echo '#define TGOTO_PROTO_MISSING 1' >> config.h
  '';

  buildPhase = ''
    runHook preBuild
    make -C Src -j''${NIX_BUILD_CORES:-4} zsh
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/share/zsh
    if [ -d share ]; then
      cp -R share/. $out/share/zsh/ 2>/dev/null || true
    fi
    cp Src/zsh $out/bin/zsh
    strip $out/bin/zsh || true
    runHook postInstall
  '';
}
