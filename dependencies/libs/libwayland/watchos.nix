{ lib, pkgs, buildPackages, common, buildModule, simulator ? false, iosToolchain ? null }:

let
  fetchSource = common.fetchSource;
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  waylandSource = {
    source = "gitlab"; owner = "wayland"; repo = "wayland"; tag = "1.23.0";
    sha256 = "sha256-oK0Z8xO2ILuySGZS0m37ZF0MOyle2l8AXb0/6wai0/w=";
  };
  src = fetchSource waylandSource;
  buildFlags = [ "-Dlibraries=true" "-Ddocumentation=false" "-Dtests=false" "-Ddefault_library=static" ];

  getDeps = depNames: map (depName:
    if depName == "expat"   then buildModule.buildForWatchOS "expat"   { inherit simulator; }
    else if depName == "libffi"  then buildModule.buildForWatchOS "libffi"  { inherit simulator; }
    else if depName == "libxml2" then buildModule.buildForWatchOS "libxml2" { inherit simulator; }
    else throw "Unknown dependency: ${depName}"
  ) depNames;
  depInputs = getDeps [ "expat" "libffi" "libxml2" ];
  epollShim = buildModule.buildForWatchOS "epoll-shim" { inherit simulator; };

  sdkName = if simulator then "WatchSimulator" else "WatchOS";
  xcrunSdk = if simulator then "watchsimulator" else "watchos";
  minVerFlag = if simulator then "-mwatchos-simulator-version-min=10.0" else "-mwatchos-version-min=10.0";

  waylandScanner = buildPackages.stdenv.mkDerivation {
    name = "wayland-scanner-host-watchos";
    inherit src;
    nativeBuildInputs = with buildPackages; [ meson ninja pkg-config expat libxml2 ];
    configurePhase = "meson setup build --prefix=$out -Dlibraries=false -Ddocumentation=false -Dtests=false";
    buildPhase = "meson compile -C build wayland-scanner";
    installPhase = ''
      mkdir -p $out/bin $out/share/pkgconfig
      cp $(find build -name wayland-scanner -type f | head -1) $out/bin/wayland-scanner
      cat > $out/share/pkgconfig/wayland-scanner.pc <<EOF
prefix=$out
exec_prefix=$out
bindir=$out/bin
datarootdir=$out/share
pkgdatadir=$out/share/wayland
Name: Wayland Scanner
Description: Wayland scanner
Version: 1.23.0
variable=wayland_scanner
wayland_scanner=$out/bin/wayland-scanner
EOF
    '';
  };
