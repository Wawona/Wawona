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
    ${WAWONA_ROOT}/dependencies/generators/gradlegen/generated
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
set(WAWONA_WESTON_TOYTOOLKIT OFF)
set(WAWONA_WESTON_COMPOSITOR OFF)
if(DEFINED NIX_DEP_INCLUDES AND NIX_DEP_INCLUDES MATCHES "weston-gen")
  set(WAWONA_WESTON_TOYTOOLKIT ON)
elseif(DEFINED NIX_DEP_LIBS AND NIX_DEP_LIBS MATCHES "libweston-13")
  set(WAWONA_WESTON_TOYTOOLKIT ON)
endif()
if(DEFINED NIX_DEP_LIBS AND NIX_DEP_LIBS MATCHES "libweston-compositor-13")
  set(WAWONA_WESTON_COMPOSITOR ON)
endif()
set(WAWONA_ILAND_GL OFF)
if(DEFINED NIX_DEP_LIBS AND NIX_DEP_LIBS MATCHES "libiland_userland")
  set(WAWONA_ILAND_GL ON)
endif()
if(NOT WAWONA_STUDIO_FALLBACK AND NOT WAWONA_WESTON_TOYTOOLKIT)
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
# anowaW app-bridge JNI glue: staged into the project by the Nix Android build
# (dependencies/wawona/android.nix) from the wwn-anowaW dep. Guarded by EXISTS so
# IDE/Studio fallback builds without the staged file still configure.
if(EXISTS "${WAWONA_ROOT}/src/platform/android/anowaw_jni.c")
  list(APPEND WAWONA_SOURCES ${WAWONA_ROOT}/src/platform/android/anowaw_jni.c)
  set(WAWONA_HAVE_ANOWAW ON)
endif()
if(WAWONA_STUDIO_FALLBACK)
  list(APPEND WAWONA_SOURCES
      ${WAWONA_ROOT}/src/platform/android/rendering/renderer_android_stub.c
      ${WAWONA_ROOT}/src/platform/android/backend_core_stub.c
  )
else()
  list(APPEND WAWONA_SOURCES
      ${WAWONA_ROOT}/src/platform/android/rendering/renderer_android.c
  )
  if(WAWONA_ILAND_GL)
    list(APPEND WAWONA_SOURCES
        ${WAWONA_ROOT}/src/platform/android/iland_presenter_android.c
    )
  endif()
  if(NOT WAWONA_WESTON_TOYTOOLKIT)
    list(APPEND WAWONA_SOURCES
        ${WAWONA_ROOT}/src/platform/android/cairo_shim.c
    )
  endif()
  if(NOT EXISTS "${WAWONA_ROOT}/dependencies/generators/gradlegen/generated/shader_spv.h")
    message(FATAL_ERROR
      "Missing generated Android shader header at dependencies/generators/gradlegen/generated/shader_spv.h. "
      "Run `nix run .#gradlegen` to regenerate project artifacts.")
  endif()
endif()

# Core library (libwawona.so)
add_library(
    wawona
    SHARED
    ${WAWONA_SOURCES}
)
if(NOT WAWONA_STUDIO_FALLBACK AND NOT WAWONA_WESTON_TOYTOOLKIT)
  target_sources(
      wawona PRIVATE
      ${WAWONA_ROOT}/deps/weston-simple-shm/clients/simple-shm.c
      ${WAWONA_ROOT}/deps/weston-simple-shm/shared/os-compatibility.c
      ${WAWONA_ROOT}/deps/weston-simple-shm/xdg-shell-protocol.c
      ${WAWONA_ROOT}/deps/weston-simple-shm/fullscreen-shell-unstable-v1-protocol.c
  )
endif()

# Parse NIX_DEP_LIBS: "-L/nix/.../lib" directories plus extra link flags
# (whole-archive weston static libs, cairo/pango -l flags, etc.)
set(NIX_LIB_DIRS "")
set(NIX_EXTRA_LINK_FLAGS "")
if (DEFINED NIX_DEP_LIBS)
    separate_arguments(NIX_ALL_FLAGS NATIVE_COMMAND "${NIX_DEP_LIBS}")
    foreach(flag ${NIX_ALL_FLAGS})
        if(flag MATCHES "^-L")
            string(REGEX REPLACE "^-L" "" dir "${flag}")
            list(APPEND NIX_LIB_DIRS "${dir}")
        elseif(flag MATCHES "\\.a$")
            if(NOT EXISTS "${flag}")
                message(FATAL_ERROR
                    "Missing native archive '${flag}'. Nix store paths in gradle.properties go stale after rebuilds. "
                    "Run `nix run .#gradlegen` from the repo root, then Build → Clean Project in Android Studio.")
            endif()
            list(APPEND NIX_EXTRA_LINK_FLAGS "${flag}")
        else()
            list(APPEND NIX_EXTRA_LINK_FLAGS "${flag}")
        endif()
    endforeach()
endif()

