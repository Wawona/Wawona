{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  androidToolchain,
  ...
}:

let
  hostTag = if pkgs.stdenv.buildPlatform.isLinux then "linux-x86_64" else "darwin-x86_64";
  NDK_SYSROOT = "${androidToolchain.androidndkRoot}/toolchains/llvm/prebuilt/${hostTag}/sysroot";
  NDK_ZLIB_LIB = "${NDK_SYSROOT}/usr/lib/aarch64-linux-android";
in
pkgs.stdenv.mkDerivation {
  name = "openssh-android";

  src = pkgs.fetchurl {
    url = "https://matt.ucc.asn.au/dropbear/releases/dropbear-2025.89.tar.bz2";
    sha256 = "sha256-DR98pxHPwzbcioXmcsq5z9giOgL+LaCkp661jJ4RNjQ=";
  };

  nativeBuildInputs = with buildPackages; [ autoconf automake python3 ];

  postPatch = ''
    # Provide getpass() for Android (Bionic doesn't have it) and
    # add SSHPASS env var support for password auth without a TTY.
    python3 <<'PY'
from pathlib import Path

# Patch cli-auth.c: replace getpass() calls with SSHPASS env var fallback
p = Path("src/cli-auth.c")
if p.exists():
    c = p.read_text()
    if "android_getpass" not in c:
        stub = (
            "\n/* Android: getpass() stub - reads from SSHPASS env var */\n"
            "static char* android_getpass(const char *prompt) {\n"
            "    static char passbuf[256];\n"
            "    const char *env = getenv(\"SSHPASS\");\n"
            "    if (env && env[0]) {\n"
            "        snprintf(passbuf, sizeof(passbuf), \"%s\", env);\n"
            "        return passbuf;\n"
            "    }\n"
            "    /* No SSHPASS set and no TTY - return empty */\n"
            "    fprintf(stderr, \"[dropbear] No SSHPASS env var set for password auth\\n\");\n"
            "    passbuf[0] = 0;\n"
            "    return passbuf;\n"
            "}\n"
        )
        c = c.replace("getpass(prompt)", "android_getpass(prompt)")
        # Insert the stub function before the first function that uses it
        marker = "#include \"includes.h\""
        c = c.replace(marker, marker + stub, 1)
        p.write_text(c)
        print("Patched cli-auth.c with android_getpass")
PY

    # Patch dbclient for -R /path:/path Unix socket forwarding
    # (streamlocal-forward@openssh.com -- required by waypipe ssh)
    bash ${./patch-dbclient-streamlocal.sh}
  '';

  preConfigure = ''
    export CC="${androidToolchain.androidCC}"
    export AR="${androidToolchain.androidAR}"
    export RANLIB="${androidToolchain.androidRANLIB}"
    export STRIP="${androidToolchain.androidSTRIP}"
    export CFLAGS="--target=${androidToolchain.androidTarget} --sysroot=${NDK_SYSROOT} -fPIC -DANDROID ${androidToolchain.androidNdkCflags}"
    export LDFLAGS="--target=${androidToolchain.androidTarget} --sysroot=${NDK_SYSROOT} -L${NDK_ZLIB_LIB} -static"
  '';

  configurePhase = ''
    runHook preConfigure

    # Create localoptions.h to disable server and features we don't need
    cat > localoptions.h <<'EOF'
#undef DROPBEAR_SERVER
#define DROPBEAR_SERVER 0
#undef DROPBEAR_SVR_PASSWORD_AUTH
#define DROPBEAR_SVR_PASSWORD_AUTH 0
#undef DROPBEAR_SFTPSERVER
#define DROPBEAR_SFTPSERVER 0
#define SFTPSERVER_PATH ""
#define DROPBEAR_CLI_REMOTESTREAMFWD 1
EOF

    ac_cv_func_getpass=yes \
    ac_cv_func_logout=no \
    ac_cv_func_logwtmp=no \
    ac_cv_func_pututline=no \
    ac_cv_func_pututxline=no \
    ac_cv_func_updwtmp=no \
    ac_cv_func_updwtmpx=no \
    ./configure \
      --prefix=$out \
      --host=aarch64-linux-android \
      --disable-syslog \
      --disable-utmp \
      --disable-utmpx \
      --disable-wtmp \
      --disable-wtmpx \
      --disable-lastlog \
      --disable-pututline \
      --disable-pututxline \
      --disable-zlib \
      --enable-static
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    make -j$NIX_BUILD_CORES PROGRAMS="dbclient scp" MULTI=0 2>&1 || {
      echo "Full build failed, trying individual targets..."
      make dbclient 2>&1
    }
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    if [ -f dbclient ]; then
      cp dbclient $out/bin/ssh
      chmod +x $out/bin/ssh
      echo "Installed dbclient as ssh"
    fi
    if [ -f scp ]; then
      cp scp $out/bin/scp
      chmod +x $out/bin/scp
    fi
    runHook postInstall
  '';

  dontFixup = true;
}
