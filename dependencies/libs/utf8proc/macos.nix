# utf8proc - Unicode processing library
# https://github.com/JuliaStrings/utf8proc
{
  lib,
  pkgs,
  common,
  buildModule ? null,
}:

let
  fetchSource = common.fetchSource;
  utf8procSource = {
    source = "github";
    owner = "JuliaStrings";
    repo = "utf8proc";
    tag = "v2.9.0";
    sha256 = "sha256-Sgh8vTbclUV+lFZdR29PtNUy8F+9L/OAXk647B+l2mg=";
  };
  src = fetchSource utf8procSource;
in
pkgs.stdenv.mkDerivation {
  pname = "utf8proc";
  version = "2.9.0";
  inherit src;

  nativeBuildInputs = with pkgs; [
    cmake
    ninja
  ];

  cmakeFlags = [
    "-DBUILD_SHARED_LIBS=ON"
    "-DUTF8PROC_ENABLE_TESTING=OFF"
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
  ];
  
  __noChroot = true;

  preConfigure = ''
    export MACOSX_DEPLOYMENT_TARGET="26.0"
    # export NIX_CFLAGS_COMPILE=""
    # export NIX_LDFLAGS=""
  '';

  meta = with lib; {
    description = "Clean C library for processing UTF-8 Unicode data";
    homepage = "https://github.com/JuliaStrings/utf8proc";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}

