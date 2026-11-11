# cargo xtask for derivations that prepare a Cargo workspace
# (workspace-src.nix). Call it from buildPackages: it runs on the builder.
{ lib, rustPlatform }:
rustPlatform.buildRustPackage {
  pname = "wawona-xtask";
  version = "0";
  src = lib.cleanSourceWith {
    src = ../../xtask;
    filter = path: _: baseNameOf path != "target";
  };
  cargoLock.lockFile = ../../xtask/Cargo.lock;
  doCheck = false;
}
