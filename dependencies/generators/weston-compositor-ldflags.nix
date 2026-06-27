# Link flags for the cross-compiled Weston nested compositor (libweston-compositor-13.a)
# consumed on Apple mobile and Android targets. Pass the platform nativeDeps attrset
# from flake.nix.
{ lib, deps, forceLoadCompositor ? true, linkMode ? "force_load" }:

let
  strip = d: if d == null then "" else toString d;
  libPath = name:
    if deps ? ${name} && deps.${name} != null then "-L${strip deps.${name}}/lib" else "";
  compositor = deps."weston-compositor" or deps.weston-compositor or null;
  libPaths = lib.filter (s: s != "") [
    (libPath "libwayland")
    (libPath "expat")
    (libPath "weston-compositor")
  ];
  libs =
    lib.filter (s: s != "") [
      "-lwayland-server"
      "-lwayland-cursor"
      "-lexpat"
      "-lm"
    ]
    ++ lib.optionals (deps.iland or null != null) [
      "-lwayland-egl"
    ];
  compositorArchive =
    if !forceLoadCompositor || compositor == null then
      [ ]
    else if linkMode == "whole_archive" then
      [
        "-Wl,--whole-archive"
        "${strip compositor}/lib/libweston-compositor-13.a"
        "-Wl,--no-whole-archive"
      ]
    else
      [ "-force_load" "${strip compositor}/lib/libweston-compositor-13.a" ];
  # libweston-desktop-13.a and libweston-keyboard.a are force-loaded by
  # weston-toytoolkit-ldflags.nix; do not duplicate them here.
in
libPaths ++ compositorArchive ++ libs
