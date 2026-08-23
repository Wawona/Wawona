#!/bin/sh
# Register (or remove) host-PATH wrappers for every executable bundled in
# /Applications/Wawona.app. Called by `nix run .#install` / `.#uninstall`.
#
# Wrappers live in ~/.local/bin (and /usr/local/bin when writable). They point
# at the installed app, not a GC-able nix store path, and set Wayland plus
# weston/fontconfig env so `weston-terminal` works from a normal shell.
set -eu

MARKER="# Wawona CLI wrapper. Do not edit."
PATH_BEGIN="# BEGIN Wawona CLI bins (nix run .#install)"
PATH_END="# END Wawona CLI bins"
CLI_DIR="${HOME}/Library/Wawona/cli"
ENV_SH="${CLI_DIR}/env.sh"
MANIFEST="${HOME}/Library/Wawona/cli-bins.list"
LOCAL_BIN="${HOME}/.local/bin"

wawona_cli_skip_name() {
  name="$1"
  case "$name" in
    ""|Wawona|Wawona.debug|.foot-wrapped)
      return 0
      ;;
    .*|*.dylib|*.so)
      return 0
      ;;
    igettyd|igetty|modeb-ttyd|modeb-tty|modeb-getty)
      return 0
      ;;
  esac
  # Do not shadow Apple /bin and /usr/bin (ssh, zsh, vi, login, ...).
  if [ -x "/bin/${name}" ] || [ -x "/usr/bin/${name}" ]; then
    return 0
  fi
  return 1
}

wawona_cli_resolve() {
  app="$1"
  name="$2"
  for cand in \
    "${app}/Contents/Resources/bin/${name}" \
    "${app}/Contents/MacOS/${name}"
  do
    if [ -f "$cand" ] && [ -x "$cand" ]; then
      printf '%s\n' "$cand"
      return 0
    fi
  done
  return 1
}

