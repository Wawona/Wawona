# Shared -L/-l block for Apple mobile app targets (SSH/crypto/zlib stack).
{ lib, deps }:
let
  strip = d: if d == null then "" else toString d;
in
[
  "-L${strip (deps.libssh2 or null)}/lib"
  "-L${strip (deps.mbedtls or null)}/lib"
  "-L${strip (deps.openssl or null)}/lib"
  "-lz"
  "-lssh2"
  "-lmbedcrypto"
  "-lmbedx509"
  "-lmbedtls"
  "-lssl"
  "-lcrypto"
]
