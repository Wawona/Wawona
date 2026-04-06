{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  simulator ? false,
  iosToolchain ? null,
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
  # We need to build libraries for the target
  buildFlags = [
    "-Dlibraries=true"
    "-Ddocumentation=false"
    "-Dtests=false"
    "-Ddefault_library=static"
  ];
  patches = [ ];
  getDeps =
    depNames:
    map (
      depName:
      if depName == "expat" then
        buildModule.buildForIOS "expat" { inherit simulator; }
      else if depName == "libffi" then
        buildModule.buildForIOS "libffi" { inherit simulator; }
      else if depName == "libxml2" then
        buildModule.buildForIOS "libxml2" { inherit simulator; }
      else
        throw "Unknown dependency: ${depName}"
    ) depNames;
  depInputs = getDeps [
    "expat"
    "libffi"
    "libxml2"
  ];
  # epoll-shim: Required for iOS Wayland builds (implements epoll on top of kqueue)
  epollShim = buildModule.buildForIOS "epoll-shim" { inherit simulator; };

  # Build wayland-scanner for the build architecture (host)
  waylandScanner = buildPackages.stdenv.mkDerivation {
    name = "wayland-scanner-host";
    inherit src;
    nativeBuildInputs = with buildPackages; [
      meson
      ninja
      pkg-config
      expat
      libxml2
    ];
    configurePhase = ''
      meson setup build \
        --prefix=$out \
        -Dlibraries=false \
        -Ddocumentation=false \
        -Dtests=false
    '';
    buildPhase = ''
      meson compile -C build wayland-scanner
    '';
    installPhase = ''
            mkdir -p $out/bin
            SCANNER_BIN=$(find build -name wayland-scanner -type f | head -n 1)
            if [ -z "$SCANNER_BIN" ]; then
              echo "Error: wayland-scanner binary not found"
              exit 1
            fi
            cp "$SCANNER_BIN" $out/bin/wayland-scanner
            
            mkdir -p $out/share/pkgconfig
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
  name = "libwayland-ios";
  inherit src patches;
  
  # Allow access to Xcode SDKs and toolchain
  __noChroot = true;
  nativeBuildInputs = with buildPackages; [
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
    waylandScanner
  ];

  buildInputs = depInputs ++ [ epollShim ];

  postPatch = ''
        # iOS syscall compatibility
        echo "=== Applying iOS syscall compatibility patches ==="
        
        # Fix missing socket defines on iOS/Darwin (CMSG_LEN, MSG_NOSIGNAL, MSG_DONTWAIT)
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

        # Fix AF_LOCAL in wayland-client.c
        sed -i '1i\
    #include <sys/socket.h>\
    #ifndef AF_LOCAL\
    #define AF_LOCAL AF_UNIX\
    #endif\
    ' src/wayland-client.c

        # Fix wayland-os.c for Darwin (SOCK_CLOEXEC, MSG_CMSG_CLOEXEC, ucred)
        sed -i '1i\
    #ifndef SOCK_CLOEXEC\
    #define SOCK_CLOEXEC 0\
    #endif\
    #ifndef MSG_CMSG_CLOEXEC\
    #define MSG_CMSG_CLOEXEC 0\
    #endif\
    ' src/wayland-os.c

        # Patch ucred error in wayland-os.c to support Darwin via stub
        # The #error guards the function definition, so we must provide the function definition
        # Also provide wl_os_socket_peercred which seems to be used by wayland-server.c
        sed -i '/#error "Don.t know how to read ucred/c\
    int wl_os_get_peer_credentials(int sockfd, uid_t *uid, gid_t *gid, pid_t *pid)\
    {\
            *uid = 0; *gid = 0; *pid = 0; return 0;\
    }\
    int wl_os_socket_peercred(int sockfd, uid_t *uid, gid_t *gid, pid_t *pid)\
    {\
            return wl_os_get_peer_credentials(sockfd, uid, gid, pid);\
    }' src/wayland-os.c

        # Fix missing struct itimerspec on Darwin (needed by event-loop.c)
        sed -i '1i\
    #if defined(__APPLE__)\
    #include <time.h>\
    struct itimerspec {\
        struct timespec it_interval;\
        struct timespec it_value;\
    };\
    #endif\
    ' src/event-loop.c

        # Fix mkostemp in os-compatibility.c
        sed -i 's/mkostemp(tmpname, O_CLOEXEC)/mkstemp(tmpname)/' cursor/os-compatibility.c
        
        echo "Applied iOS syscall compatibility patches"
  '';

  preConfigure = ''
    # Strip Nix stdenv's DEVELOPER_DIR to bypass any store fallbacks
    unset DEVELOPER_DIR

    ${if simulator then ''
      # Robust SDK detection for iOS Simulator
      IOS_SDK=$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null || true)
      if [ ! -d "$IOS_SDK" ]; then
        # Fallback 1: via ensureIosSimSDK script
        IOS_SDK=$(${xcodeUtils.ensureIosSimSDK}/bin/ensure-ios-sim-sdk) || true
      fi
      if [ ! -d "$IOS_SDK" ]; then
        # Fallback 2: Default location
        XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode)
        IOS_SDK="$XCODE_APP/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
      fi
    '' else ''
      # Robust SDK detection for iOS Device
      IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)
      if [ ! -d "$IOS_SDK" ]; then
        # Fallback 1: Default location
        XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode)
        IOS_SDK="$XCODE_APP/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
      fi
    ''}

    if [ ! -d "$IOS_SDK" ]; then
      echo "ERROR: iOS SDK not found. Build cannot proceed." >&2
      exit 1
    fi
    export SDKROOT="$IOS_SDK"
    export IOS_SDK

    # Find the Developer dir associated with this SDK
    # Use sed instead of grep -oP for macOS compatibility
    export DEVELOPER_DIR=$(echo "$IOS_SDK" | sed -E 's|^(.*\.app/Contents/Developer)/.*$|\1|')
    [ "$DEVELOPER_DIR" = "$IOS_SDK" ] && DEVELOPER_DIR=$(/usr/bin/xcode-select -p)
    export PATH="$DEVELOPER_DIR/usr/bin:$PATH"

    echo "Using iOS SDK: $IOS_SDK"
    echo "Using Developer Dir: $DEVELOPER_DIR"
    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""
    export NIX_LDFLAGS=""
        
        if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
          IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
          IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
        else
          IOS_CC="${buildPackages.clang}/bin/clang"
          IOS_CXX="${buildPackages.clang}/bin/clang++"
        fi
        
        EPOL_SHIM_PATH="${epollShim}"
        
        export CFLAGS="-D_DARWIN_C_SOURCE -I$EPOL_SHIM_PATH/include/libepoll-shim -I$EPOL_SHIM_PATH/include ''${NIX_CFLAGS_COMPILE:-}"
        export LDFLAGS="-L$EPOL_SHIM_PATH/lib -lepoll-shim ''${NIX_LDFLAGS:-}"
        export PKG_CONFIG_PATH="$EPOL_SHIM_PATH/lib/pkgconfig:''${PKG_CONFIG_PATH:-}"
        export PKG_CONFIG_PATH_FOR_BUILD="${waylandScanner}/share/pkgconfig:''${PKG_CONFIG_PATH_FOR_BUILD:-}"
        
        IOS_ARCH="${if simulator then pkgs.stdenv.hostPlatform.darwinArch else "arm64"}"
        IOS_CPU_FAMILY="${if simulator && pkgs.stdenv.hostPlatform.darwinArch == "x86_64" then "x86_64" else "aarch64"}"
        
        cat > ios-cross-file.txt <<EOF
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
    cpu_family = '$IOS_CPU_FAMILY'
    cpu = '$IOS_ARCH'
    endian = 'little'

    [built-in options]
    c_args = ['-arch', '$IOS_ARCH', '-isysroot', '$SDKROOT', '-m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0', '-fPIC', '-D_DARWIN_C_SOURCE', '-I$EPOL_SHIM_PATH/include/libepoll-shim', '-I$EPOL_SHIM_PATH/include']
    cpp_args = ['-arch', '$IOS_ARCH', '-isysroot', '$SDKROOT', '-m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0', '-fPIC', '-D_DARWIN_C_SOURCE', '-I$EPOL_SHIM_PATH/include/libepoll-shim', '-I$EPOL_SHIM_PATH/include']
    c_link_args = ['-arch', '$IOS_ARCH', '-isysroot', '$SDKROOT', '-m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0', '-L$EPOL_SHIM_PATH/lib', '-lepoll-shim']
    cpp_link_args = ['-arch', '$IOS_ARCH', '-isysroot', '$SDKROOT', '-m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0', '-L$EPOL_SHIM_PATH/lib', '-lepoll-shim']
    EOF
  '';

  configurePhase = ''
    runHook preConfigure
    # Unset SDKROOT so it doesn't leak into host-side tool builds
    unset SDKROOT
    echo "Configured epoll-shim paths for iOS: $EPOL_SHIM_PATH"
    meson setup build \
      --prefix=$out \
      --libdir=$out/lib \
      --cross-file=ios-cross-file.txt \
      ${lib.concatMapStringsSep " \\\n  " (flag: flag) buildFlags}
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    meson compile -C build \
      wayland-client \
      wayland-server \
      wayland-cursor \
      wayland-egl
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib $out/include/wayland $out/lib/pkgconfig

    # Install static libraries without rebuilding wayland-scanner.
    for libpath in \
      build/src/libwayland-client.a \
      build/src/libwayland-server.a \
      build/src/libwayland-egl.a \
      build/cursor/libwayland-cursor.a; do
      if [ -f "$libpath" ]; then
        cp "$libpath" $out/lib/
      fi
    done

    # Install public headers.
    for header in src/*.h; do
      if [ -f "$header" ]; then
        cp "$header" $out/include/wayland/
      fi
    done
    if [ -f build/src/wayland-version.h ]; then
      cp build/src/wayland-version.h $out/include/wayland/
    fi
    if [ -f build/src/wayland-client-protocol.h ]; then
      cp build/src/wayland-client-protocol.h $out/include/wayland/
    fi
    if [ -f build/src/wayland-server-protocol.h ]; then
      cp build/src/wayland-server-protocol.h $out/include/wayland/
    fi

    # Install pkg-config files used by consumers like wayland-sys.
    # Meson may not generate .pc files during cross-compilation, so we create
    # them manually if missing.
    for pcfile in build/src/*.pc build/cursor/*.pc; do
      if [ -f "$pcfile" ]; then
        cp "$pcfile" $out/lib/pkgconfig/
      fi
    done

    # Ensure wayland-client.pc exists (required by wayland-sys Rust crate)
    if [ ! -f "$out/lib/pkgconfig/wayland-client.pc" ]; then
      cat > $out/lib/pkgconfig/wayland-client.pc <<EOF
prefix=$out
exec_prefix=\''${prefix}
libdir=\''${exec_prefix}/lib
includedir=\''${prefix}/include/wayland

Name: Wayland Client
Description: Wayland client side library (iOS cross-compiled)
Version: 1.23.0
Cflags: -I\''${includedir}
Libs: -L\''${libdir} -lwayland-client
Libs.private: -lepoll-shim
EOF
      echo "Generated wayland-client.pc"
    fi

    if [ ! -f "$out/lib/pkgconfig/wayland-server.pc" ]; then
      cat > $out/lib/pkgconfig/wayland-server.pc <<EOF
prefix=$out
exec_prefix=\''${prefix}
libdir=\''${exec_prefix}/lib
includedir=\''${prefix}/include/wayland

Name: Wayland Server
Description: Wayland server side library (iOS cross-compiled)
Version: 1.23.0
Cflags: -I\''${includedir}
Libs: -L\''${libdir} -lwayland-server
Libs.private: -lepoll-shim
EOF
      echo "Generated wayland-server.pc"
    fi

    if [ ! -f "$out/lib/pkgconfig/wayland-cursor.pc" ]; then
      cat > $out/lib/pkgconfig/wayland-cursor.pc <<EOF
prefix=$out
exec_prefix=\''${prefix}
libdir=\''${exec_prefix}/lib
includedir=\''${prefix}/include/wayland

Name: Wayland Cursor
Description: Wayland cursor library (iOS cross-compiled)
Version: 1.23.0
Cflags: -I\''${includedir}
Libs: -L\''${libdir} -lwayland-cursor
EOF
      echo "Generated wayland-cursor.pc"
    fi

    runHook postInstall
  '';
}
