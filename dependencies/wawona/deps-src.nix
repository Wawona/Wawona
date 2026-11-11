# The patched sources every backend build reads, as .deps/src
# (`cargo xtask deps get <sdk>` always fetches it):
#   waypipe, coreutils     the root Cargo.toml's path crates (Apple waypipe)
#   android/waypipe        waypipe with the Android patch set
#   crates/<name>-<ver>    crates.io crates `cargo xtask backend` [patch]es
#   terminal, toolbar-keys the Terminal and ToolbarKeys sources
# Every patch here is gated on target_os, so one tree serves all slices.
{ pkgs, appleWorkspace, androidWorkspace, terminalSrc, toolbarKeysSrc }:
let
  # Only the crates patched below, at the versions and checksums Cargo.lock pins.
  patched = p: p.name == "nix" || (p.name == "wayland-backend" && p.version == "0.3.17");
  crates = map (p: pkgs.runCommand "${p.name}-${p.version}" { } ''
    mkdir -p $out && tar -xzf ${pkgs.fetchurl {
      name = "${p.name}-${p.version}.crate";
      url = "https://static.crates.io/crates/${p.name}/${p.name}-${p.version}.crate";
      sha256 = p.checksum;
    }} -C $out --strip-components=1
  '') (builtins.filter patched (builtins.fromTOML (builtins.readFile ../../Cargo.lock)).package);
  appleTargets = ''any(target_os = "macos", target_os = "ios", target_os = "tvos", target_os = "visionos", target_os = "watchos")'';
in
pkgs.runCommand "wawona-deps-src" { } ''
  mkdir -p $out/crates $out/android
  cp -r ${appleWorkspace}/waypipe ${appleWorkspace}/coreutils $out/
  cp -r ${androidWorkspace}/waypipe $out/android/waypipe
  cp -r ${terminalSrc} $out/terminal
  cp -r ${toolbarKeysSrc} $out/toolbar-keys
  chmod -R u+w $out
  # tvOS and watchOS libc has no fork/exec*; waypipe gates pipe2/ppoll on iOS
  # and tvOS has the same APIs.
  (cd $out/coreutils/src/uu/env && patch -p1 < ${../patches/uu_env-0.12.0-watchos-tvos-no-execvp.patch})
  find $out/waypipe/src -name '*.rs' -exec sed -i \
    's/target_os = "ios"/any(target_os = "ios", target_os = "tvos")/g' {} +
  # libc omits sockaddr_ctl outside macOS and fork/exec* on tvOS/watchOS.
  for n in ${toString crates}; do
    d=$out/crates/''${n#*-}
    cp -r $n $d
    chmod -R u+w $d
  done
  for d in $out/crates/nix-0.*; do
    (cd $d && patch -p1 < ${../patches/nix-0.30.1-watchos-tvos-no-fork-sysctl.patch})
    # Cargo caps lints for registry crates, not [patch] path crates; the
    # patch leaves code unused on some targets.
    sed -i 's/#!\[deny(unused)\]/#![warn(unused)]/' $d/src/lib.rs
  done
  find $out/crates/wayland-backend-0.3.17 -name '*.rs' -exec sed -i \
    's/target_os[[:space:]]*=[[:space:]]*"macos"/${appleTargets}/g' {} +
''
