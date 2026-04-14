{
  pkgs,
  wawonaVersion,
  wawonaSrc ? ../..,
  ...
}:

pkgs.writeShellApplication {
  name = "wawona-linux-run";
  runtimeInputs = [
    pkgs.cargo
    pkgs.rustc
    pkgs.pkg-config
    pkgs.gtk4
    pkgs.libadwaita
  ];
  text = ''
    set -euo pipefail
    exec cargo run --manifest-path "${wawonaSrc}/Cargo.toml" --bin wawona-linux-ui --features linux-ui -- "$@"
  '';
  meta = {
    description = "Wawona Linux GTK shell scaffold";
    platforms = pkgs.lib.platforms.linux;
  };
}