# Auto-link nested Weston compositor when materialized in .nix-deps but absent
# from stale gradle.properties (common after partial gradlegen refresh).
set(_WAWONA_WESTON_COMPOSITOR_LINKED OFF)
foreach(flag ${NIX_EXTRA_LINK_FLAGS})
    if(flag MATCHES "libweston-compositor-13\\.a$")
        set(_WAWONA_WESTON_COMPOSITOR_LINKED ON)
    endif()
endforeach()
if(NOT _WAWONA_WESTON_COMPOSITOR_LINKED)
    foreach(dir ${NIX_LIB_DIRS})
        set(_compositor_archive "${dir}/libweston-compositor-13.a")
        if(EXISTS "${_compositor_archive}")
            list(APPEND NIX_EXTRA_LINK_FLAGS
                "-Wl,-u,weston_compositor_main"
                "${_compositor_archive}")
            set(WAWONA_WESTON_COMPOSITOR ON)
            message(STATUS "Auto-linking nested Weston compositor: ${_compositor_archive}")
            break()
        endif()
    endforeach()
endif()

# Auto-link iland userland KMS + kmscube when materialized in .nix-deps.
set(_WAWONA_ILAND_LINKED OFF)
set(_WAWONA_GBM_ES2_LINKED OFF)
foreach(flag ${NIX_EXTRA_LINK_FLAGS})
    if(flag MATCHES "libiland_userland\\.a$")
        set(_WAWONA_ILAND_LINKED ON)
        set(WAWONA_ILAND_GL ON)
    endif()
    if(flag MATCHES "libgbm_es2_demo\\.a$")
        set(_WAWONA_GBM_ES2_LINKED ON)
    endif()
endforeach()
if(NOT _WAWONA_ILAND_LINKED)
    foreach(dir ${NIX_LIB_DIRS})
        set(_iland_archive "${dir}/libiland_userland.a")
        if(EXISTS "${_iland_archive}")
            list(APPEND NIX_EXTRA_LINK_FLAGS
                "-Wl,--whole-archive"
                "${_iland_archive}"
                "-Wl,--no-whole-archive")
            set(_kmscube_archive "${dir}/libkmscube.a")
            if(EXISTS "${_kmscube_archive}")
                list(APPEND NIX_EXTRA_LINK_FLAGS
                    "-Wl,-u,kmscube_main"
                    "${_kmscube_archive}")
            endif()
            set(_gbm_es2_archive "${dir}/libgbm_es2_demo.a")
            if(EXISTS "${_gbm_es2_archive}")
                list(APPEND NIX_EXTRA_LINK_FLAGS
                    "-Wl,-u,gbm_es2_demo_main"
                    "${_gbm_es2_archive}"
                    "-lc++_static"
                    "-lc++abi")
                set(_WAWONA_GBM_ES2_LINKED ON)
            endif()
            set(WAWONA_ILAND_GL ON)
            message(STATUS "Auto-linking iland GL stack: ${_iland_archive}")
            break()
        endif()
    endforeach()
endif()
# Presenter hard-refs gbm_es2_demo_main when WAWONA_ILAND_GL; pull it if only
# iland+kmscube landed in NIX_DEP_LIBS (stale gradlegen without gbm-es2-demo).
if(WAWONA_ILAND_GL AND NOT _WAWONA_GBM_ES2_LINKED)
    foreach(dir ${NIX_LIB_DIRS})
        set(_gbm_es2_archive "${dir}/libgbm_es2_demo.a")
        if(EXISTS "${_gbm_es2_archive}")
            list(APPEND NIX_EXTRA_LINK_FLAGS
                "-Wl,-u,gbm_es2_demo_main"
                "${_gbm_es2_archive}"
                "-lc++_static"
                "-lc++abi")
            message(STATUS "Auto-linking gbm-es2-demo: ${_gbm_es2_archive}")
            break()
        endif()
    endforeach()
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
  if(WAWONA_WESTON_TOYTOOLKIT)
    target_link_options(wawona PRIVATE "-Wl,--wrap=strtod_l")
  endif()
endif()
if(WAWONA_HAVE_ANOWAW)
  # libanowaw.so is bundled into jniLibs via androidDeps; link it so the JNI
  # glue resolves the anowaw_* C ABI.
  list(APPEND _WAWONA_LINK_LIBS anowaw)
endif()
target_link_libraries(wawona PRIVATE ${_WAWONA_LINK_LIBS} ${NIX_EXTRA_LINK_FLAGS})

if (NIX_LIB_DIRS)
    target_link_directories(wawona PRIVATE ${NIX_LIB_DIRS})
endif()

# Extra definitions
target_compile_definitions(wawona PRIVATE
    _GNU_SOURCE
    _POSIX_C_SOURCE=200809L
)
if(WAWONA_WESTON_TOYTOOLKIT)
  target_compile_definitions(wawona PRIVATE WAWONA_WESTON_TOYTOOLKIT=1)
endif()
if(WAWONA_WESTON_COMPOSITOR)
  target_compile_definitions(wawona PRIVATE WAWONA_WESTON_COMPOSITOR=1)
endif()
if(WAWONA_ILAND_GL)
  target_compile_definitions(wawona PRIVATE WAWONA_ILAND_GL=1)
  target_link_libraries(wawona PRIVATE android)
endif()
