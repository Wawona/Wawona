# Canonical bundled native clients. Keep in sync with
# Sources/Wawona: kBundledClients in WWNMachinesViewModel.swift
#
# Usage: source scripts/lib/bundled-clients-catalog.sh
#   bundled_clients_all          → space-separated ids
#   bundled_client_prefs_key ID  → prefsKey
#   bundled_client_skip_reason PLATFORM CLIENT → nonempty = skip

bundled_clients_all() {
  printf '%s\n' \
    weston-terminal \
    weston-simple-shm \
    weston \
    niri \
    foot \
    weston-flower \
    kmscube \
    gbm-es2-demo \
    opengl-cube \
    vkcube \
    weston-simple-egl \
    weston-smoke \
    weston-clickdot \
    weston-eventdemo \
    weston-resizor \
    weston-cliptest \
    weston-transformed \
    weston-stacking \
    weston-dnd \
    weston-image \
    weston-scaler \
    weston-editor \
    weston-constraints
}

bundled_client_prefs_key() {
  case "$1" in
    weston-terminal) echo WestonTerminalEnabled ;;
    weston-simple-shm) echo WestonSimpleSHMEnabled ;;
    weston) echo WestonEnabled ;;
    niri) echo NiriEnabled ;;
    foot) echo FootEnabled ;;
    weston-flower) echo WestonFlowerEnabled ;;
    kmscube) echo KmscubeEnabled ;;
    gbm-es2-demo) echo GbmEs2DemoEnabled ;;
    opengl-cube) echo OpenglCubeEnabled ;;
    vkcube) echo VkcubeEnabled ;;
    weston-simple-egl) echo WestonSimpleEglEnabled ;;
    weston-smoke) echo WestonSmokeEnabled ;;
    weston-clickdot) echo WestonClickdotEnabled ;;
    weston-eventdemo) echo WestonEventdemoEnabled ;;
    weston-resizor) echo WestonResizorEnabled ;;
    weston-cliptest) echo WestonCliptestEnabled ;;
    weston-transformed) echo WestonTransformedEnabled ;;
    weston-stacking) echo WestonStackingEnabled ;;
    weston-dnd) echo WestonDndEnabled ;;
    weston-image) echo WestonImageEnabled ;;
    weston-scaler) echo WestonScalerEnabled ;;
    weston-editor) echo WestonEditorEnabled ;;
    weston-constraints) echo WestonConstraintsEnabled ;;
    *) echo "" ;;
  esac
}

# Platform-targets matrix: tvOS forbids Vulkan/OpenGL in store matrix cells unless
# WWN_TVOS_GPU. watchOS CPU GLES/VK (SwiftShader + ANGLE) when WWN_WATCH_SWIFTSHADER=1.
# Nested compositors (weston/niri) are allowed everywhere native machines are.
# weston-simple-egl is a Wayland-EGL client (wl_egl_window + ANGLE). Not KMS.
bundled_client_skip_reason() {
  local platform="$1" client="$2"
  case "$platform" in
    tvos)
      case "$client" in
        kmscube|gbm-es2-demo|opengl-cube|vkcube|weston-simple-egl)
          echo "platform-targets: no Vulkan/OpenGL/ANGLE on ${platform}"
          return 0
          ;;
      esac
      ;;
    watchos)
      case "$client" in
        kmscube|gbm-es2-demo|opengl-cube|vkcube|weston-simple-egl)
          case "${WWN_WATCH_SWIFTSHADER:-1}" in
            1|true|TRUE|yes|YES) ;;
            *)
              echo "watchos: CPU GLES/VK requires WWN_WATCH_SWIFTSHADER=1 build"
              return 0
              ;;
          esac
          ;;
      esac
      ;;
  esac
  echo ""
}

# Hold seconds: nested compositors need longer settle; demos are shorter.
bundled_client_hold_sec() {
  case "$1" in
    weston|niri) echo "${WAWONA_MATRIX_NESTED_HOLD_SEC:-20}" ;;
    *) echo "${WAWONA_MATRIX_CLIENT_HOLD_SEC:-12}" ;;
  esac
}

# Success log patterns (any match after connect → evidence of live client).
# Fail patterns abort the cell as FAIL even if process still alive.
bundled_client_fail_patterns() {
  printf '%s\n' \
    'niri_main: panicked' \
    'niri_main: fatal error' \
    'niri_main not linked' \
    'weston_compositor_main not linked' \
    'Unknown bundled client id' \
    'WWNNativeClientLaunchFailed' \
    'LaunchFailedNotification' \
    'exited with code 127' \
    'Refusing launch: empty bundled client' \
    'KMS clients deferred' \
    'SIGABRT' \
    'panic_cannot_unwind' \
    'Fatal error:' \
    'EXC_BAD_ACCESS' \
    'terminated due to signal'
}

bundled_client_ok_patterns() {
  local client="$1"
  case "$client" in
    niri)
      printf '%s\n' 'Launching in-process niri_main' 'niri (nested) listening' 'starting niri' 'Launched niri with PID'
      ;;
    weston)
      printf '%s\n' 'Launching nested weston' 'weston_compositor_main' 'Compositor started'
      ;;
    weston-terminal)
      printf '%s\n' 'weston_terminal_main' 'Launching in-process weston-terminal' 'WAWONA_ZSH'
      ;;
    foot)
      printf '%s\n' 'foot_main' 'Launching in-process foot'
      ;;
    opengl-cube|vkcube|weston-simple-egl)
      printf '%s\n' \
        'WATCH: First frame' \
        'Launching in-process' \
        "Launched client '" \
        'Starting ' \
        'RENDER' \
        'Node present'
      ;;
    kmscube|gbm-es2-demo)
      printf '%s\n' \
        'WATCH: First frame' \
        "Launched client '" \
        'iland DRM present' \
        'enter (iland DRM present)'
      ;;
    weston-smoke)
      # Require a real SHM buffer / frame. Process-alive alone is not PASS.
      printf '%s\n' \
        'Node present' \
        'RENDER' \
        'first buffer' \
        'Attached buffer' \
        'wl_buffer' \
        'frame callback' \
        'Launching in-process weston-smoke'
      ;;
    *)
      printf '%s\n' "Launching in-process ${client}" "Launching in-process" "RENDER" "Node present"
      ;;
  esac
}
