# Real zsh binary cross-compiled for Android (NDK).
#
# Unlike the iOS recipe this produces an ordinary executable ($out/bin/zsh): on
# Android fork/exec is permitted, so the PTY shim posix_spawn()s this binary and
# zsh runs external commands (including the uutils multicall) normally. There is
# therefore NO main-rename and NO patch-zsh-exec.py here — those exist solely for
# the App-Store in-process model.
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
  src = pkgs.zsh.src;
in
pkgs.stdenv.mkDerivation {
  name = "zsh-android";
  inherit src;

  nativeBuildInputs = with buildPackages; [
    autoconf
    automake
    yodl
  ];

  preConfigure = ''
    export CC="${androidToolchain.androidCC} --target=${androidToolchain.androidTarget}"
    export AR="${androidToolchain.androidAR}"
    export STRIP="${androidToolchain.androidSTRIP}"
    export RANLIB="${androidToolchain.androidRANLIB}"
    export CFLAGS="--sysroot=${androidToolchain.androidNdkSysroot} -fPIE -O2"
    export LDFLAGS="--target=${androidToolchain.androidTarget} --sysroot=${androidToolchain.androidNdkSysroot} -L${androidToolchain.androidNdkAbiLibDir} -fPIE -pie"
    # NDK has no terminfo/curses; provide the same tiny termcap stub the iOS build
    # uses so the line editor links.
    cp ${./termcap-stub.h} termcap-stub.h
    cp ${./termcap-stub.c} termcap-stub.c
  '';

  configurePhase = ''
    runHook preConfigure
    "$CC" -c termcap-stub.c $CFLAGS -o termcap-stub.o
    "$AR" rcs libtermcap.a termcap-stub.o
    cp libtermcap.a libcurses.a
    export LDFLAGS="-L$PWD $LDFLAGS"
    export LIBS="-L$PWD $LIBS"
    export ac_cv_search_tigetstr=-lcurses
    export ac_cv_search_tigetflag=-lcurses
    export ac_cv_search_tgetent=-lcurses
    ./configure \
      --host=${androidToolchain.androidTarget} \
      --build=${buildPackages.stdenv.hostPlatform.config} \
      --prefix=$out \
      --enable-static \
      --disable-dynamic \
      --disable-nls \
      --disable-gdbm \
      --disable-pcre \
      --disable-cap \
      --disable-ldconfig \
      --with-tcset=termios \
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
    cp Src/zsh $out/bin/zsh
    for subdir in Functions Completion Misc Etc; do
      if [ -d "./$subdir" ]; then
        cp -R "./$subdir" $out/share/zsh/
      fi
    done
    runHook postInstall
  '';

  meta = with lib; {
    description = "zsh shell (Android NDK cross-build, real executable)";
    homepage = "https://www.zsh.org/";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
