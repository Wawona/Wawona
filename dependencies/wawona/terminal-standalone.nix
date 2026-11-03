# Standalone Wawona Terminal (`nix run .#terminal`).
# Source: flake input `terminal` (github.com/Wawona/Terminal).
# Recipe: Terminal/nix/package.nix + Terminal/flake.nix
#   zig2nix Zig 0.17 + ghostty libghostty-vt + Rust libghostty-rs (pkg-config).
{
  pkgs,
  terminalSrc,
  libghosttyVt ? null,
  zig ? null,
}:
pkgs.callPackage (terminalSrc + "/nix/package.nix") {
  inherit (pkgs)
    lib
    stdenv
    rustPlatform
    pkg-config
    gtk4
    glib
    clang
    libclang
    openssl
    libiconv
    writeShellApplication
    ;
  inherit terminalSrc zig;
  # Prefer caller-supplied Ghostty VT (from Terminal flake / ghostty input).
  # When null, package.nix cannot link nix-ghostty-vt; Wawona flake must pass it.
  libghosttyVt =
    if libghosttyVt != null then
      libghosttyVt
    else
      throw "terminal-standalone: pass libghosttyVt (ghostty.packages.\${system}.libghostty-vt)";
}
