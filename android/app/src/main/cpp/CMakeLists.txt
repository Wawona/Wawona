cmake_minimum_required(VERSION 3.22.1)
project("wawona")

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

# The root of the Wawona repository (relative to android/app/src/main/cpp/)
set(WAWONA_ROOT "../../../..")

# Set up include directories
include_directories(
    ${WAWONA_ROOT}/src
    ${WAWONA_ROOT}/src/core
    ${WAWONA_ROOT}/src/stubs
    ${WAWONA_ROOT}/src/platform/android/rendering
    ${WAWONA_ROOT}/src/platform/macos
    ${WAWONA_ROOT}/src/platform/android
    ${WAWONA_ROOT}/deps/weston-simple-shm
    ${WAWONA_ROOT}/deps/weston-simple-shm/shared
    ${WAWONA_ROOT}/deps/weston-simple-shm/include
)

# Convert NIX_DEP_INCLUDES from string "-I/nix/.../include -I/nix/.../include" into proper CMake dirs
if (DEFINED NIX_DEP_INCLUDES)
    string(REPLACE "-I" "" NIX_INCLUDES_CL ${NIX_DEP_INCLUDES})
    separate_arguments(NIX_INCLUDES_CL)
    include_directories(${NIX_INCLUDES_CL})
endif()

# Keep the Android native build aligned with the Nix source filter instead of
# globbing in platform-specific desktop/iOS stubs.
set(WAWONA_SOURCES
    ${WAWONA_ROOT}/src/stubs/egl_buffer_handler.c
    ${WAWONA_ROOT}/src/platform/android/android_jni.c
    ${WAWONA_ROOT}/src/platform/android/input_android.c
    ${WAWONA_ROOT}/src/platform/android/cairo_shim.c
    ${WAWONA_ROOT}/src/platform/android/rendering/renderer_android.c
    ${WAWONA_ROOT}/src/platform/macos/WWNSettings.c
)

# Core library (libwawona.so)
add_library(
    wawona
    SHARED
    ${WAWONA_SOURCES}
    ${WAWONA_ROOT}/deps/weston-simple-shm/clients/simple-shm.c
    ${WAWONA_ROOT}/deps/weston-simple-shm/shared/os-compatibility.c
    ${WAWONA_ROOT}/deps/weston-simple-shm/xdg-shell-protocol.c
    ${WAWONA_ROOT}/deps/weston-simple-shm/fullscreen-shell-unstable-v1-protocol.c
)

# Parse NIX_DEP_LIBS "-L/nix/.../lib -L/nix/.../lib"
set(NIX_LIB_DIRS "")
if (DEFINED NIX_DEP_LIBS)
    string(REPLACE "-L" "" NIX_LIB_DIRS_RAW "${NIX_DEP_LIBS}")
    separate_arguments(NIX_LIB_DIRS NATIVE_COMMAND "${NIX_LIB_DIRS_RAW}")
endif()

# Target Link Libraries
target_link_libraries(
    wawona
    
    # Internal Rust backend
    ${RUST_BACKEND_LIB}
    
    # Standard external dependencies
    wayland-server
    wayland-client
    pixman-1
    xkbcommon
    ffi
    expat
    ssl
    crypto
    zstd
    lz4
    
    # Android System Libraries
    log
    android
    vulkan
    m
    dl
    z
)

if (NIX_LIB_DIRS)
    target_link_directories(wawona PRIVATE ${NIX_LIB_DIRS})
endif()

# Extra definitions
target_compile_definitions(wawona PRIVATE _GNU_SOURCE)
