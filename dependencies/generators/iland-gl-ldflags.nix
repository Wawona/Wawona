# Link flags for iland + ANGLE + in-process kmscube on Apple targets.
# Mirrors wwn-kmscube/dependencies/generators/kmscube-ldflags.nix.
{ lib, deps, forceLoad ? true, simulator ? false }:

let
  strip = d: if d == null then "" else toString d;
  libPath = name:
    if deps ? ${name} && deps.${name} != null then "-L${strip deps.${name}}/lib" else "";
  iland = deps.iland or null;
  angle = deps.angle or null;
  kmscube =
    deps.kmscube or deps."iland-gl-clients" or deps.iland-gl-clients or null;
  angleLinkKind =
    if angle == null then
      "none"
    else if builtins.pathExists "${strip angle}/nix-support/link-kind" then
      lib.strings.trim (builtins.readFile "${strip angle}/nix-support/link-kind")
    else if builtins.pathExists "${strip angle}/lib/libEGL.dylib" then
      "dylib"
    else
      "static";
  libPaths = lib.filter (s: s != "") [
    (libPath "iland")
    (libPath "angle")
    (libPath "kmscube")
    (libPath "iland-gl-clients")
  ];
  ilandArchive =
    if forceLoad && iland != null then
      [ "-force_load" "${strip iland}/lib/libiland_userland.a" ]
    else
      [ ];
  kmscubeArchive =
    if forceLoad && kmscube != null then
      [ "-force_load" "${strip kmscube}/lib/libkmscube.a" ]
    else
      [ ];
  angleFlags =
    if angle == null then
      [ ]
    else if angleLinkKind == "dylib" then
      [ "-lEGL" "-lGLESv2" ]
    else
      [
        "-force_load" "${strip angle}/lib/libEGL.a"
        "-force_load" "${strip angle}/lib/libGLESv2.a"
      ];
  cxxFlags =
    if angle != null && angleLinkKind != "dylib" then
      [ "-lc++" "-lc++abi" ]
    else
      [ ];
  platformSupportLibs = [
    "-framework"
    "Accelerate"
    "-liconv"
  ];
in
libPaths ++ ilandArchive ++ kmscubeArchive ++ angleFlags ++ cxxFlags ++ platformSupportLibs
