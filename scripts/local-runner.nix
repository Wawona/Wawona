{ pkgs }:

let
  python = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
in
pkgs.writeShellApplication {
  name = "local-runner";
  runtimeInputs = [ pkgs.nix-output-monitor pkgs.which ];
  text = ''
    exec ${python}/bin/python ${./local_runner.py} "$@"
  '';
}
