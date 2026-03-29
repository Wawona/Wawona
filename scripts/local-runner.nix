{ pkgs, src }:

pkgs.stdenv.mkDerivation {
  pname = "local-runner";
  version = "0.1.0";

  inherit src;

  nativeBuildInputs = [ pkgs.makeWrapper ];
  buildInputs = [ (pkgs.python3.withPackages (ps: [ ps.pyyaml ])) ];

  installPhase = ''
    mkdir -p $out/bin
    cp scripts/local_runner.py $out/bin/local-runner
    chmod +x $out/bin/local-runner
    
    wrapProgram $out/bin/local-runner \
      --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.nix pkgs.nix-output-monitor pkgs.which ]} \
      --set PYTHONPATH $PYTHONPATH
  '';
}
