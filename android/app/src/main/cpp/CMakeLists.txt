cmake_minimum_required(VERSION 3.22.1)
project("wawona")

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

# Repository root containing src/, deps/, etc. Two layouts are supported:
# - Nix build: android/* is flattened to repo root, so app/ is <root>/app -> 4 levels up from cpp.
# - android/ or Wawona-gradle-project/: app/ is nested one level deeper -> 5 levels up from cpp.
set(_CPP "${CMAKE_CURRENT_SOURCE_DIR}")
set(_ROOT5 "${_CPP}/../../../../..")
set(_ROOT4 "${_CPP}/../../../..")
if(EXISTS "${_ROOT5}/src/stubs/egl_buffer_handler.c" AND EXISTS "${_ROOT5}/deps/weston-simple-shm/clients/simple-shm.c")
  set(WAWONA_ROOT "${_ROOT5}")
elseif(EXISTS "${_ROOT4}/src/stubs/egl_buffer_handler.c" AND EXISTS "${_ROOT4}/deps/weston-simple-shm/clients/simple-shm.c")
  set(WAWONA_ROOT "${_ROOT4}")
else()
  message(FATAL_ERROR
    "Wawona C sources/deps not found (expected src/stubs/egl_buffer_handler.c and deps/weston-simple-shm/clients/simple-shm.c). "
    "For Android Studio use `nix run .#gradlegen` from the repo (links src/ and Weston deps), "
    "or build from the Nix-flattened tree (see dependencies/wawona/android.nix).")
endif()

# Set up include directories
include_directories(
    ${WAWONA_ROOT}/src
    ${WAWONA_ROOT}/src/core
    ${WAWONA_ROOT}/src/stubs
    ${WAWONA_ROOT}/src/platform/android/rendering
    ${WAWONA_ROOT}/src/platform/macos
    ${WAWONA_ROOT}/src/platform/android
)

# Convert NIX_DEP_INCLUDES from string "-I/nix/.../include -I/nix/.../include" into proper CMake dirs
if (DEFINED NIX_DEP_INCLUDES)
    string(REPLACE "-I" "" NIX_INCLUDES_CL ${NIX_DEP_INCLUDES})
    separate_arguments(NIX_INCLUDES_CL)
    include_directories(${NIX_INCLUDES_CL})
endif()

# Android Studio local builds often run without Nix DEP_INCLUDES/DEP_LIBS.
# In that mode we build a reduced native target that avoids external Wayland deps.
set(WAWONA_STUDIO_FALLBACK OFF)
if(NOT DEFINED NIX_DEP_INCLUDES OR NIX_DEP_INCLUDES STREQUAL "")
  set(WAWONA_STUDIO_FALLBACK ON)
endif()
if(NOT WAWONA_STUDIO_FALLBACK)
  include_directories(
      ${WAWONA_ROOT}/deps/weston-simple-shm
      ${WAWONA_ROOT}/deps/weston-simple-shm/shared
      ${WAWONA_ROOT}/deps/weston-simple-shm/include
  )
endif()

# Keep the Android native build aligned with the Nix source filter instead of
# globbing in platform-specific desktop/iOS stubs.
set(WAWONA_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/wawona_client_stubs.c
    ${WAWONA_ROOT}/src/stubs/egl_buffer_handler.c
    ${WAWONA_ROOT}/src/platform/android/android_jni.c
    ${WAWONA_ROOT}/src/platform/android/input_android.c
    ${WAWONA_ROOT}/src/platform/macos/WWNSettings.c
)
if(WAWONA_STUDIO_FALLBACK)
  list(APPEND WAWONA_SOURCES
      ${WAWONA_ROOT}/src/platform/android/rendering/renderer_android_stub.c
      ${WAWONA_ROOT}/src/platform/android/backend_core_stub.c
  )
else()
  list(APPEND WAWONA_SOURCES
      ${WAWONA_ROOT}/src/platform/android/cairo_shim.c
      ${WAWONA_ROOT}/src/platform/android/rendering/renderer_android.c
  )
endif()

# Core library (libwawona.so)
add_library(
    wawona
    SHARED
    ${WAWONA_SOURCES}
)
if(NOT WAWONA_STUDIO_FALLBACK)
  target_sources(
      wawona PRIVATE
      ${WAWONA_ROOT}/deps/weston-simple-shm/clients/simple-shm.c
      ${WAWONA_ROOT}/deps/weston-simple-shm/shared/os-compatibility.c
      ${WAWONA_ROOT}/deps/weston-simple-shm/xdg-shell-protocol.c
      ${WAWONA_ROOT}/deps/weston-simple-shm/fullscreen-shell-unstable-v1-protocol.c
  )
endif()

# Parse NIX_DEP_LIBS "-L/nix/.../lib -L/nix/.../lib"
set(NIX_LIB_DIRS "")
if (DEFINED NIX_DEP_LIBS)
    string(REPLACE "-L" "" NIX_LIB_DIRS_RAW "${NIX_DEP_LIBS}")
    separate_arguments(NIX_LIB_DIRS NATIVE_COMMAND "${NIX_LIB_DIRS_RAW}")
endif()

# Target Link Libraries (Rust backend first to match Nix/ld resolution)
set(_WAWONA_LINK_LIBS "")
if(DEFINED RUST_BACKEND_LIB AND NOT RUST_BACKEND_LIB STREQUAL "")
  list(APPEND _WAWONA_LINK_LIBS ${RUST_BACKEND_LIB})
endif()
if(WAWONA_STUDIO_FALLBACK)
  list(APPEND _WAWONA_LINK_LIBS
      log
      android
      vulkan
      m
      dl
      z
  )
  # JNI bridge references backend symbols resolved in full Nix builds.
  # Allow unresolved symbols for local IDE-only fallback builds.
  target_link_options(wawona PRIVATE
      "-Wl,--allow-shlib-undefined"
      "-Wl,--unresolved-symbols=ignore-all"
  )
else()
  list(APPEND _WAWONA_LINK_LIBS
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
      log
      android
      vulkan
      m
      dl
      z
  )
endif()
target_link_libraries(wawona PRIVATE ${_WAWONA_LINK_LIBS})

if (NIX_LIB_DIRS)
    target_link_directories(wawona PRIVATE ${NIX_LIB_DIRS})
endif()

# Extra definitions
target_compile_definitions(wawona PRIVATE
    _GNU_SOURCE
    _POSIX_C_SOURCE=200809L
)
