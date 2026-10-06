# Build the current local Apple product without discarding untracked sources.
# Uses published locks for upstream inputs and explicit sibling source overrides.
# Run from Wawona: nix build --impure --file scripts/build-current-ios.nix
# Add --arg simulator true for the native iOS Simulator product.
{ simulator ? false }:
let
  root = ../.;
  source = builtins.path {
    path = root;
    name = "wawona-local-build-source";
    filter = path: type:
      let name = baseNameOf path;
      in type != "unknown"
        && !(builtins.elem name [ ".git" ".cache" ".DS_Store" ])
        && !(builtins.any (entry: toString path == "${toString root}/${entry}") [ "build" "target" ".build" ".direnv" ".nix-deps" ".artifacts" ".agent-device" "Wawona-gradle-project" ])
        && builtins.match "\\.derivedData.*" name == null
        && builtins.match "relay-vm-state.*" name == null
        && builtins.match "result(-.*)?" name == null;
  };
  base = builtins.getFlake (builtins.unsafeDiscardStringContext (toString source));
  cleanSibling = root: builtins.path {
    path = root;
    filter = path: type:
      let name = baseNameOf path;
      in type != "unknown"
        && !(builtins.elem name [ ".git" ".cache" ".DS_Store" "target" ".direnv" ])
        && builtins.match "relay-vm-state.*" name == null
        && builtins.match "result(-.*)?" name == null;
  };
  toolchainSource = cleanSibling ../../wwn-toolchain;
  toolchainInputs = base.inputs.wwn-toolchain.inputs // {
    inherit (base.inputs) nixpkgs rust-overlay;
    self = toolchain;
  };
  toolchain = (import (toolchainSource + "/flake.nix")).outputs toolchainInputs // {
    outPath = toolchainSource;
    inputs = toolchainInputs;
  };
  ilandSource = cleanSibling ../../wwn-iland;
  relaySource = cleanSibling ../../Relay;
  ilandInputs = base.inputs.wwn-iland.inputs // {
    inherit (base.inputs) nixpkgs rust-overlay;
    wwn-toolchain = toolchain;
    self = iland;
  };
  iland = (import (ilandSource + "/flake.nix")).outputs ilandInputs // {
    outPath = ilandSource;
    inputs = ilandInputs;
  };
  relayInputs = base.inputs.wwn-relay.inputs // {
    inherit (base.inputs) nixpkgs rust-overlay microvm;
    wwn-toolchain = toolchain;
    crate2nix = toolchain.inputs.crate2nix;
    self = relay;
  };
  relay = (import (relaySource + "/flake.nix")).outputs relayInputs // {
    outPath = relaySource;
    inputs = relayInputs;
  };
  waypipeSource = cleanSibling ../../wwn-waypipe;
  waypipeInputs = base.inputs.wwn-waypipe.inputs // {
    inherit (base.inputs) nixpkgs rust-overlay;
    wwn-toolchain = toolchain;
    wwn-iland = iland;
    self = waypipe;
  };
  waypipe = (import (waypipeSource + "/flake.nix")).outputs waypipeInputs // {
    outPath = waypipeSource;
    inputs = waypipeInputs;
  };
  terminalSource = cleanSibling ../../Terminal;
  productInputs = base.inputs // {
    wwn-toolchain = toolchain;
    wwn-iland = iland;
    wwn-relay = relay;
    wwn-waypipe = waypipe;
    terminal = terminalSource;
    self = product;
  };
  product = (import (source + "/flake.nix")).outputs productInputs // {
    outPath = source;
    inputs = productInputs;
  };
in if simulator then product.packages.aarch64-darwin.wawona-ios-app-sim
   else product.packages.aarch64-darwin.wawona-ios-app-device
