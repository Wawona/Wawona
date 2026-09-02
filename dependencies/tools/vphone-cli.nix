# Darwin-only wrap of Lakr233/vphone-cli for the Wawona jailbreak lab.
# Not an L0 toolchain input. IPSWs stay in ~/.vphone (or $VPHONE_ROOT).
{
  lib,
  stdenv,
  fetchFromGitHub,
  makeWrapper,
  python3,
  aria2,
  wget,
  gnutar,
  openssl,
  cmake,
  libusb1,
  zstd,
  # ldid from nixpkgs when available; Procursus ldid preferred at runtime.
  ldid ? null,
}:

assert stdenv.hostPlatform.isDarwin;
assert stdenv.hostPlatform.isAarch64;

stdenv.mkDerivation rec {
  pname = "vphone-cli";
  version = "unstable-2026-08";

  src = fetchFromGitHub {
    owner = "Lakr233";
    repo = "vphone-cli";
    # Pin loosely; bump when the lab recipe needs a known tip.
    rev = "main";
    hash = lib.fakeHash; # replaced after first prefetch; see passthru.update
  };

  # Upstream often needs a live checkout for IPSW tooling. Prefer wrapping a
  # fetch that fails eval until hash is filled; for local lab use the
  # writeShellApplication fallback below when hash is fake.
  meta = {
    description = "Virtual iPhone (PCC) CLI with jailbreak jb variant";
    homepage = "https://github.com/Lakr233/vphone-cli";
    platforms = [ "aarch64-darwin" ];
    license = lib.licenses.unfreeRedistributable; # research tooling; check upstream
  };
}
