#!/bin/sh
# Sourced by Wawona CLI wrappers. Rewritten by cargo xtask install.
APP="${WAWONA_CLI_APP:-@APP@}"
NAME="${WAWONA_CLI_NAME:-}"

WAWONA_CLI_BIN=""
for cand in \
  "$APP/Contents/Resources/bin/$NAME" \
  "$APP/Contents/MacOS/$NAME"
do
  if [ -f "$cand" ] && [ -x "$cand" ]; then
    WAWONA_CLI_BIN="$cand"
    break
  fi
done
if [ -z "$WAWONA_CLI_BIN" ]; then
  echo "wawona: bundled '$NAME' missing in $APP" >&2
  echo "Hint: cargo xtask install" >&2
  exit 127
fi

MODEB=0
# Classic Take Over: Apple WindowServer is gone. The session compositor
# uses iland DRM/KMS/GBM. Inner weston/niri still nest as Wayland clients
# of that compositor. Do not trust leaked WWN_MODEB_TTY while Aqua is up.
if ! /usr/bin/pgrep -x WindowServer >/dev/null 2>&1; then
  MODEB=1
fi

uid="$(id -u)"
runtime_dir_default="/tmp/wawona-$uid"
runtime_env_file="$runtime_dir_default/wawona-env.sh"
# Nested niri/weston inherit WAYLAND_DISPLAY. zsh inside foot prepends
# ~/.local/bin, so weston-terminal is this wrapper. Sourcing wawona-env.sh
# used to steal the client onto the host socket (new macOS window). Fuzzel
# execs Resources/bin directly and stays nested. Keep a live caller socket.
# macOS Terminal.app has none, so it still attaches to Wawona.
_wawona_saved_display="${WAYLAND_DISPLAY:-}"
_wawona_saved_socket="${WAYLAND_SOCKET:-}"
_wawona_saved_runtime="${XDG_RUNTIME_DIR:-}"
_wawona_keep_caller=0
if [ -n "$_wawona_saved_socket" ]; then
  _wawona_keep_caller=1
