#!/usr/bin/env bash
# Build WawonaAgent.pkg for the macOS DMG.
#
# Hybrid installer: the pkg PAYLOAD installs /Applications/Wawona.app AND the
# postinstall writes + loads the compositor + menubar LaunchAgents and publishes
# XDG_RUNTIME_DIR / WAYLAND_DISPLAY into the user launchd domain so Wayland
# clients can connect without the Wawona UI being open.
#
# A user can either drag Wawona.app to /Applications (classic) OR just open this
# pkg for a complete install (app + agents). Both are supported; the DMG ships
# both the loose app and this pkg.
#
# Usage:
#   WAWONA_APP_SRC=/path/to/Wawona.app WAWONA_VERSION=26.8.8 \
#     scripts/macos-launch-agent-pkg.sh /out/WawonaAgent.pkg
#
# Env:
#   WAWONA_APP_SRC   REQUIRED. Path to a built Wawona.app to embed in the payload.
#   WAWONA_VERSION   pkg version (defaults to VERSION file).
#   WAWONA_PKG_ID    pkg identifier (default com.aspauldingcode.wawona.agent).
#   WAWONA_INSTALL_USERS  (install time, root only) comma/space list of extra
#                    local short usernames to install agents for. Default: the
#                    console user. GUI double-click cannot pass this; it is the
#                    admin CLI path: sudo WAWONA_INSTALL_USERS=alice,bob installer …
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/WawonaAgent.pkg}"
IDENTIFIER="${WAWONA_PKG_ID:-com.aspauldingcode.wawona.agent}"
VERSION="${WAWONA_VERSION:-$(cat "$ROOT/VERSION" 2>/dev/null || echo 0.0.0)}"
APP_SRC="${WAWONA_APP_SRC:-}"

if [[ -z "$APP_SRC" || ! -d "$APP_SRC" ]]; then
  echo "error: WAWONA_APP_SRC must point at a built Wawona.app (got: '${APP_SRC:-<unset>}')" >&2
  exit 2
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/wawona-agent-pkg.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

PAYLOAD="$WORKDIR/payload"
SCRIPTS="$WORKDIR/scripts"
mkdir -p "$PAYLOAD/Applications" "$SCRIPTS"

# Payload installs the app to /Applications. Same bits the DMG offers for drag.
ditto "$APP_SRC" "$PAYLOAD/Applications/Wawona.app"
# GHA artifact zip can drop +x; restore before packaging.
chmod -R u+w "$PAYLOAD/Applications/Wawona.app"
find "$PAYLOAD/Applications/Wawona.app/Contents/MacOS" -type f -exec chmod +x {} + 2>/dev/null || true
find "$PAYLOAD/Applications/Wawona.app/Contents/Resources/bin" -type f -exec chmod +x {} + 2>/dev/null || true
# Avoid AppleDouble (._*) junk in the payload on macOS.
find "$PAYLOAD" -name '._*' -delete 2>/dev/null || true
find "$PAYLOAD" -name '.DS_Store' -delete 2>/dev/null || true

cat >"$SCRIPTS/postinstall" <<'EOF'
#!/bin/bash
set -euo pipefail

APP_EXEC="/Applications/Wawona.app/Contents/MacOS/Wawona"
COMPOSITOR_LABEL="com.aspauldingcode.wawona.compositorhost"
MENUBAR_LABEL="com.aspauldingcode.wawona.menubar"

# The payload installs the app; this is a safety net if it is somehow missing.
if [[ ! -x "$APP_EXEC" ]]; then
  echo "error: $APP_EXEC not found after payload install." >&2
  exit 1
fi

RUNNING_UID="$(id -u)"

# Resolve the set of target users. Default: console user. When run as root an
# admin may pass WAWONA_INSTALL_USERS=user1,user2 to install for more accounts.
resolve_target_users() {
  if [[ "$RUNNING_UID" -eq 0 && -n "${WAWONA_INSTALL_USERS:-}" ]]; then
    printf '%s\n' "$WAWONA_INSTALL_USERS" | tr ',' ' '
    return
  fi
  local console_uid console_user
  console_uid="$(stat -f %u /dev/console 2>/dev/null || echo "")"
  if [[ -z "$console_uid" || "$console_uid" == "0" ]]; then
    console_uid="$RUNNING_UID"
  fi
  id -un "$console_uid"
}

write_agent() {
  # $1 label  $2 mode  $3 log_prefix  $4 launch_agents_dir  $5 runtime_dir  $6 owner
  local label="$1" mode="$2" log_prefix="$3" la_dir="$4" runtime_dir="$5" owner="$6"
  local uid
  uid="$(id -u "$owner")"
  local plist_path="$la_dir/$label.plist"
  cat >"$plist_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>$APP_EXEC</string>
    <string>$mode</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>5</integer>
  <key>StandardOutPath</key>
  <string>/tmp/$log_prefix-$uid.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/$log_prefix-$uid.error.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>XDG_RUNTIME_DIR</key>
    <string>$runtime_dir</string>
    <key>WAYLAND_DISPLAY</key>
    <string>wayland-0</string>
    <key>WAWONA_SKIP_LAUNCH_AGENT_BOOTSTRAP</key>
    <string>1</string>
  </dict>
</dict>
</plist>
PLIST
  chown "$owner" "$plist_path" 2>/dev/null || true
}