wawona_cli_dest_dirs() {
  printf '%s\n' "$LOCAL_BIN"
  if [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
    printf '%s\n' /usr/local/bin
  fi
}

wawona_cli_write_env() {
  app="$1"
  mkdir -p "$CLI_DIR"
  cat > "$ENV_SH" <<EOF
#!/bin/sh
# Sourced by Wawona CLI wrappers. Rewritten by nix run .#install.
APP="\${WAWONA_CLI_APP:-${app}}"
NAME="\${WAWONA_CLI_NAME:-}"

WAWONA_CLI_BIN=""
for cand in \\
  "\$APP/Contents/Resources/bin/\$NAME" \\
  "\$APP/Contents/MacOS/\$NAME"
do
  if [ -f "\$cand" ] && [ -x "\$cand" ]; then
    WAWONA_CLI_BIN="\$cand"
    break
  fi
done
if [ -z "\$WAWONA_CLI_BIN" ]; then
  echo "wawona: bundled '\$NAME' missing in \$APP" >&2
  echo "Hint: nix run .#install" >&2
  exit 127
fi

uid="\$(id -u)"
runtime_dir_default="/tmp/wawona-\$uid"
runtime_env_file="\$runtime_dir_default/wawona-env.sh"
if [ -f "\$runtime_env_file" ]; then
  # shellcheck source=/dev/null
  . "\$runtime_env_file" || true
fi
export XDG_RUNTIME_DIR="\${XDG_RUNTIME_DIR:-\$runtime_dir_default}"
export WAYLAND_DISPLAY="\${WAYLAND_DISPLAY:-wayland-0}"
if [ ! -d "\$XDG_RUNTIME_DIR" ]; then
  mkdir -p "\$XDG_RUNTIME_DIR"
  chmod 700 "\$XDG_RUNTIME_DIR"
fi
SOCKET_PATH="\$XDG_RUNTIME_DIR/\$WAYLAND_DISPLAY"
if [ ! -S "\$SOCKET_PATH" ] && command -v launchctl >/dev/null 2>&1; then
  launchctl kickstart -k "gui/\$uid/com.aspauldingcode.wawona.compositorhost" >/dev/null 2>&1 || true
  if [ -f "\$runtime_env_file" ]; then
    # shellcheck source=/dev/null
    . "\$runtime_env_file" || true
    export XDG_RUNTIME_DIR="\${XDG_RUNTIME_DIR:-\$runtime_dir_default}"
    export WAYLAND_DISPLAY="\${WAYLAND_DISPLAY:-wayland-0}"
    SOCKET_PATH="\$XDG_RUNTIME_DIR/\$WAYLAND_DISPLAY"
  fi
  i=0
  while [ ! -S "\$SOCKET_PATH" ] && [ "\$i" -lt 50 ]; do
    sleep 0.1
    i=\$((i + 1))
  done
fi

export WAWONA_APP_BUNDLE_ROOT="\$APP"
export WAWONA_APP_BIN="\$APP/Contents/MacOS/Wawona"

share=""
for d in "\$APP/Contents/Resources/share" "\$APP/share"; do
  if [ -d "\$d" ]; then
    share="\$d"
    break
  fi
done
if [ -n "\$share" ]; then
  export WAWONA_SHARE_ROOT="\$share"
  export XDG_DATA_DIRS="\$share\${XDG_DATA_DIRS:+:\$XDG_DATA_DIRS}"
fi

lib=""
for d in "\$APP/Contents/Resources/lib" "\$APP/lib"; do
  if [ -d "\$d" ]; then
    lib="\$d"
    break
  fi
done
if [ -n "\$lib" ]; then
  export WAWONA_LIB_ROOT="\$lib"
fi

weston_data=""
for d in "\$APP/Contents/Resources/share/weston" "\$APP/share/weston"; do
  if [ -d "\$d" ]; then
    weston_data="\$d"
    break
  fi
done
if [ -n "\$weston_data" ]; then
  export WESTON_DATA_DIR="\$weston_data"
fi
weston_modules=""
for d in "\$APP/Contents/Resources/lib/weston" "\$APP/lib/weston"; do
  if [ -d "\$d" ]; then
    weston_modules="\$d"
    break
  fi
done
if [ -n "\$weston_modules" ]; then
  export WESTON_MODULE_DIR="\$weston_modules"
fi
weston_backends=""
for d in "\$APP/Contents/Resources/lib/libweston-13" "\$APP/lib/libweston-13"; do
  if [ -d "\$d" ]; then
    weston_backends="\$d"
    break
  fi
done
if [ -n "\$weston_backends" ]; then
  export WESTON_BACKEND_DIR="\$weston_backends"
fi

icons=""
for d in "\$APP/Contents/Resources/share/icons" "\$APP/share/icons"; do
  if [ -d "\$d" ]; then
    icons="\$d"
    break
  fi
done
if [ -n "\$icons" ]; then
  export XCURSOR_PATH="\$icons"
  export XCURSOR_THEME="Adwaita"
fi

fonts=""
for d in "\$APP/share/fonts" "\$APP/Contents/Resources/share/fonts"; do
  if [ -d "\$d" ]; then
    fonts="\$d"
    break
  fi
done
if [ -n "\$fonts" ]; then
  fc_dir="\${HOME}/Library/Caches/Wawona"
  mkdir -p "\$fc_dir/cache"
  fc_file="\$fc_dir/cli-fonts.conf"
  cat > "\$fc_file" <<FC
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <dir>\$fonts</dir>
  <cachedir>\$fc_dir/cache</cachedir>
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
  export FONTCONFIG_FILE="\$fc_file"
  export FONTCONFIG_PATH="\$fc_dir"
fi

if [ -d "\$APP/Contents/Frameworks" ]; then
  export DYLD_LIBRARY_PATH="\$APP/Contents/Frameworks\${DYLD_LIBRARY_PATH:+:\$DYLD_LIBRARY_PATH}"
fi
# Never export DYLD_INSERT_LIBRARIES here. Apple /bin/* is arm64e.

bin_dir="\$APP/Contents/Resources/bin"
if [ -d "\$bin_dir" ]; then
  export PATH="\$bin_dir:\$PATH"
fi

if [ "\$NAME" = weston ]; then
  export WAWONA_OUTPUT_SCALE="\${WAWONA_OUTPUT_SCALE:-1}"
  export WAWONA_NESTED_WAYLAND="\${WAWONA_NESTED_WAYLAND:-1}"
  if [ -z "\${WESTON_CONFIG_FILE:-}" ] && [ -n "\${XDG_RUNTIME_DIR:-}" ]; then
    _wawona_ini="\$XDG_RUNTIME_DIR/weston.ini"
    _wawona_shell=""
    _wawona_kbd=""
    for _wawona_c in \\
      "\$APP/Contents/Resources/bin/weston-desktop-shell" \\
      "\$APP/Contents/MacOS/weston-desktop-shell" \\
      "\$APP/Contents/Resources/libexec/weston-desktop-shell"
    do
      if [ -x "\$_wawona_c" ]; then
        _wawona_shell="\$_wawona_c"
        break
      fi
    done
    for _wawona_c in \\
      "\$APP/Contents/Resources/bin/weston-keyboard" \\
      "\$APP/Contents/MacOS/weston-keyboard"
    do
      if [ -x "\$_wawona_c" ]; then
        _wawona_kbd="\$_wawona_c"
        break
      fi
    done
    {
      printf '%s\n' "[core]" "use-pixman=false" "" "[shell]"
      if [ -n "\$_wawona_shell" ]; then
        printf 'client=%s\n' "\$_wawona_shell"
      fi
      if [ -n "\$_wawona_kbd" ]; then
        printf 'input-method=%s\n' "\$_wawona_kbd"
      fi
      printf '%s\n' "background-color=0xff1a1a2e" "panel-position=top"
    } > "\$_wawona_ini"
    export WESTON_CONFIG_FILE="\$_wawona_ini"
    unset _wawona_ini _wawona_shell _wawona_kbd _wawona_c
  fi
  # gl-renderer.so uses -undefined dynamic_lookup. Load the iland EGL shim
  # (Frameworks/libEGL.dylib) so nested weston gets Wayland-EGL + dmabuf.
  # ANGLE is libEGL_angle.dylib, opened by the shim. Never export DYLD_INSERT
  # for Apple /bin/* (arm64e).
  if [ -z "\${DYLD_INSERT_LIBRARIES:-}" ] && [ -d "\$APP/Contents/Frameworks" ]; then
    _wawona_egl="\$APP/Contents/Frameworks/libEGL.dylib"
    _wawona_gles="\$APP/Contents/Frameworks/libGLESv2.dylib"
    _wawona_insert=""
    if [ -f "\$_wawona_egl" ]; then
      _wawona_insert="\$_wawona_egl"
    fi
    if [ -f "\$_wawona_gles" ]; then
      _wawona_insert="\${_wawona_insert:+\$_wawona_insert:}\$_wawona_gles"
    fi
    if [ -n "\$_wawona_insert" ]; then
      export DYLD_INSERT_LIBRARIES="\$_wawona_insert"
    fi
    unset _wawona_egl _wawona_gles _wawona_insert
  fi
fi
EOF
  chmod 644 "$ENV_SH"
}

wawona_cli_write_wrapper() {
  dest="$1"
  app="$2"
  name="$3"
  cat > "$dest" <<EOF
#!/bin/sh
${MARKER}
export WAWONA_CLI_APP="${app}"
export WAWONA_CLI_NAME="${name}"
# shellcheck source=/dev/null
. "${ENV_SH}"
# Nested weston is a Wayland client of Wawona. Parent already scaled the
# NSWindow. --scale from wl_output (2 on Retina) doubles the desktop.
if [ "\$WAWONA_CLI_NAME" = weston ]; then
  export WAWONA_OUTPUT_SCALE="\${WAWONA_OUTPUT_SCALE:-1}"
  _wawona_has_backend=0
  _wawona_has_scale=0
  for _wawona_arg in "\$@"; do
    case "\$_wawona_arg" in
      --backend|--backend=*|-B) _wawona_has_backend=1 ;;
      --scale|--scale=*) _wawona_has_scale=1 ;;
    esac
  done
  if [ "\$_wawona_has_backend" -eq 0 ]; then
    set -- --backend=wayland --shell=desktop-shell.so "\$@"
  fi
  if [ "\$_wawona_has_scale" -eq 0 ]; then
    set -- --scale=1 "\$@"
  fi
  unset _wawona_has_backend _wawona_has_scale _wawona_arg
