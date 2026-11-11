cmake_minimum_required(VERSION 3.22.1)
project("wawona")

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

# android/app/build.gradle.kts passes WAWONA_ROOT (the repository) and
# WAWONA_DEPS (.deps/android) with the NIX_DEP_* flags from its wawona.properties.
if(NOT DEFINED NIX_DEP_INCLUDES OR NOT EXISTS "${WAWONA_DEPS}/cpp/shader_spv.h")
  message(FATAL_ERROR "Android dependencies missing. Run `nix run .#deps -- android` at the repository root.")
endif()

include_directories(
    ${WAWONA_ROOT}/src
    ${WAWONA_ROOT}/src/core
    ${WAWONA_ROOT}/src/stubs
    ${WAWONA_ROOT}/src/platform/android/rendering
    ${WAWONA_DEPS}/cpp
    ${WAWONA_ROOT}/src/platform/macos
    ${WAWONA_ROOT}/src/platform/android
)
string(REPLACE "-I" "" NIX_INCLUDES_CL ${NIX_DEP_INCLUDES})
separate_arguments(NIX_INCLUDES_CL)
include_directories(${NIX_INCLUDES_CL})

set(WAWONA_WESTON_COMPOSITOR OFF)
if(NIX_DEP_LIBS MATCHES "libweston-compositor-13")
  set(WAWONA_WESTON_COMPOSITOR ON)
endif()
set(WAWONA_ILAND_GL OFF)
if(NIX_DEP_LIBS MATCHES "libiland_userland")
  set(WAWONA_ILAND_GL ON)
endif()

set(WAWONA_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/wawona_client_stubs.c
    ${WAWONA_ROOT}/src/stubs/egl_buffer_handler.c
    ${WAWONA_ROOT}/src/platform/android/android_jni.c
    ${WAWONA_ROOT}/src/platform/android/anowaw_jni.c
    ${WAWONA_ROOT}/src/platform/android/input_android.c
    ${WAWONA_ROOT}/src/platform/android/rendering/renderer_android.c
    ${WAWONA_ROOT}/src/platform/macos/WWNSettings.c
)
if(WAWONA_ILAND_GL)
  list(APPEND WAWONA_SOURCES ${WAWONA_ROOT}/src/platform/android/iland_presenter_android.c)
endif()

# Core library (libwawona.so)
add_library(wawona SHARED ${WAWONA_SOURCES})

# NIX_DEP_LIBS: "-L" directories plus link flags (whole-archive weston, -l flags).
set(NIX_LIB_DIRS "")
set(NIX_EXTRA_LINK_FLAGS "")
separate_arguments(NIX_ALL_FLAGS NATIVE_COMMAND "${NIX_DEP_LIBS}")
foreach(flag ${NIX_ALL_FLAGS})
    if(flag MATCHES "^-L")
        string(REGEX REPLACE "^-L" "" dir "${flag}")
        list(APPEND NIX_LIB_DIRS "${dir}")
    else()
        list(APPEND NIX_EXTRA_LINK_FLAGS "${flag}")
    endif()
endforeach()

# Rust backend first to match Nix/ld resolution. android_shell.rs is its own
# object; pull it even when the archive index was produced on a Darwin host.
set(_WAWONA_LINK_LIBS "")
foreach(_shell_symbol
    wwn_android_shell_start
    wwn_android_shell_write
    wwn_android_shell_read
    wwn_android_shell_resize
    wwn_android_shell_stop)
  list(APPEND _WAWONA_LINK_LIBS "-Wl,-u,${_shell_symbol}")
endforeach()
list(APPEND _WAWONA_LINK_LIBS
    ${RUST_BACKEND_LIB}
    anowaw
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
# NDK lld treats Darwin-indexed static archives (common when cross-compiling
# from macOS hosts) as warnings; --fatal-warnings from the toolchain promotes
# those to hard link failures for -lcairo/-lpango etc.
target_link_options(wawona PRIVATE "-Wl,--no-fatal-warnings")
target_link_options(wawona PRIVATE "-Wl,--wrap=memfd_create")
# Rust nix crate references syncfs; Bionic may not export it at minSdk.
target_link_options(wawona PRIVATE "-Wl,--wrap=syncfs")
# AHardwareBuffer starts at API 26 while Wawona keeps API 24 compatibility.
# Resolve these entry points dynamically; wrappers return ENOSYS on API 24/25.
foreach(_ahb_symbol allocate describe release lock unlock)
  target_link_options(
    wawona PRIVATE "-Wl,--wrap=AHardwareBuffer_${_ahb_symbol}"
  )
endforeach()
target_link_options(wawona PRIVATE "-Wl,--wrap=strtod_l")
target_link_libraries(wawona PRIVATE ${_WAWONA_LINK_LIBS} ${NIX_EXTRA_LINK_FLAGS})

target_link_directories(wawona PRIVATE ${NIX_LIB_DIRS})

# Extra definitions
target_compile_definitions(wawona PRIVATE
    _GNU_SOURCE
    _POSIX_C_SOURCE=200809L
    WAWONA_WESTON_TOYTOOLKIT=1
)
if(WAWONA_WESTON_COMPOSITOR)
  target_compile_definitions(wawona PRIVATE WAWONA_WESTON_COMPOSITOR=1)
endif()
if(WAWONA_ILAND_GL)
  target_compile_definitions(wawona PRIVATE WAWONA_ILAND_GL=1)
  target_link_libraries(wawona PRIVATE android)
endif()
