# One-shot jailbroken vphone lab: gate → create/CFW(jb) → launch → SSH smoke.
#   nix run .#vphone-jb-lab
# See docs/testing/vphone-jailbreak-lab.md.
{
  lib,
  writeShellApplication,
  vphone-cli,
  sshpass,
  coreutils,
  gnugrep,
  gnused,
  gawk,
}:

writeShellApplication {
  name = "vphone-jb-lab";
  runtimeInputs = [
    vphone-cli
    sshpass
    coreutils
    gnugrep
    gnused
    gawk
  ];
  # Embed the checkout script so `nix run` works from any cwd once built.
  # Host /usr/bin/nc (macOS) is used for port probes.
  text = builtins.readFile ../../scripts/vphone-jb-lab.sh;
}