fi
exec "\$WAWONA_CLI_BIN" "\$@"
EOF
  chmod 755 "$dest"
}

wawona_cli_path_block() {
  printf '\n%s\n' "$PATH_BEGIN"
  printf '%s\n' '# nix-darwin /etc/zshenv sources this for every zsh, login or not.'
  printf '%s\n' 'if [ -d "$HOME/.local/bin" ]; then'
  printf '%s\n' '  PATH="$HOME/.local/bin:$PATH"'
  printf '%s\n' '  export PATH'
  printf '%s\n' 'fi'
  printf '%s\n' "$PATH_END"
}

wawona_cli_merge_path_file() {
  dest="$1"
  if [ -e "$dest" ] && grep -Fq "$PATH_BEGIN" "$dest" 2>/dev/null; then
    return 0
  fi
  wawona_cli_path_block >> "$dest"
}

wawona_cli_run_as_root() {
  script="$1"
  if [ "$(id -u)" -eq 0 ]; then
    /bin/sh "$script"
    return $?
  fi
  if sudo -n /bin/sh "$script" >/dev/null 2>&1; then
    return 0
  fi
  if command -v osascript >/dev/null 2>&1; then
    osascript -e "do shell script \"/bin/sh '$script'\" with administrator privileges" >/dev/null
    return $?
  fi
  return 1
}

