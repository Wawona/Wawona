# Runnable lab wrapper for Lakr233/vphone-cli (Swift + Makefile).
# Clones into $VPHONE_ROOT/src, builds via scripts/build.sh, execs the .app binary.
# IPSWs stay under ~/.vphone. See docs/testing/vphone-jailbreak-lab.md.
{
  lib,
  writeShellApplication,
  git,
  python3,
  aria2,
  wget,
  gnutar,
  openssl,
  cmake,
  libusb1,
  zstd,
  coreutils,
  findutils,
  gnused,
  gnugrep,
  gnumake,
}:

writeShellApplication {
  name = "vphone-cli";
  runtimeInputs = [
    git
    python3
    aria2
    wget
    gnutar
    openssl
    cmake
    libusb1
    zstd
    coreutils
    findutils
    gnused
    gnugrep
    gnumake
  ];
  text = ''
    set -euo pipefail
    ROOT="''${VPHONE_ROOT:-$HOME/.vphone}"
    SRC="$ROOT/src/vphone-cli"
    BIN_APP="$SRC/.build/vphone-cli.app/Contents/MacOS/vphone-cli"
    BIN_REL="$SRC/.build/release/vphone-cli"
    mkdir -p "$ROOT"

    if [[ ! -d "$SRC/.git" ]]; then
      echo "vphone-cli: cloning Lakr233/vphone-cli (recurse-submodules) into $SRC" >&2
      git clone --recurse-submodules --depth 1 \
        https://github.com/Lakr233/vphone-cli.git "$SRC"
    fi

    pick_bin() {
      if [[ -x "$BIN_APP" ]]; then echo "$BIN_APP"; return; fi
      if [[ -x "$BIN_REL" ]]; then echo "$BIN_REL"; return; fi
      echo ""
    }

    BIN="$(pick_bin)"
    if [[ -z "$BIN" ]]; then
      echo "vphone-cli: building (scripts/setup_tools.sh + scripts/build.sh)" >&2
      echo "vphone-cli: needs Xcode, network, and tens of GB free for later IPSWs" >&2
      cd "$SRC"
      if [[ ! -x .venv/bin/python3 ]]; then
        ./scripts/setup_tools.sh || {
          echo "vphone-cli: setup_tools.sh failed (brew deps may be missing; nix PATH has substitutes)" >&2
          exit 1
        }
      fi
      ./scripts/build.sh || true
      BIN="$(pick_bin)"
    fi

    if [[ -z "$BIN" || ! -x "$BIN" ]]; then
      echo "vphone-cli: no runnable binary under $SRC/.build" >&2
      exit 1
    fi

    exec "$BIN" "$@"
  '';
}
