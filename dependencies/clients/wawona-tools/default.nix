{ pkgs }:

pkgs.runCommand "wawona-tools-sources" { } ''
  mkdir -p "$out"
  cp ${./Cargo.toml} "$out/Cargo.toml"
  cp ${./Cargo.lock} "$out/Cargo.lock"
  cp -R ${./src} "$out/src"
''
