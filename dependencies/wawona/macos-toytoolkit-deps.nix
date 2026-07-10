# nixpkgs cairo/pango closure for macOS Xcode linking. weston-toytoolkit-ldflags
# emits -lcairo/-lpango/etc. and -L<dep>/lib; mobile deps come from wwn-toolchain
# cross builds, but macOS weston uses pkgs.cairo (registry macos = null).
#
# Multi-output nixpkgs derivations (pango, glib, fontconfig, pcre2, ...) default
# to their `bin`/`dev` output under toString, which has no /lib. Force the
# library output via lib.getLib so the -L paths point at real .dylib dirs.
{ pkgs }:
let
  getLib = pkgs.lib.getLib;
in
{
  cairo = getLib pkgs.cairo;
  pango = getLib pkgs.pango;
  harfbuzz = getLib pkgs.harfbuzz;
  fontconfig = getLib pkgs.fontconfig;
  freetype = getLib pkgs.freetype;
  fribidi = getLib pkgs.fribidi;
  glib = getLib pkgs.glib;
  libpng = getLib pkgs.libpng;
  pcre2 = getLib pkgs.pcre2;
  expat = getLib pkgs.expat;
}
