# Builds a uutils "coreutils" multicall binary from the pinned coreutils-src for
# the platforms where fork/exec IS allowed (macOS, Android). On those platforms
# zsh launches the binary normally — NO zsh exec patch and NO in-process shim is
# needed (that machinery is Apple-mobile only).
#
# The same safe subset as the in-process build is used so behaviour matches
# across platforms. Per-utility symlinks (ls, cat, ...) are created next to the
# multicall binary so a bare `ls` resolves on PATH; `coreutils ls` also works.
#
# Wiring:
#   * macOS: add "${wawona-coreutils-multicall}/bin" to the shell PATH (the
#     macOS shell uses the host zsh via NSTask; prepend this dir).
#   * Android: copy bin/ into the APK userland and add it to PATH in the
#     Android shell environment.
{
  pkgs,
  lib ? pkgs.lib,
  coreutils-src,
  rustPlatform ? pkgs.rustPlatform,
  # Keep in sync with the `coreutils` dependency feature subset in Cargo.toml
  # and wwn_safe_subset[] in wawona-dispatch.c.
  utils ? [
    "ls" "cat" "cp" "mv" "rm" "mkdir" "rmdir" "ln" "touch" "echo"
    "pwd" "head" "tail" "wc" "sort" "cut" "tr" "seq" "basename"
    "dirname" "stat" "du" "df" "date" "env" "printenv" "uname"
    "whoami" "yes" "tee" "nl" "tac" "fold" "expand" "unexpand"
    "truncate"
  ],
}:

rustPlatform.buildRustPackage {
  pname = "wawona-coreutils-multicall";
  version = "0.0.30";
  src = coreutils-src;

  cargoLock = {
    lockFile = "${coreutils-src}/Cargo.lock";
  };

  buildNoDefaultFeatures = true;
  buildFeatures = utils;

  # Only the umbrella multicall binary; skip uudoc and the test suite.
  cargoBuildFlags = [ "--bin" "coreutils" ];
  doCheck = false;

  postInstall = ''
    cd $out/bin
    for u in ${lib.concatStringsSep " " utils}; do
      ln -sf coreutils "$u"
    done
  '';

  meta = {
    description = "uutils coreutils multicall binary (Wawona safe subset)";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
