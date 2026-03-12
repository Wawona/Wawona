# tllist - Header-only typed linked list library (used by foot terminal)
# https://codeberg.org/dnkl/tllist
{
  lib,
  pkgs,
  common,
  buildModule ? null,
}:

let
  fetchSource = common.fetchSource;
  tllistSource = {
    source = "codeberg";
    owner = "dnkl";
    repo = "tllist";
    tag = "1.1.0";
    sha256 = "sha256-4WW0jGavdFO3LX9wtMPzz3Z1APCPgUQOktpmwAM0SQw=";
  };
  src = fetchSource tllistSource;
in
pkgs.stdenv.mkDerivation {
  pname = "tllist";
  version = "1.1.0";
  inherit src;

  nativeBuildInputs = with pkgs; [
    meson
    ninja
    pkg-config
  ];

  __noChroot = true;

  preConfigure = ''
    export MACOSX_DEPLOYMENT_TARGET="26.0"
    # export NIX_CFLAGS_COMPILE=""
    # export NIX_LDFLAGS=""
  '';

  # tllist is header-only, no special meson flags needed
  mesonFlags = [];

  meta = with lib; {
    description = "Typed linked list C header file only library";
    homepage = "https://codeberg.org/dnkl/tllist";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}

