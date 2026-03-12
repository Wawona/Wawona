{
  lib,
  pkgs,
  common,
  buildModule,
}:

let
  fetchSource = common.fetchSource;
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  waylandSource = {
    source = "gitlab";
    owner = "wayland";
    repo = "wayland";
    tag = "1.23.0";
    sha256 = "sha256-oK0Z8xO2ILuySGZS0m37ZF0MOyle2l8AXb0/6wai0/w=";
  };
  src = fetchSource waylandSource;
  buildFlags = [
    "-Dlibraries=true"
    "-Ddocumentation=false"
    "-Dtests=false"
  ];
  patches = [ ];
  getDeps =
    depNames:
    map (
      depName:
      if depName == "expat" then
        buildModule.buildForMacOS "expat" { }
      else if depName == "libffi" then
        buildModule.buildForMacOS "libffi" { }
      else if depName == "libxml2" then
        buildModule.buildForMacOS "libxml2" { }
      else
        throw "Unknown dependency: ${depName}"
    ) depNames;
  depInputs = getDeps [
    "expat"
    "libffi"
    "libxml2"
  ];
  # epoll-shim: Required for macOS Wayland builds (implements epoll on top of kqueue)
  epollShim = buildModule.buildForMacOS "epoll-shim" { };
in
pkgs.stdenv.mkDerivation {
  name = "libwayland-macos";
  inherit src patches;
  __noChroot = true;
  nativeBuildInputs = with pkgs; [
    meson
    ninja
    pkg-config
    (python3.withPackages (
      ps: with ps; [
        setuptools
        pip
        packaging
        mako
        pyyaml
      ]
    ))
    bison
    flex
  ];
  buildInputs = depInputs ++ [ epollShim ];

  postPatch = ''
        # Fix missing socket defines and types on macOS/Darwin
        # - _DARWIN_C_SOURCE: Enables u_int, etc.
        # - sys/types.h: Must be included before sys/ucred.h for u_int
        # - SOCK_CLOEXEC, MSG_CMSG_CLOEXEC: Not supported on macOS, define to 0
        # - MSG_NOSIGNAL, MSG_DONTWAIT: Not supported on macOS, define to 0/appropriate value
        # - CMSG_LEN: Macro missing on some macOS SDK versions / standards modes
        
        COMMON_DEFINES=$(cat <<EOF
    #define _DARWIN_C_SOURCE
    #include <sys/types.h>
    #include <sys/socket.h>
    #include <sys/un.h>
    #include <time.h>
    #ifndef MSG_NOSIGNAL
    #define MSG_NOSIGNAL 0
    #endif
    #ifndef MSG_DONTWAIT
    #define MSG_DONTWAIT 0x80
    #endif
    #ifndef AF_LOCAL
    #define AF_LOCAL AF_UNIX
    #endif
    #ifndef SOCK_CLOEXEC
    #define SOCK_CLOEXEC 0
    #endif
    #ifndef MSG_CMSG_CLOEXEC
    #define MSG_CMSG_CLOEXEC 0
    #endif
    #ifndef CMSG_LEN
    #define CMSG_LEN(len) (CMSG_DATA((struct cmsghdr *)0) - (unsigned char *)0 + (len))
    #endif
    #ifndef MAP_ANONYMOUS
    #define MAP_ANONYMOUS MAP_ANON
    #endif
    #ifndef mkostemp
    #define mkostemp(template, flags) mkstemp(template)
    #endif
    #ifndef _STRUCT_ITIMERSPEC
    struct itimerspec {
        struct timespec it_interval;
        struct timespec it_value;
    };
    #endif
    EOF
    )
        
        for f in src/connection.c src/wayland-os.c src/wayland-client.c src/wayland-server.c src/wayland-shm.c cursor/os-compatibility.c src/event-loop.c; do
          if [ -f "$f" ]; then
            # Insert defines at the top
            echo "$COMMON_DEFINES" | cat - "$f" > "$f.tmp" && mv "$f.tmp" "$f"
          fi
        done

        # Patch meson.build: librt does not exist on macOS (it's part of libSystem).
        # Make it optional so the build doesn't fail.
        if [ -f meson.build ]; then
          substituteInPlace meson.build --replace "find_library('rt')" "find_library('rt', required: false)"
        fi
        
        if [ -f src/wayland-os.c ]; then
          # Replace the #error directive with macOS implementation for get_credentials
          # This assumes wl_os_socket_peercred(int sockfd, ...) signature
          # Wraps in function definition because the #error is likely at global scope (platform-specific function def)
          substituteInPlace src/wayland-os.c \
            --replace '#error "Don'\'''t know how to read ucred on this platform"' \
    '/* macOS implementation injected by Nix */
    int wl_os_socket_peercred(int sockfd, uid_t *uid, gid_t *gid, pid_t *pid)
    {
        socklen_t len = sizeof(struct xucred);
        struct xucred cr;
        if (getsockopt(sockfd, SOL_LOCAL, LOCAL_PEERCRED, &cr, &len) < 0) return -1;
        *uid = cr.cr_uid;
        *gid = cr.cr_gid;
        *pid = 0;
        #ifdef LOCAL_PEERPID
        pid_t p;
        len = sizeof(p);
        if (getsockopt(sockfd, SOL_LOCAL, LOCAL_PEERPID, &p, &len) == 0) *pid = p;
        #endif
        return 0;
    }'
        fi
  '';

  MACOS_SDK = "/System/Library/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
  preConfigure = ''
    # Fallback if preferred SDK path doesn't exist
    if [ ! -d "$MACOS_SDK" ]; then
      MACOS_SDK=$(${xcodeUtils.findXcodeScript}/bin/find-xcode)/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
    fi
    if [ ! -d "$MACOS_SDK" ]; then
      MACOS_SDK=$(/usr/bin/xcode-select -p)/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
    fi
    export SDKROOT="$MACOS_SDK"
    export MACOSX_DEPLOYMENT_TARGET="26.0"

    # Isolate environment from Nix wrapper flags to prevent linker conflicts
    export CC="${pkgs.clang}/bin/clang"
    export CXX="${pkgs.clang}/bin/clang++"
    # export NIX_CFLAGS_COMPILE=""
    # export NIX_LDFLAGS=""

    # Add sysroot and version-min explicitly
    export CFLAGS="-isysroot $SDKROOT -mmacosx-version-min=26.0 -fPIC $CFLAGS -I${epollShim}/include/libepoll-shim"
    export LDFLAGS="-isysroot $SDKROOT -mmacosx-version-min=26.0 $LDFLAGS -L${epollShim}/lib -lepoll-shim"
  '';

  configurePhase = ''
    runHook preConfigure

    # Use standard Meson configure
    meson setup build \
      --prefix=$out \
      --buildtype=release \
      ${lib.concatMapStringsSep " " (flag: flag) buildFlags} \
      -Dc_args="$CFLAGS" \
      -Dc_link_args="$LDFLAGS"
      
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    ninja -C build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    ninja -C build install
    runHook postInstall
  '';
}
