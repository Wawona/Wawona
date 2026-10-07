{ pkgs }:

# Historical source package for the ObjC shell/launcher. Product code is
# Sources/WawonaApple/Shell/AppScanner.swift. Keep an empty derivation so flake
# attrs that still reference wawona-shell do not break.
pkgs.runCommand "wawona-shell-sources" { } ''
  mkdir -p "$out"
  cp ${./sources.nix} "$out/sources.nix"
  echo "Sources/WawonaApple/Shell/AppScanner.swift" > "$out/README"
''