wawona_cli_ensure_system_path() {
  dest=/etc/zshenv.local
  if [ -f "$dest" ] && grep -Fq "$PATH_BEGIN" "$dest" 2>/dev/null; then
    echo "PATH hook already present: $dest"
    return 0
  fi
  mkdir -p "$CLI_DIR"
  helper="${CLI_DIR}/install-zshenv-local.sh"
  block="${CLI_DIR}/path-block.sh"
  wawona_cli_path_block > "$block"
  cat > "$helper" <<EOF
#!/bin/sh
set -eu
dest=/etc/zshenv.local
begin='$PATH_BEGIN'
block='$block'
if [ -f "\$dest" ] && /usr/bin/grep -Fq "\$begin" "\$dest"; then
  exit 0
fi
/bin/cat "\$block" >> "\$dest"
/bin/chmod 644 "\$dest"
EOF
  chmod 755 "$helper"
  if wawona_cli_run_as_root "$helper"; then
    echo "PATH hook installed for all zsh: $dest"
    return 0
  fi
  echo "Note: could not write $dest (needs administrator once)." >&2
  echo "  Cursor and nested zsh are not login shells, so ~/.zprofile is skipped." >&2
  echo "  This shell: export PATH=\"\$HOME/.local/bin:\$PATH\"" >&2
  echo "  Or add home.sessionPath = [ \"\$HOME/.local/bin\" ]; and rebuild." >&2
  return 1
}

wawona_cli_strip_system_path() {
  dest=/etc/zshenv.local
  [ -f "$dest" ] || return 0
  grep -Fq "$PATH_BEGIN" "$dest" 2>/dev/null || return 0
  mkdir -p "$CLI_DIR"
  helper="${CLI_DIR}/strip-zshenv-local.sh"
  cat > "$helper" <<'EOF'
#!/bin/sh
set -eu
dest=/etc/zshenv.local
begin='# BEGIN Wawona CLI bins (nix run .#install)'
end='# END Wawona CLI bins'
[ -f "$dest" ] || exit 0
tmp="${dest}.wawona-cli.tmp"
awk -v begin="$begin" -v end="$end" '
  $0 == begin { skip = 1; next }
  $0 == end { skip = 0; next }
  skip { next }
  { print }
' "$dest" > "$tmp"
mv "$tmp" "$dest"
if [ ! -s "$dest" ]; then
  rm -f "$dest"
fi
EOF
  chmod 755 "$helper"
  wawona_cli_run_as_root "$helper" || true
}

wawona_cli_ensure_path() {
  for rc in "${HOME}/.zprofile" "${HOME}/.zshrc" "${HOME}/.bash_profile"; do
    if [ -e "$rc" ] && grep -Fq "$PATH_BEGIN" "$rc" 2>/dev/null; then
      continue
    fi
    if [ -e "$rc" ] && [ ! -w "$rc" ]; then
      echo "Note: $rc is not writable (home-manager)." >&2
      continue
    fi
    if [ -f "$rc" ] || [ "$rc" = "${HOME}/.zprofile" ]; then
      if [ ! -e "$rc" ]; then
        if ! printf '' > "$rc" 2>/dev/null; then
          echo "Note: could not create $rc" >&2
          continue
        fi
      fi
      if wawona_cli_merge_path_file "$rc" 2>/dev/null; then
        :
      else
        echo "Note: could not append PATH snippet to $rc" >&2
      fi
    fi
  done
  wawona_cli_ensure_system_path || true
}

