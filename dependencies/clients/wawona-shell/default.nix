{ pkgs }:

pkgs.runCommand "wawona-shell-sources" { } ''
  mkdir -p "$out"
  cp -R ${./src} "$out/src"
  cp ${./sources.nix} "$out/sources.nix"
''
