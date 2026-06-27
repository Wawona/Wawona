# Link flags for the cross-compiled weston toytoolkit (cairo/pango stack) consumed
# by libweston-13.a on Apple mobile and Android targets. Pass the platform's
# nativeDeps attrset from flake.nix.
{ lib, deps, forceLoadWeston ? false, linkMode ? "force_load" }:

let
  strip = d: if d == null then "" else toString d;
  libPath = name:
    if deps ? ${name} && deps.${name} != null then "-L${strip deps.${name}}/lib" else "";
  libPaths = lib.filter (s: s != "") [
    (libPath "cairo")
    (libPath "pango")
    (libPath "harfbuzz")
    (libPath "fontconfig")
    (libPath "freetype")
    (libPath "fribidi")
    (libPath "glib")
    (libPath "libpng")
    (libPath "pcre2")
    (libPath "expat")
    (libPath "libintl")
    (libPath "weston")
    (libPath "wawona-pty")
  ];
  libs = lib.filter (s: s != "") [
    "-lcairo"
    "-lpangocairo-1.0"
    "-lpangoft2-1.0"
    "-lpango-1.0"
    "-lharfbuzz"
    "-lfontconfig"
    "-lfreetype"
    "-lfribidi"
    "-lgobject-2.0"
    "-lglib-2.0"
    "-lgmodule-2.0"
    "-lgio-2.0"
    "-lpng16"
    "-lpcre2-8"
    (if deps ? libintl && deps.libintl != null then "-lintl" else "")
  ];
  westonLibDir = strip (deps.weston or null) + "/lib";
  westonArchives =
    let
      archiveNames = [
        "libweston-13.a"
        "libweston-terminal.a"
        "libweston-desktop-13.a"
        "libweston-keyboard.a"
      ];
      existingArchives =
        if forceLoadWeston && deps ? weston && deps.weston != null then
          lib.filter (name: builtins.pathExists "${westonLibDir}/${name}") archiveNames
        else
          [ ];
    in
    if existingArchives == [ ] then
      [
        "-lweston-13"
        "-lweston-desktop-13"
        "-lweston-terminal"
      ]
    else if linkMode == "whole_archive" then
      [
        "-Wl,--whole-archive"
      ]
      ++ (map (name: "${westonLibDir}/${name}") existingArchives)
      ++ [
        "-Wl,--no-whole-archive"
      ]
    else
      lib.concatLists (map (name: [ "-force_load" "${westonLibDir}/${name}" ]) existingArchives);
  wawonaPtyArchive =
    let
      ptyDir = strip (deps."wawona-pty" or null);
    in
    if ptyDir != "" && builtins.pathExists "${ptyDir}/lib/libwwn-pty.a" then
      [ "-force_load" "${ptyDir}/lib/libwwn-pty.a" ]
    else
      [ ];
in
libPaths ++ westonArchives ++ wawonaPtyArchive ++ libs
