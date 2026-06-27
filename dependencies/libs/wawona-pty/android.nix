# libwwn-pty.a for Android (NDK).
#
# Android allows fork/exec, so the PTY shim uses the portable posix_spawn path in
# wwn_pty.c (spawn_on_slave) — the same code the macOS/desktop path uses — to
# launch a real zsh binary on the slave end of a forkpty()-style PTY. None of the
# Apple in-process (no-fork) machinery is compiled here, and there is no uutils
# in-process dispatch shim: Android ships the uutils multicall binary on PATH and
# zsh exec()s it normally.
{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  androidToolchain ? (import ../../toolchains/android.nix { inherit lib pkgs; }),
  ...
}:

pkgs.stdenv.mkDerivation {
  name = "wawona-pty-android";
  src = ./.;

  buildPhase = ''
    runHook preBuild
    CC="${androidToolchain.androidCC}"
    AR="${androidToolchain.androidAR}"
    RANLIB="${androidToolchain.androidRANLIB}"
    CFLAGS="--target=${androidToolchain.androidTarget} --sysroot=${androidToolchain.androidNdkSysroot} -fPIC -O2"

    # Portable PTY/spawn path only (the Apple in-process branch is #if'd out on
    # non-Apple targets, so plain wwn_pty.c is the forkpty/posix_spawn build).
    "$CC" -c src/wwn_pty.c -Iinclude $CFLAGS -o wwn_pty.o
    "$AR" rcs libwwn-pty.a wwn_pty.o
    if command -v "$RANLIB" >/dev/null 2>&1; then
      "$RANLIB" libwwn-pty.a
    fi
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib $out/include
    cp libwwn-pty.a $out/lib/
    cp include/wwn_pty.h $out/include/
    runHook postInstall
  '';

  meta = with lib; {
    description = "Wawona PTY shim (Android NDK, forkpty/posix_spawn path)";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