install_for_user() {
  local user="$1"
  local uid home la_dir runtime_dir domain
  uid="$(id -u "$user" 2>/dev/null || echo "")"
  if [[ -z "$uid" ]]; then
    echo "error: user '$user' does not exist" >&2
    return 1
  fi
  home="$(dscl . -read "/Users/$user" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
  if [[ -z "${home:-}" ]]; then
    home="$(eval echo "~$user")"
  fi
  la_dir="$home/Library/LaunchAgents"
  runtime_dir="/tmp/wawona-$uid"
  domain="gui/$uid"

  mkdir -p "$la_dir" "$runtime_dir"
  chmod 700 "$runtime_dir" || true
  chown "$user" "$la_dir" "$runtime_dir" 2>/dev/null || true

  as_user() {
    if [[ "$RUNNING_UID" -eq 0 ]]; then
      launchctl asuser "$uid" "$@"
    else
      "$@"
    fi
  }

  ensure_loaded() {
    local label="$1"
    local target="$domain/$label"
    as_user launchctl bootout "$target" >/dev/null 2>&1 || true
    as_user launchctl bootstrap "$domain" "$la_dir/$label.plist"
    as_user launchctl kickstart -k "$target" >/dev/null 2>&1 || true
  }

  write_agent "$COMPOSITOR_LABEL" "--compositor-host" "wawona-compositor" "$la_dir" "$runtime_dir" "$user"
  write_agent "$MENUBAR_LABEL" "--menubar" "wawona-menubar" "$la_dir" "$runtime_dir" "$user"
  ensure_loaded "$COMPOSITOR_LABEL"
  ensure_loaded "$MENUBAR_LABEL"

  # Session-wide env so GUI/CLI Wayland clients can find Wawona's socket without
  # the main app window being open (compositor-host agent owns the socket).
  as_user launchctl setenv XDG_RUNTIME_DIR "$runtime_dir" || true
  as_user launchctl setenv WAYLAND_DISPLAY wayland-0 || true

  PANE_SRC="/Applications/Wawona.app/Contents/Resources/PreferencePanes/Wawona.prefPane"
  if [[ -d "$PANE_SRC" ]]; then
    home="$(dscl . -read "/Users/$user" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
    if [[ -n "$home" ]]; then
      mkdir -p "$home/Library/PreferencePanes"
      rm -rf "$home/Library/PreferencePanes/Wawona.prefPane"
      ditto "$PANE_SRC" "$home/Library/PreferencePanes/Wawona.prefPane"
      chown -R "$user" "$home/Library/PreferencePanes/Wawona.prefPane" || true
    fi
  fi

  echo "Wawona LaunchAgents installed for $user:"
  echo "  - $COMPOSITOR_LABEL"
  echo "  - $MENUBAR_LABEL"
  echo "  Published: XDG_RUNTIME_DIR=$runtime_dir WAYLAND_DISPLAY=wayland-0"
}

PANE_SRC="/Applications/Wawona.app/Contents/Resources/PreferencePanes/Wawona.prefPane"
if [[ -d "$PANE_SRC" ]]; then
  mkdir -p /Library/PreferencePanes
  rm -rf /Library/PreferencePanes/Wawona.prefPane
  ditto "$PANE_SRC" /Library/PreferencePanes/Wawona.prefPane
  echo "Installed System Settings pane: /Library/PreferencePanes/Wawona.prefPane"
else
  echo "warning: Wawona.prefPane missing in app bundle" >&2
fi

if [[ -x "$APP_EXEC" ]]; then
  echo "Staging Desktop Replacement helper (no Take Over)..."
  "$APP_EXEC" --mode-b-stage || echo "warning: Desktop Replacement helper install failed; open Wawona once or use Settings → Desktop → Enable" >&2
fi

rc=0
for user in $(resolve_target_users); do
  install_for_user "$user" || rc=1
done
exit $rc
EOF
chmod 755 "$SCRIPTS/postinstall"
# Avoid AppleDouble (._*) junk in the Scripts payload on macOS.
rm -f "$SCRIPTS"/._* "$SCRIPTS"/.DS_Store

COPYFILE_DISABLE=1 pkgbuild \
  --root "$PAYLOAD" \
  --scripts "$SCRIPTS" \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  --install-location "/" \
  "$OUT"

echo "Built $OUT"
ls -lah "$OUT"