elif [ -n "$_wawona_saved_display" ]; then
  _rt="${_wawona_saved_runtime:-$runtime_dir_default}"
  case "$_wawona_saved_display" in
    /*) _sock="$_wawona_saved_display" ;;
    *) _sock="$_rt/$_wawona_saved_display" ;;
  esac
  if [ -S "$_sock" ]; then
    _wawona_keep_caller=1
  fi
  unset _rt _sock
fi
if [ "$_wawona_keep_caller" -eq 1 ]; then
  # Already a client of weston, niri, or Wawona. Inner compositors nest.
  export WAWONA_CLI_NESTED_PARENT=1
  export NIRI_BACKEND=nested
  unset WWN_MODEB_TTY WWN_MODEB_INSERT
elif [ "$MODEB" -eq 1 ]; then
  unset WAWONA_CLI_NESTED_PARENT
  unset WAYLAND_DISPLAY WAYLAND_SOCKET DISPLAY
  export NIRI_BACKEND=tty
  export WWN_MODEB_TTY=1
else
  unset WAWONA_CLI_NESTED_PARENT
  unset WWN_MODEB_TTY WWN_MODEB_INSERT
  case "${NIRI_BACKEND:-}" in
    tty) export NIRI_BACKEND=nested ;;
    "") export NIRI_BACKEND=nested ;;
  esac
fi
if [ "$MODEB" -eq 0 ] && [ "$_wawona_keep_caller" -eq 0 ] && [ -f "$runtime_env_file" ]; then
  # shellcheck source=/dev/null
  . "$runtime_env_file" || true
fi
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$runtime_dir_default}"
if [ "$MODEB" -eq 0 ]; then
  export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
fi
if [ ! -d "$XDG_RUNTIME_DIR" ]; then
  mkdir -p "$XDG_RUNTIME_DIR"
  chmod 700 "$XDG_RUNTIME_DIR"
fi
if [ "$MODEB" -eq 0 ] && [ "$_wawona_keep_caller" -eq 0 ]; then
SOCKET_PATH="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
if [ ! -S "$SOCKET_PATH" ] && command -v launchctl >/dev/null 2>&1; then
  launchctl kickstart -k "gui/$uid/com.aspauldingcode.wawona.compositorhost" >/dev/null 2>&1 || true
  if [ -f "$runtime_env_file" ]; then
    # shellcheck source=/dev/null
    . "$runtime_env_file" || true
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$runtime_dir_default}"
    export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
    SOCKET_PATH="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
  fi
  i=0
  while [ ! -S "$SOCKET_PATH" ] && [ "$i" -lt 50 ]; do
    sleep 0.1
    i=$((i + 1))
  done
fi
fi
if [ "$_wawona_keep_caller" -eq 1 ]; then
  if [ -n "$_wawona_saved_runtime" ]; then
    export XDG_RUNTIME_DIR="$_wawona_saved_runtime"
  fi
  if [ -n "$_wawona_saved_display" ]; then
    export WAYLAND_DISPLAY="$_wawona_saved_display"
  fi
  if [ -n "$_wawona_saved_socket" ]; then
    export WAYLAND_SOCKET="$_wawona_saved_socket"
  fi
fi
unset _wawona_saved_display _wawona_saved_socket _wawona_saved_runtime _wawona_keep_caller

export WAWONA_APP_BUNDLE_ROOT="$APP"
export WAWONA_APP_BIN="$APP/Contents/MacOS/Wawona"

share=""
for d in "$APP/Contents/Resources/share" "$APP/share"; do
  if [ -d "$d" ]; then
    share="$d"
    break
  fi
done
if [ -n "$share" ]; then
  export WAWONA_SHARE_ROOT="$share"
  export XDG_DATA_DIRS="$share${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
fi

lib=""
for d in "$APP/Contents/Resources/lib" "$APP/lib"; do
  if [ -d "$d" ]; then
    lib="$d"
    break
  fi
done
if [ -n "$lib" ]; then
  export WAWONA_LIB_ROOT="$lib"
fi

weston_data=""
for d in "$APP/Contents/Resources/share/weston" "$APP/share/weston"; do
  if [ -d "$d" ]; then
    weston_data="$d"
    break
  fi
done
if [ -n "$weston_data" ]; then
  export WESTON_DATA_DIR="$weston_data"
fi
weston_modules=""
for d in "$APP/Contents/Resources/lib/weston" "$APP/lib/weston"; do
  if [ -d "$d" ]; then
    weston_modules="$d"
    break
  fi
done
if [ -n "$weston_modules" ]; then
  export WESTON_MODULE_DIR="$weston_modules"
fi
weston_backends=""
for d in "$APP/Contents/Resources/lib/libweston-13" "$APP/lib/libweston-13"; do
  if [ -d "$d" ]; then
    weston_backends="$d"
    break
  fi
done
if [ -n "$weston_backends" ]; then
  export WESTON_BACKEND_DIR="$weston_backends"
fi

# desktop-shell.so spawns weston-desktop-shell from baked LIBEXECDIR (a
# nix-store path). WESTON_MODULE_MAP remaps helper names in current weston.
# WESTON_LIBEXEC_DIR is the directory prefix (weston port + this env).
_wawona_libexec=""
for d in "$APP/Contents/Resources/bin" "$APP/Contents/MacOS"; do
  if [ -x "$d/weston-desktop-shell" ]; then
    _wawona_libexec="$d"
    break
  fi
done
if [ -n "$_wawona_libexec" ]; then
  export WESTON_LIBEXEC_DIR="$_wawona_libexec"
  _wawona_map=""
  for _h in weston-desktop-shell weston-keyboard weston-simple-im; do
    if [ -x "$_wawona_libexec/$_h" ]; then
      if [ -n "$_wawona_map" ]; then
        _wawona_map="$_wawona_map;"
      fi
      _wawona_map="$_wawona_map$_h=$_wawona_libexec/$_h"
    fi
  done
  if [ -n "$_wawona_map" ]; then
    export WESTON_MODULE_MAP="$_wawona_map"
  fi
  unset _wawona_map _h
fi
unset _wawona_libexec

icons=""
for d in "$APP/Contents/Resources/share/icons" "$APP/share/icons"; do
  if [ -d "$d" ]; then
    icons="$d"
    break
  fi
done
if [ -n "$icons" ]; then
  export XCURSOR_PATH="$icons"
  export XCURSOR_THEME="Adwaita"
  export XCURSOR_SIZE="${XCURSOR_SIZE:-24}"
fi

fonts=""
for d in "$APP/share/fonts" "$APP/Contents/Resources/share/fonts"; do
  if [ -d "$d" ]; then
    fonts="$d"
    break
  fi
done
if [ -n "$fonts" ]; then
  fc_dir="${HOME}/Library/Caches/Wawona"
  mkdir -p "$fc_dir/cache"
  fc_file="$fc_dir/cli-fonts.conf"
  cat > "$fc_file" <<FC
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <dir>$fonts</dir>
  <cachedir>$fc_dir/cache</cachedir>
  <alias>
    <family>monospace</family>
    <prefer><family>DejaVuSansM Nerd Font Mono</family></prefer>
    <prefer><family>DejaVu Sans Mono</family></prefer>
  </alias>
  <alias>
    <family>sans-serif</family>
    <prefer><family>DejaVu Sans</family></prefer>
  </alias>
  <config></config>
</fontconfig>
FC
  export FONTCONFIG_FILE="$fc_file"
  export FONTCONFIG_PATH="$fc_dir"
fi

if [ -d "$APP/Contents/Frameworks" ]; then
  export DYLD_LIBRARY_PATH="$APP/Contents/Frameworks${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
fi
# Never export DYLD_INSERT_LIBRARIES here. Apple /bin/* is arm64e.

bin_dir="$APP/Contents/Resources/bin"
if [ -d "$bin_dir" ]; then
  export PATH="$bin_dir:$PATH"
fi

if [ "$NAME" = weston ] && [ "$MODEB" -eq 0 ]; then
  export WAWONA_OUTPUT_SCALE="${WAWONA_OUTPUT_SCALE:-1}"
  export WAWONA_NESTED_WAYLAND="${WAWONA_NESTED_WAYLAND:-1}"
  if [ -z "${WESTON_CONFIG_FILE:-}" ] && [ -n "${XDG_RUNTIME_DIR:-}" ]; then
    _wawona_ini="$XDG_RUNTIME_DIR/weston.ini"
    _wawona_shell=""
    _wawona_kbd=""
    for _wawona_c in \
      "$APP/Contents/Resources/bin/weston-desktop-shell" \
      "$APP/Contents/MacOS/weston-desktop-shell" \
      "$APP/Contents/Resources/libexec/weston-desktop-shell"
    do
      if [ -x "$_wawona_c" ]; then
        _wawona_shell="$_wawona_c"
        break
      fi
    done
    for _wawona_c in \
      "$APP/Contents/Resources/bin/weston-keyboard" \
      "$APP/Contents/MacOS/weston-keyboard"
    do
      if [ -x "$_wawona_c" ]; then
        _wawona_kbd="$_wawona_c"
        break
      fi
    done
    {
      printf '%s\n' "[core]" "use-pixman=false" "" "[shell]"
      if [ -n "$_wawona_shell" ]; then
        printf 'client=%s\n' "$_wawona_shell"
      fi
      if [ -n "$_wawona_kbd" ]; then
        printf 'input-method=%s\n' "$_wawona_kbd"
      fi
      printf '%s\n' "background-color=0xff1a1a2e"
      if [ -n "$weston_data" ] && [ -f "$weston_data/background.png" ]; then
        printf 'background-image=%s\n' "$weston_data/background.png"
        printf '%s\n' "background-type=scale"
      fi
      printf '%s\n' "panel-color=0xff101010" "panel-position=top" "clock-format=seconds"
    } > "$_wawona_ini"
    export WESTON_CONFIG_FILE="$_wawona_ini"
    unset _wawona_ini _wawona_shell _wawona_kbd _wawona_c
  fi
  # gl-renderer.so uses -undefined dynamic_lookup. Load the iland EGL shim
  # (Frameworks/libEGL.dylib) so nested weston gets Wayland-EGL + dmabuf.
  # ANGLE is libEGL_angle.dylib, opened by the shim. Never export DYLD_INSERT
  # for Apple /bin/* (arm64e).
  if [ -d "$APP/Contents/Frameworks" ]; then
    _wawona_egl="$APP/Contents/Frameworks/libEGL.dylib"
    _wawona_gles="$APP/Contents/Frameworks/libGLESv2.dylib"
    _wawona_clean_insert=""
    if [ -n "${DYLD_INSERT_LIBRARIES:-}" ]; then
      _wawona_oifs="$IFS"
      IFS=':'
      for _p in $DYLD_INSERT_LIBRARIES; do
        case "$_p" in
          *libViewDebuggerSupport*|*GPUToolsCapture*|*RealityKitInspection*|*DebugHierarchyFoundation*|*SpatialInspectorFoundation*) ;;
          "") ;;
          *) _wawona_clean_insert="${_wawona_clean_insert:+$_wawona_clean_insert:}$_p" ;;
        esac
      done
      IFS="$_wawona_oifs"
      unset _wawona_oifs _p
    fi
    _wawona_insert=""
    if [ -f "$_wawona_egl" ]; then
      _wawona_insert="$_wawona_egl"
    fi
    if [ -f "$_wawona_gles" ]; then
      _wawona_insert="${_wawona_insert:+$_wawona_insert:}$_wawona_gles"
    fi
    if [ -n "$_wawona_clean_insert" ]; then
      _wawona_insert="${_wawona_insert:+$_wawona_insert:}$_wawona_clean_insert"
    fi
    if [ -n "$_wawona_insert" ]; then
      export DYLD_INSERT_LIBRARIES="$_wawona_insert"
    fi
    unset _wawona_egl _wawona_gles _wawona_clean_insert _wawona_insert
  fi
fi

# CLI niri reads ~/Library/Application Support/niri/config.kdl. Only point
# at the bundled KDL when the user has not created one. Do not overwrite.
if [ "$NAME" = niri ] && [ -z "${NIRI_CONFIG:-}" ]; then
  _niri_user="${HOME}/Library/Application Support/niri/config.kdl"
  _niri_bundled=""
  for d in \
    "$APP/Contents/Resources/share/niri/default-config.kdl" \
    "$APP/share/niri/default-config.kdl"
  do
    if [ -f "$d" ]; then
      _niri_bundled="$d"
      break
    fi
  done
  if [ ! -f "$_niri_user" ] && [ -n "$_niri_bundled" ]; then
    export NIRI_CONFIG="$_niri_bundled"
  fi
  unset _niri_user _niri_bundled d
fi
