#!/bin/sh
@MARKER@
export WAWONA_CLI_APP="@APP@"
export WAWONA_CLI_NAME="@NAME@"
# shellcheck source=/dev/null
. "@ENV_SH@"
# Nested weston is a Wayland client of Wawona. Parent already scaled the
# NSWindow. --scale from wl_output (2 on Retina) doubles the desktop.
if [ "$WAWONA_CLI_NAME" = weston ]; then
  export WAWONA_OUTPUT_SCALE="${WAWONA_OUTPUT_SCALE:-1}"
  _wawona_has_backend=0
  _wawona_has_scale=0
  _wawona_has_config=0
  _wawona_has_socket=0
  for _wawona_arg in "$@"; do
    case "$_wawona_arg" in
      --backend|--backend=*|-B) _wawona_has_backend=1 ;;
      --scale|--scale=*) _wawona_has_scale=1 ;;
      --config|--config=*|-c) _wawona_has_config=1 ;;
      --socket|--socket=*) _wawona_has_socket=1 ;;
    esac
  done
  if [ "${WAWONA_CLI_NESTED_PARENT:-0}" = 1 ] || [ "${MODEB:-0}" -eq 0 ]; then
    if [ "$_wawona_has_backend" -eq 0 ]; then
      set -- --backend=wayland --shell=desktop-shell.so "$@"
    fi
    if [ "$_wawona_has_scale" -eq 0 ]; then
      set -- --scale=1 "$@"
    fi
  else
    if [ "$_wawona_has_backend" -eq 0 ]; then
      set -- --backend=drm "$@"
    fi
  fi
  # WESTON_CONFIG_FILE is a basename for XDG search, not a path. Machines
  # Start passes --config=. Without it, CLI weston ignores the written ini
  # ("Starting with no config file") and execs baked nix-store libexec
  # helpers.
  if [ "$_wawona_has_config" -eq 0 ] && [ -n "${WESTON_CONFIG_FILE:-}" ] && [ -f "$WESTON_CONFIG_FILE" ]; then
    set -- --config="$WESTON_CONFIG_FILE" "$@"
  fi
  # Default listen socket is wayland-1 (parent is wayland-0). A leftover
  # lockfile prints "unable to lock lockfile … wayland-1.lock". Unique name
  # so CLI weston does not collide with Machines --socket=wawona-nested
  # or with an outer weston/niri.
  if [ "$_wawona_has_socket" -eq 0 ] && {
    [ "${WAWONA_CLI_NESTED_PARENT:-0}" = 1 ] || [ "${MODEB:-0}" -eq 0 ]
  }; then
    set -- --socket="weston-cli-$$" "$@"
  fi
  unset _wawona_has_backend _wawona_has_scale _wawona_has_config _wawona_has_socket _wawona_arg
fi
if [ "${MODEB:-0}" -eq 1 ] && [ "${WAWONA_CLI_NESTED_PARENT:-0}" != 1 ] && {
  [ "$WAWONA_CLI_NAME" = weston ] || [ "$WAWONA_CLI_NAME" = niri ]
}; then
  if [ -z "${WWN_MODEB_INSERT:-}" ] && [ -r /tmp/libwayland-support/modeb-insert ]; then
    WWN_MODEB_INSERT=$(sed -n '1p' /tmp/libwayland-support/modeb-insert)
    export WWN_MODEB_INSERT
  fi
  if [ -z "${WWN_MODEB_INSERT:-}" ]; then
    echo "wawona: WWN_MODEB_INSERT unset. Type $NAME after Classic Take Over." >&2
    echo "Never sudo $NAME. iland userspace DRM is the insert, not /dev/dri." >&2
    exit 1
  fi
  export DYLD_INSERT_LIBRARIES="$WWN_MODEB_INSERT"
fi
exec "$WAWONA_CLI_BIN" "$@"
