{ pkgs }:
let
  helper = pkgs.runCommand "wawona-carplay-helper" { nativeBuildInputs = [ pkgs.rustc pkgs.stdenv.cc ]; } ''
    mkdir -p $out/bin
    cp ${./main.rs} main.rs
    cp ${./tui.rs} tui.rs
    rustc --edition=2021 -O main.rs -o $out/bin/carplay
  '';
in pkgs.writeShellApplication {
  name = "carplay";
  runtimeInputs = [ pkgs.git pkgs.curl pkgs.unzip pkgs.nodejs ];
  text = ''
    umask 077
    export JAVA_HOME="${pkgs.jdk21}"
    export PATH="$JAVA_HOME/bin:$PATH:/usr/bin:/bin:/usr/sbin:/sbin"
    exec ${helper}/bin/carplay "$@"
  '';
}