in
pkgs.stdenv.mkDerivation {
  name = "libwayland-watchos";
  inherit src;
  __noChroot = true;
  nativeBuildInputs = with buildPackages; [
    meson ninja pkg-config
    (python3.withPackages (ps: with ps; [ setuptools pip packaging mako pyyaml ]))
    bison flex waylandScanner
  ];
  buildInputs = depInputs ++ [ epollShim ];

  postPatch = ''
    sed -i '1i\
#ifndef MSG_NOSIGNAL\
#define MSG_NOSIGNAL 0\
#endif\
#ifndef MSG_DONTWAIT\
#define MSG_DONTWAIT 0x80\
#endif\
#include <sys/socket.h>\
#ifndef AF_LOCAL\
#define AF_LOCAL AF_UNIX\
#endif\
#ifndef CMSG_LEN\
#define CMSG_LEN(len) (CMSG_DATA((struct cmsghdr *)0) - (unsigned char *)0 + (len))\
#endif\
' src/connection.c
    sed -i '1i\
#include <sys/socket.h>\
#ifndef AF_LOCAL\
#define AF_LOCAL AF_UNIX\
#endif\
' src/wayland-client.c
    sed -i '1i\
#ifndef SOCK_CLOEXEC\
#define SOCK_CLOEXEC 0\
#endif\
#ifndef MSG_CMSG_CLOEXEC\
#define MSG_CMSG_CLOEXEC 0\
#endif\
' src/wayland-os.c
    sed -i '/#error "Don.t know how to read ucred/c\
int wl_os_get_peer_credentials(int sockfd, uid_t *uid, gid_t *gid, pid_t *pid)\
{\
        *uid = 0; *gid = 0; *pid = 0; return 0;\
}\
int wl_os_socket_peercred(int sockfd, uid_t *uid, gid_t *gid, pid_t *pid)\
{\
        return wl_os_get_peer_credentials(sockfd, uid, gid, pid);\
}' src/wayland-os.c
    sed -i '1i\
#if defined(__APPLE__)\
#include <time.h>\
struct itimerspec {\
    struct timespec it_interval;\
    struct timespec it_value;\
};\
#endif\
' src/event-loop.c
    sed -i 's/mkostemp(tmpname, O_CLOEXEC)/mkstemp(tmpname)/' cursor/os-compatibility.c
  '';

  preConfigure = ''
    unset DEVELOPER_DIR
    SDK=$(xcrun --sdk ${xcrunSdk} --show-sdk-path 2>/dev/null || true)
    if [ ! -d "$SDK" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode)
      SDK="$XCODE_APP/Contents/Developer/Platforms/${sdkName}.platform/Developer/SDKs/${sdkName}.sdk"
    fi
    [ -d "$SDK" ] || { echo "ERROR: watchOS SDK not found"; exit 1; }
    export SDKROOT="$SDK"
    export DEVELOPER_DIR=$(echo "$SDK" | sed -E 's|^(.*\.app/Contents/Developer)/.*$|\1|')
    [ "$DEVELOPER_DIR" = "$SDK" ] && DEVELOPER_DIR=$(/usr/bin/xcode-select -p)
    export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
    export NIX_CFLAGS_COMPILE="" NIX_CXXFLAGS_COMPILE="" NIX_LDFLAGS=""
    IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
    IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
    ARCH="arm64"
    cat > watchos-cross-file.txt <<EOF
[binaries]
c = '$IOS_CC'
cpp = '$IOS_CXX'
c_for_build = '${buildPackages.clang}/bin/clang'
cpp_for_build = '${buildPackages.clang}/bin/clang++'
ar = 'ar'
strip = 'strip'
pkgconfig = '${buildPackages.pkg-config}/bin/pkg-config'
[host_machine]
system = 'darwin'
cpu_family = 'aarch64'
cpu = 'arm64'
endian = 'little'
[built-in options]
c_args   = ['-arch','$ARCH','-isysroot','$SDKROOT','${minVerFlag}','-fPIC','-D_DARWIN_C_SOURCE','-I${epollShim}/include/libepoll-shim','-I${epollShim}/include']
cpp_args = ['-arch','$ARCH','-isysroot','$SDKROOT','${minVerFlag}','-fPIC','-D_DARWIN_C_SOURCE','-I${epollShim}/include/libepoll-shim','-I${epollShim}/include']
c_link_args   = ['-arch','$ARCH','-isysroot','$SDKROOT','${minVerFlag}','-L${epollShim}/lib','-lepoll-shim']
cpp_link_args = ['-arch','$ARCH','-isysroot','$SDKROOT','${minVerFlag}','-L${epollShim}/lib','-lepoll-shim']
EOF
    export CFLAGS="-D_DARWIN_C_SOURCE -I${epollShim}/include/libepoll-shim -I${epollShim}/include"
    export LDFLAGS="-L${epollShim}/lib -lepoll-shim"
    export PKG_CONFIG_PATH="${epollShim}/lib/pkgconfig:''${PKG_CONFIG_PATH:-}"
    export PKG_CONFIG_PATH_FOR_BUILD="${waylandScanner}/share/pkgconfig:''${PKG_CONFIG_PATH_FOR_BUILD:-}"
  '';

  configurePhase = ''
    runHook preConfigure
    unset SDKROOT
    meson setup build --prefix=$out --libdir=$out/lib --cross-file=watchos-cross-file.txt ${lib.concatStringsSep " " buildFlags}
    runHook postConfigure
  '';
  buildPhase = ''
    runHook preBuild
    meson compile -C build wayland-client wayland-server wayland-cursor wayland-egl

    # ── Generate XDG shell server protocol (needed by WWNMiniWaylandServer) ──
    # NOTE: SDKROOT was unset in configurePhase for meson compatibility.
    # Re-detect the watchOS SDK here before cross-compiling the XDG glue code.
    XDG_SDK=$(xcrun --sdk ${xcrunSdk} --show-sdk-path 2>/dev/null || true)
    if [ ! -d "$XDG_SDK" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode)
      XDG_SDK="$XCODE_APP/Contents/Developer/Platforms/${sdkName}.platform/Developer/SDKs/${sdkName}.sdk"
    fi
    [ -d "$XDG_SDK" ] || { echo "ERROR: watchOS SDK not found for XDG shell compilation"; exit 1; }
    XDG_DEVDIR=$(echo "$XDG_SDK" | sed -E 's|^(.*\.app/Contents/Developer)/.*$|\1|')
    [ "$XDG_DEVDIR" = "$XDG_SDK" ] && XDG_DEVDIR=$(/usr/bin/xcode-select -p)
    XDG_CC="$XDG_DEVDIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
    XDG_AR="$XDG_DEVDIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ar"

    XDG_XML="${pkgs.wayland-protocols}/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml"
    ${waylandScanner}/bin/wayland-scanner server-header "$XDG_XML" xdg-shell-server-protocol.h
    ${waylandScanner}/bin/wayland-scanner private-code   "$XDG_XML" xdg-shell-protocol.c

    # Compile the protocol glue (defines xdg_wm_base_interface etc.) for watchOS
    "$XDG_CC" -c xdg-shell-protocol.c \
        -I. -I src -I build/src \
        -I${epollShim}/include/libepoll-shim -I${epollShim}/include \
        -isysroot "$XDG_SDK" -arch arm64 ${minVerFlag} \
        -fPIC -D_DARWIN_C_SOURCE \
        -o xdg-shell-protocol.o

    # Merge the glue object into libwayland-server.a
    "$XDG_AR" r build/src/libwayland-server.a xdg-shell-protocol.o

    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib $out/include/wayland $out/lib/pkgconfig
    for f in build/src/libwayland-client.a build/src/libwayland-server.a build/src/libwayland-egl.a build/cursor/libwayland-cursor.a; do
      [ -f "$f" ] && cp "$f" $out/lib/
    done
    for h in src/*.h; do [ -f "$h" ] && cp "$h" $out/include/wayland/; done
    [ -f build/src/wayland-version.h ]          && cp build/src/wayland-version.h $out/include/wayland/
    [ -f build/src/wayland-client-protocol.h ]  && cp build/src/wayland-client-protocol.h $out/include/wayland/
    [ -f build/src/wayland-server-protocol.h ]  && cp build/src/wayland-server-protocol.h $out/include/wayland/
    # XDG shell server protocol header (generated above)
    [ -f xdg-shell-server-protocol.h ]          && cp xdg-shell-server-protocol.h $out/include/wayland/
    for pc in build/src/*.pc build/cursor/*.pc; do [ -f "$pc" ] && cp "$pc" $out/lib/pkgconfig/; done
    if [ ! -f "$out/lib/pkgconfig/wayland-client.pc" ]; then
      cat > $out/lib/pkgconfig/wayland-client.pc <<EOF
prefix=$out
exec_prefix=\''${prefix}
libdir=\''${exec_prefix}/lib
includedir=\''${prefix}/include/wayland
Name: Wayland Client
Description: Wayland client side library (watchOS cross-compiled)
Version: 1.23.0
Cflags: -I\''${includedir}
Libs: -L\''${libdir} -lwayland-client
Libs.private: -lepoll-shim
EOF
    fi
    runHook postInstall
  '';
}
