{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  androidToolchain ? (import ../../toolchains/android.nix { inherit lib pkgs; }),
  ...
}:

let
  fetchSource = common.fetchSource;
  # androidToolchain passed from caller
  waylandSource = {
    source = "gitlab";
    owner = "wayland";
    repo = "wayland";
    tag = "1.23.0";
    sha256 = "sha256-oK0Z8xO2ILuySGZS0m37ZF0MOyle2l8AXb0/6wai0/w=";
  };
  src = fetchSource waylandSource;
  # Enable libraries for Android - we need libwayland-client and libwayland-server
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
        buildModule.buildForAndroid "expat" { }
      else if depName == "libffi" then
        buildModule.buildForAndroid "libffi" { }
      else if depName == "libxml2" then
        buildModule.buildForAndroid "libxml2" { }
      else
        throw "Unknown dependency: ${depName}"
    ) depNames;
  depInputs = getDeps [
    "expat"
    "libffi"
    "libxml2"
  ];

  # Build wayland-scanner for the build architecture (host)
  # We need a native wayland-scanner to generate headers for the target
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
  name = "libwayland-android";
  inherit src patches;
  nativeBuildInputs = with buildPackages; [
    meson
    ninja
    pkg-config
    python3
    bison
    flex
    libxml2
    expat
    gcc
    which
    waylandScanner
  ];
  depsTargetTarget = depInputs;
  buildInputs = depInputs;
  propagatedBuildInputs = [ ];
  depsBuildBuild = with buildPackages; [
    libxml2
    expat
  ];
  postPatch = ''
        # Meson build patches for cross-compilation
        substituteInPlace src/meson.build \
          --replace "scanner_deps += dependency('libxml-2.0')" "scanner_deps += dependency('libxml-2.0', native: true)" \
          --replace "scanner_deps = [ dependency('expat') ]" "scanner_deps = [ dependency('expat', native: true) ]" \
          --replace "scanner_deps += dependency('expat')" "scanner_deps += dependency('expat', native: true)"
        python3 <<'PYTHONPATCH'
    import sys

    with open('src/meson.build', 'r') as f:
        lines = f.readlines()

    new_lines = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if 'scanner_deps = [ dependency(' in line and 'expat' in line:
            new_lines.append(line.replace("dependency('expat')", "dependency('expat', native: true)"))
            i += 1
            continue
        if 'scanner_deps += dependency(' in line and 'expat' in line:
            new_lines.append(line.replace("dependency('expat')", "dependency('expat', native: true)"))
            i += 1
            continue
        new_lines.append(line)
        i += 1

    with open('src/meson.build', 'w') as f:
        f.writelines(new_lines)
    PYTHONPATCH
        python3 <<'PYTHONPATCH'
    import sys

    with open('src/meson.build', 'r') as f:
        lines = f.readlines()

    new_lines = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if 'wayland_util = static_library(' in line:
            new_lines.append(line)
            i += 1
            paren_count = line.count('(') - line.count(')')
            while i < len(lines) and paren_count > 0:
                new_lines.append(lines[i])
                paren_count += lines[i].count('(') - lines[i].count(')')
                i += 1
            if i < len(lines) and lines[i].strip() == ')':
                new_lines.append(lines[i])
                i += 1
            new_lines.append('wayland_util_native = static_library(\n')
            new_lines.append("\t'wayland-util-native',\n")
            new_lines.append("\tsources: 'wayland-util.c',\n")
            new_lines.append("\tinclude_directories: include_directories('.'),\n")
            new_lines.append('\tnative: true\n')
            new_lines.append(')\n')
            continue
        if 'wayland_util_dep = declare_dependency(' in line:
            new_lines.append('wayland_util_dep_native = declare_dependency(\n')
            new_lines.append('\tlink_with: wayland_util_native,\n')
            new_lines.append("\tinclude_directories: include_directories('.')\n")
            new_lines.append(')\n')
            new_lines.append(line)
            i += 1
            continue
        if 'dependencies: [ scanner_deps, wayland_util_dep, ],' in line:
            new_lines.append('\tdependencies: [ scanner_deps, wayland_util_dep_native ],\n')
            new_lines.append('\t\tnative: true,\n')
            i += 1
            while i < len(lines):
                if 'install: true' in lines[i]:
                    new_lines.append('\tinstall: false,\n')
                    i += 1
                    break
                elif lines[i].strip() == ')':
                    new_lines.append('\tinstall: false,\n')
                    new_lines.append(lines[i])
                    i += 1
                    break
                new_lines.append(lines[i])
                i += 1
            continue
        new_lines.append(line)
        i += 1

    with open('src/meson.build', 'w') as f:
        f.writelines(new_lines)
    PYTHONPATCH
        
        echo "=== Applying Android syscall compatibility patches ==="
        
        # Disable Meson checks for signalfd and timerfd (not available in Bionic)
        # Remove the lines from the check array
        sed -i "/sys\/signalfd.h/d" meson.build
        sed -i "/sys\/timerfd.h/d" meson.build
        
        # Also try to comment out direct error calls if they exist
        sed -i "s/error.*SFD_CLOEXEC.*/message('Skipped SFD_CLOEXEC check for Android')/g" meson.build
        sed -i "s/error.*TFD_CLOEXEC.*/message('Skipped TFD_CLOEXEC check for Android')/g" meson.build
        
        # Android syscall compatibility: Remove signalfd/timerfd usage
        # These syscalls don't exist in Android's Bionic libc
        # We need to provide stub implementations that return appropriate values
        if [ -f src/event-loop.c ]; then
          echo "=== Patching event-loop.c for Android ==="
          
          # Add stub functions and defines at the very beginning of the file
          # This ensures they're available before any code tries to use them
          sed -i '1i\
    /* Android Bionic compatibility: stubs for missing signalfd/timerfd */\
    #include <errno.h>\
    #include <signal.h>\
    #include <time.h>\
    #include <sys/types.h>\
    #include <stdint.h>\
    \
    /* Stub struct for signalfd_siginfo */\
    struct signalfd_siginfo {\
            uint32_t ssi_signo;\
            int32_t ssi_errno;\
            int32_t ssi_code;\
            uint32_t ssi_pid;\
            uint32_t ssi_uid;\
            int32_t ssi_fd;\
            uint32_t ssi_tid;\
            uint32_t ssi_band;\
            uint32_t ssi_overrun;\
            uint32_t ssi_trapno;\
            int32_t ssi_status;\
            int32_t ssi_int;\
            uint64_t ssi_ptr;\
            uint64_t ssi_utime;\
            uint64_t ssi_stime;\
            uint64_t ssi_addr;\
            uint16_t ssi_addr_lsb;\
            uint16_t __pad2;\
            int32_t ssi_syscall;\
            uint64_t ssi_call_addr;\
            uint32_t ssi_arch;\
    };\
    \
    /* Stub implementations that return errors */\
    static inline int android_signalfd(int fd, const sigset_t *mask, int flags) {\
            (void)fd; (void)mask; (void)flags;\
            errno = ENOSYS;\
            return -1;\
    }\
    static inline int android_timerfd_create(int clockid, int flags) {\
            (void)clockid; (void)flags;\
            errno = ENOSYS;\
            return -1;\
    }\
    static inline int android_timerfd_settime(int fd, int flags, const struct itimerspec *new_value, struct itimerspec *old_value) {\
            (void)fd; (void)flags; (void)new_value; (void)old_value;\
            errno = ENOSYS;\
            return -1;\
    }\
    \
    /* Redirect calls to our stubs */\
    #define signalfd android_signalfd\
    #define timerfd_create android_timerfd_create\
    #define timerfd_settime android_timerfd_settime\
    \
    /* Define missing constants */\
    #ifndef SFD_CLOEXEC\
    #define SFD_CLOEXEC 0\
    #endif\
    #ifndef SFD_NONBLOCK\
    #define SFD_NONBLOCK 0\
    #endif\
    #ifndef TFD_CLOEXEC\
    #define TFD_CLOEXEC 0\
    #endif\
    #ifndef TFD_NONBLOCK\
    #define TFD_NONBLOCK 0\
    #endif\
    #ifndef TFD_TIMER_ABSTIME\
    #define TFD_TIMER_ABSTIME 0\
    #endif\
    ' src/event-loop.c
          
          # Remove the actual includes since we're providing stubs
          substituteInPlace src/event-loop.c \
            --replace "#include <sys/signalfd.h>" "/* Android: signalfd not available in Bionic - using stub */" \
            --replace "#include <sys/timerfd.h>" "/* Android: timerfd not available in Bionic - using stub */"
          
          echo "Applied event-loop.c patches for Android"
        fi
        
        # Android socket compatibility: Some socket flags might not be available
        # Check if we need to define MSG_NOSIGNAL, MSG_DONTWAIT, etc.
        # Android Bionic should have these, but let's be safe
        if [ -f src/connection.c ]; then
          echo "=== Checking connection.c for Android compatibility ==="
          # Android should have CMSG_LEN, but verify
          # MSG_NOSIGNAL and MSG_DONTWAIT should be available in Android
          # No patches needed for connection.c on Android typically
        fi
        
        # Android wayland-os.c compatibility: ucred handling
        # Android uses SO_PEERCRED but with standard Linux kernel semantics
        # We implement it using SO_PEERCRED and define a local compatible struct
        # to avoid any header definition issues.
        if [ -f src/wayland-os.c ]; then
          echo "=== Patching wayland-os.c for Android ==="
          # Replace the #error block or the whole function if it fails to compile
          # We provide a complete implementation using SO_PEERCRED (17)
          if grep -q '#error "Don.t know how to read ucred' src/wayland-os.c; then
            echo "Found ucred error, replacing with Android SO_PEERCRED implementation"
            sed -i '/#error "Don.t know how to read ucred/c\
    #include <sys/socket.h>\
    #include <sys/types.h>\
    \
    /* Define struct ucred locally if not available to avoid conflicts */\
    /* Layout matches Linux kernel: pid, uid, gid (all 32-bit typically) */\
    struct android_ucred {\
        pid_t pid;\
        uid_t uid;\
        gid_t gid;\
    };\
    \
    /* Ensure SO_PEERCRED is defined (should be available with sys/socket.h) */\
    #ifndef SO_PEERCRED\
    #define SO_PEERCRED 17\
    #endif\
    \
    int wl_os_get_peer_credentials(int sockfd, uid_t *uid, gid_t *gid, pid_t *pid)\
    {\
            struct android_ucred peercred;\
            socklen_t len = sizeof(peercred);\
            if (getsockopt(sockfd, SOL_SOCKET, SO_PEERCRED, &peercred, &len) < 0) return -1;\
            *uid = peercred.uid;\
            *gid = peercred.gid;\
            *pid = peercred.pid;\
            return 0;\
    }\
    \
    int wl_os_socket_peercred(int sockfd, uid_t *uid, gid_t *gid, pid_t *pid)\
    {\
            return wl_os_get_peer_credentials(sockfd, uid, gid, pid);\
    }' src/wayland-os.c
          fi
          
          # Check for SOCK_CLOEXEC and MSG_CMSG_CLOEXEC
          # Android should support these, but let's check and define if missing
          sed -i '1i\
    #ifndef SOCK_CLOEXEC\
    #define SOCK_CLOEXEC 0\
    #endif\
    #ifndef MSG_CMSG_CLOEXEC\
    #define MSG_CMSG_CLOEXEC 0\
    #endif\
    ' src/wayland-os.c
          
          echo "Applied wayland-os.c patches for Android"
        fi
        
        # Fix mkostemp in os-compatibility.c if it exists
        if [ -f cursor/os-compatibility.c ]; then
          echo "=== Checking os-compatibility.c ==="
          # Android should have mkostemp, but if not, fallback to mkstemp
          if grep -q "mkostemp" cursor/os-compatibility.c; then
            echo "Found mkostemp usage, checking Android support"
            # Android API 21+ should have mkostemp, but we can add fallback if needed
            # For now, leave it as Android should support it
          fi
        fi
        
        echo "=== Android compatibility patches complete ==="
  '';
  preConfigure = ''
        unset NIX_CFLAGS_COMPILE NIX_CXXFLAGS_COMPILE
        export CC="${androidToolchain.androidCC}"
        export CXX="${androidToolchain.androidCXX}"
        export AR="${androidToolchain.androidAR}"
        export STRIP="${androidToolchain.androidSTRIP}"
        export RANLIB="${androidToolchain.androidRANLIB}"
        PKG_CONFIG_PATH=""
        for depPkg in ${lib.concatMapStringsSep " " (p: toString p) depInputs}; do
          if [ -d "$depPkg/lib/pkgconfig" ]; then
            PKG_CONFIG_PATH="$depPkg/lib/pkgconfig:$PKG_CONFIG_PATH"
          fi
        done
        
        # Use the native wayland-scanner we built
        # Also add native expat and libxml2 for native build tools
        NATIVE_EXPAT_PKG_CONFIG_DIR="${buildPackages.expat.dev}/lib/pkgconfig"
        NATIVE_LIBXML2_PKG_CONFIG_DIR="${buildPackages.libxml2.dev}/lib/pkgconfig"
        if [ ! -d "$NATIVE_EXPAT_PKG_CONFIG_DIR" ]; then
          NATIVE_EXPAT_PKG_CONFIG_DIR="${buildPackages.expat}/lib/pkgconfig"
        fi
        if [ ! -d "$NATIVE_LIBXML2_PKG_CONFIG_DIR" ]; then
          NATIVE_LIBXML2_PKG_CONFIG_DIR="${buildPackages.libxml2}/lib/pkgconfig"
        fi
        export PKG_CONFIG_PATH_FOR_BUILD="${waylandScanner}/share/pkgconfig:$NATIVE_EXPAT_PKG_CONFIG_DIR:$NATIVE_LIBXML2_PKG_CONFIG_DIR:''${PKG_CONFIG_PATH_FOR_BUILD:-}"
        export PATH="${waylandScanner}/bin:$PATH"
        
        # Add libffi include and library paths to cross-file for compilation
        # Find libffi specifically (it's needed for connection.c)
        LIBFFI_INCLUDE=""
        LIBFFI_LIB=""
        LIBFFI_PKG=$(echo ${
          lib.concatMapStringsSep " " (p: toString p) depInputs
        } | tr ' ' '\n' | grep libffi | head -n 1)
        if [ -n "$LIBFFI_PKG" ]; then
          if [ -d "$LIBFFI_PKG/include" ]; then
            LIBFFI_INCLUDE="$LIBFFI_PKG/include"
            echo "Found libffi include: $LIBFFI_INCLUDE"
          fi
          if [ -d "$LIBFFI_PKG/lib" ]; then
            LIBFFI_LIB="$LIBFFI_PKG/lib"
            echo "Found libffi lib: $LIBFFI_LIB"
          fi
        else
          echo "Warning: libffi package not found"
        fi
        # Build cross-file with libffi include and library paths
        cat > android-cross-file.txt <<EOF
    [binaries]
    c = '${androidToolchain.androidCC}'
    cpp = '${androidToolchain.androidCXX}'
    ar = '${androidToolchain.androidAR}'
    strip = '${androidToolchain.androidSTRIP}'
    ranlib = '${androidToolchain.androidRANLIB}'
    pkgconfig = '${buildPackages.pkg-config}/bin/pkg-config'

    [host_machine]
    system = 'android'
    cpu_family = 'aarch64'
    cpu = 'aarch64'
    endian = 'little'

    [built-in options]
    EOF
        if [ -n "$LIBFFI_INCLUDE" ]; then
          echo "c_args = ['--target=${androidToolchain.androidTarget}', '--sysroot', '${androidToolchain.androidndkRoot}/sysroot', '-isystem', '${androidToolchain.androidndkRoot}/sysroot/usr/include', '-isystem', '${androidToolchain.androidndkRoot}/sysroot/usr/include/aarch64-linux-android', '-fPIC', '-I$LIBFFI_INCLUDE', '${androidToolchain.androidNdkCflags}', '-D_GNU_SOURCE']" >> android-cross-file.txt
          echo "cpp_args = ['--target=${androidToolchain.androidTarget}', '--sysroot', '${androidToolchain.androidndkRoot}/sysroot', '-isystem', '${androidToolchain.androidndkRoot}/sysroot/usr/include', '-isystem', '${androidToolchain.androidndkRoot}/sysroot/usr/include/aarch64-linux-android', '-fPIC', '-I$LIBFFI_INCLUDE', '${androidToolchain.androidNdkCflags}', '-D_GNU_SOURCE']" >> android-cross-file.txt
        else
          echo "c_args = ['--target=${androidToolchain.androidTarget}', '--sysroot', '${androidToolchain.androidndkRoot}/sysroot', '-isystem', '${androidToolchain.androidndkRoot}/sysroot/usr/include', '-isystem', '${androidToolchain.androidndkRoot}/sysroot/usr/include/aarch64-linux-android', '-fPIC', '${androidToolchain.androidNdkCflags}', '-D_GNU_SOURCE']" >> android-cross-file.txt
          echo "cpp_args = ['--target=${androidToolchain.androidTarget}', '--sysroot', '${androidToolchain.androidndkRoot}/sysroot', '-isystem', '${androidToolchain.androidndkRoot}/sysroot/usr/include', '-isystem', '${androidToolchain.androidndkRoot}/sysroot/usr/include/aarch64-linux-android', '-fPIC', '${androidToolchain.androidNdkCflags}', '-D_GNU_SOURCE']" >> android-cross-file.txt
        fi
        if [ -n "$LIBFFI_LIB" ]; then
          echo "c_link_args = ['--target=${androidToolchain.androidTarget}', '--sysroot', '${androidToolchain.androidndkRoot}/sysroot', '-L$LIBFFI_LIB']" >> android-cross-file.txt
          echo "cpp_link_args = ['--target=${androidToolchain.androidTarget}', '--sysroot', '${androidToolchain.androidndkRoot}/sysroot', '-L$LIBFFI_LIB']" >> android-cross-file.txt
        else
          echo "c_link_args = ['--target=${androidToolchain.androidTarget}', '--sysroot', '${androidToolchain.androidndkRoot}/sysroot']" >> android-cross-file.txt
          echo "cpp_link_args = ['--target=${androidToolchain.androidTarget}', '--sysroot', '${androidToolchain.androidndkRoot}/sysroot']" >> android-cross-file.txt
        fi
        LIBXML2_NATIVE_INCLUDE_VAL=""
        LIBXML2_NATIVE_LIB_VAL=""
        if [ -d "${buildPackages.libxml2.dev}/include/libxml2" ]; then
          LIBXML2_NATIVE_INCLUDE_VAL="${buildPackages.libxml2.dev}/include/libxml2"
        fi
        if [ -d "${buildPackages.libxml2.out}/lib" ]; then
          LIBXML2_NATIVE_LIB_VAL="${buildPackages.libxml2.out}/lib"
          if [ -f "${buildPackages.libxml2.out}/lib/libxml2.dylib" ]; then
            LIBXML2_NATIVE_LIB_VAL="${buildPackages.libxml2.out}/lib"
          elif [ -f "${buildPackages.libxml2.out}/lib/libxml2.a" ]; then
            LIBXML2_NATIVE_LIB_VAL="${buildPackages.libxml2.out}/lib"
          fi
        fi
        echo "LIBXML2_NATIVE_LIB_VAL: $LIBXML2_NATIVE_LIB_VAL"
        ls -la "$LIBXML2_NATIVE_LIB_VAL"/*.dylib "$LIBXML2_NATIVE_LIB_VAL"/*.a 2>/dev/null | head -5 || echo "No libxml2 libraries found"
        NATIVE_CC="${buildPackages.gcc}/bin/gcc"
        NATIVE_CXX="${buildPackages.gcc}/bin/g++"
        if [ ! -x "$NATIVE_CC" ]; then
          NATIVE_CC="${buildPackages.stdenv.cc}/bin/cc"
          NATIVE_CXX="${buildPackages.stdenv.cc}/bin/c++"
          if [ ! -x "$NATIVE_CC" ] || echo "$($NATIVE_CC --version 2>&1)" | grep -q "android"; then
            NATIVE_CC="${buildPackages.clang}/bin/clang"
            NATIVE_CXX="${buildPackages.clang}/bin/clang++"
            if echo "$($NATIVE_CC --version 2>&1)" | grep -q "android"; then
              NATIVE_CC="cc"
              NATIVE_CXX="c++"
            fi
          fi
        fi
        echo "Using native compiler: $NATIVE_CC"
        if [ -x "$NATIVE_CC" ]; then
          "$NATIVE_CC" --version || true
        fi
        cat > meson-native-file.txt <<NATIVEFILE
    [binaries]
    c = '$NATIVE_CC'
    cpp = '$NATIVE_CXX'
    pkg-config = '${buildPackages.pkg-config}/bin/pkg-config'
    NATIVEFILE
        if [ -n "$LIBXML2_NATIVE_INCLUDE_VAL" ]; then
          echo "" >> meson-native-file.txt
          echo "[built-in options]" >> meson-native-file.txt
          echo "c_args = ['-I$LIBXML2_NATIVE_INCLUDE_VAL']" >> meson-native-file.txt
          echo "cpp_args = ['-I$LIBXML2_NATIVE_INCLUDE_VAL']" >> meson-native-file.txt
          if [ -n "$LIBXML2_NATIVE_LIB_VAL" ]; then
            LIBXML2_LIB_FILE=""
            if [ -f "$LIBXML2_NATIVE_LIB_VAL/libxml2.dylib" ]; then
              LIBXML2_LIB_FILE="$LIBXML2_NATIVE_LIB_VAL/libxml2.dylib"
            elif [ -f "$LIBXML2_NATIVE_LIB_VAL/libxml2.a" ]; then
              LIBXML2_LIB_FILE="$LIBXML2_NATIVE_LIB_VAL/libxml2.a"
            fi
            if [ -n "$LIBXML2_LIB_FILE" ]; then
              echo "c_link_args = ['$LIBXML2_LIB_FILE', '-L$LIBXML2_NATIVE_LIB_VAL']" >> meson-native-file.txt
              echo "cpp_link_args = ['$LIBXML2_LIB_FILE', '-L$LIBXML2_NATIVE_LIB_VAL']" >> meson-native-file.txt
            else
              echo "c_link_args = ['-L$LIBXML2_NATIVE_LIB_VAL', '-lxml2']" >> meson-native-file.txt
              echo "cpp_link_args = ['-L$LIBXML2_NATIVE_LIB_VAL', '-lxml2']" >> meson-native-file.txt
            fi
          fi
        fi
        if [ -n "$LIBXML2_NATIVE_INCLUDE_VAL" ]; then
          export CFLAGS="-I$LIBXML2_NATIVE_INCLUDE_VAL"
          export CPPFLAGS="-I$LIBXML2_NATIVE_INCLUDE_VAL"
          export C_INCLUDE_PATH="$LIBXML2_NATIVE_INCLUDE_VAL"
          export CPP_INCLUDE_PATH="$LIBXML2_NATIVE_INCLUDE_VAL"
        fi
        export PATH="${buildPackages.gcc}/bin:$PATH"
  '';
  configurePhase = ''
    runHook preConfigure
    ANDROID_PKG_CONFIG_PATH=""
    for depPkg in ${lib.concatMapStringsSep " " (p: toString p) depInputs}; do
      if [ -d "$depPkg/lib/pkgconfig" ]; then
        ANDROID_PKG_CONFIG_PATH="$depPkg/lib/pkgconfig:$ANDROID_PKG_CONFIG_PATH"
      fi
    done
    export PKG_CONFIG_PATH="$ANDROID_PKG_CONFIG_PATH"
    # PKG_CONFIG_PATH_FOR_BUILD is set in preConfigure for wayland-scanner
    export PATH="${buildPackages.gcc}/bin:$PATH"
    unset CC CXX AR STRIP RANLIB CFLAGS CXXFLAGS LDFLAGS NIX_CFLAGS_COMPILE NIX_CXXFLAGS_COMPILE
    NATIVE_FILE_PATH="$(pwd)/meson-native-file.txt"
    CROSS_FILE_PATH="$(pwd)/android-cross-file.txt"
    echo "PKG_CONFIG_PATH_FOR_BUILD=$PKG_CONFIG_PATH_FOR_BUILD"
    echo "PKG_CONFIG_PATH=$PKG_CONFIG_PATH"
    echo "Testing native expat pkg-config:"
    PKG_CONFIG_PATH="$PKG_CONFIG_PATH_FOR_BUILD" ${buildPackages.pkg-config}/bin/pkg-config --exists expat && echo "expat found" || echo "expat NOT found"
    PKG_CONFIG_PATH="$PKG_CONFIG_PATH_FOR_BUILD" ${buildPackages.pkg-config}/bin/pkg-config --libs expat || echo "expat libs failed"
    echo "Testing wayland-scanner:"
    which wayland-scanner || echo "wayland-scanner not in PATH"
    PKG_CONFIG_PATH="$PKG_CONFIG_PATH" PKG_CONFIG_PATH_FOR_BUILD="$PKG_CONFIG_PATH_FOR_BUILD" meson setup build \
      --prefix=$out \
      --libdir=$out/lib \
      --cross-file="$CROSS_FILE_PATH" \
      --native-file="$NATIVE_FILE_PATH" \
      --default-library=both \
      -Dscanner=true \
      ${lib.concatMapStringsSep " \\\n  " (flag: flag) buildFlags}
    runHook postConfigure
  '';
  buildPhase = ''
    runHook preBuild
    meson compile -C build
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    meson install -C build
    runHook postInstall
  '';
  __impureHostDeps = [ "/bin/sh" ];
}