wawona_cli_strip_path() {
  wawona_cli_strip_system_path
  for rc in "${HOME}/.zprofile" "${HOME}/.zshrc" "${HOME}/.bash_profile"; do
    [ -f "$rc" ] && [ -w "$rc" ] || continue
    grep -Fq "$PATH_BEGIN" "$rc" || continue
    tmp="${rc}.wawona-cli.tmp"
    awk -v begin="$PATH_BEGIN" -v end="$PATH_END" '
      $0 == begin { skip = 1; next }
      $0 == end { skip = 0; next }
      skip { next }
      { print }
    ' "$rc" > "$tmp"
    mv "$tmp" "$rc"
  done
}

wawona_cli_is_ours() {
  path="$1"
  [ -f "$path" ] || return 1
  grep -Fq "$MARKER" "$path"
}

wawona_cli_clear_wrappers() {
  if [ -f "$MANIFEST" ]; then
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      if wawona_cli_is_ours "$path"; then
        rm -f "$path"
      fi
    done < "$MANIFEST"
  fi
  for dir in "$LOCAL_BIN" /usr/local/bin; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*; do
      [ -f "$f" ] || continue
      if wawona_cli_is_ours "$f"; then
        rm -f "$f"
      fi
    done
  done
  rm -f "$MANIFEST"
}

wawona_cli_unregister() {
  wawona_cli_clear_wrappers
  wawona_cli_strip_path
  rm -rf "$CLI_DIR"
}

wawona_cli_register() {
  app="$1"
  if [ -z "$app" ] || [ ! -d "$app" ]; then
    echo "Error: Wawona.app missing at ${app:-"(unset)"}" >&2
    exit 1
  fi
  wawona_cli_clear_wrappers
  wawona_cli_write_env "$app"
  mkdir -p "$LOCAL_BIN" "$(dirname "$MANIFEST")"
  : > "$MANIFEST"

  names=""
  seen=""
  for dir in "${app}/Contents/Resources/bin" "${app}/Contents/MacOS"; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*; do
      [ -e "$f" ] || continue
      name="$(basename "$f")"
      if wawona_cli_skip_name "$name"; then
        continue
      fi
      case " $seen " in
        *" $name "*) continue ;;
      esac
      if ! wawona_cli_resolve "$app" "$name" >/dev/null; then
        continue
      fi
      seen="$seen $name"
      names="$names $name"
      for dest_dir in $(wawona_cli_dest_dirs); do
        mkdir -p "$dest_dir"
        dest="${dest_dir}/${name}"
        wawona_cli_write_wrapper "$dest" "$app" "$name"
        printf '%s\n' "$dest" >> "$MANIFEST"
      done
    done
  done

  # Convenience alias for the app binary itself (MacOS/Wawona).
  if [ -x "${app}/Contents/MacOS/Wawona" ]; then
    for dest_dir in $(wawona_cli_dest_dirs); do
      dest="${dest_dir}/wawona"
      if [ ! -e "$dest" ] || wawona_cli_is_ours "$dest"; then
        wawona_cli_write_wrapper "$dest" "$app" "Wawona"
        printf '%s\n' "$dest" >> "$MANIFEST"
      fi
    done
    names="$names wawona"
  fi

  wawona_cli_ensure_path
  count=$(printf '%s\n' $names | grep -c . || true)
  echo "Registered ${count} Wawona CLI tools in ${LOCAL_BIN}"
  echo "  examples: weston-terminal niri foot kmscube waypipe"
  echo "  skipped Apple-shadowing names (ssh, zsh, vi, ...): use the bundle bin/"
  echo "Already-open shells: export PATH=\"\$HOME/.local/bin:\$PATH\""
}

usage() {
  echo "usage: macos-register-cli-bins.sh register <Wawona.app>" >&2
  echo "       macos-register-cli-bins.sh unregister" >&2
  exit 2
}

cmd="${1:-}"
case "$cmd" in
  register)
    wawona_cli_register "${2:-}"
    ;;
  unregister)
    wawona_cli_unregister
    echo "Removed Wawona CLI wrappers from PATH."
    ;;
  *)
    usage
    ;;
esac
