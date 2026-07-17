#!/usr/bin/env bash
# Build Wawona-LaunchAgents.pkg for the macOS DMG.
# Installs compositor + menubar LaunchAgents pointing at /Applications/Wawona.app
# and publishes XDG_RUNTIME_DIR / WAYLAND_DISPLAY into the user launchd domain
# so Wayland clients can connect without the Wawona UI being open.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/Wawona-LaunchAgents.pkg}"
APP_EXEC="${WAWONA_APP_EXEC:-/Applications/Wawona.app/Contents/MacOS/Wawona}"
IDENTIFIER="${WAWONA_PKG_ID:-com.aspauldingcode.wawona.launchagents}"
VERSION="${WAWONA_VERSION:-$(cat "$ROOT/VERSION" 2>/dev/null || echo 0.0.0)}"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/wawona-launchagents-pkg.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

PAYLOAD="$WORKDIR/payload"
SCRIPTS="$WORKDIR/scripts"
mkdir -p "$PAYLOAD" "$SCRIPTS"

# Payload is intentionally empty — agents are written at install time so they
# can resolve the console user's home and /Applications path.
cat >"$SCRIPTS/postinstall" <<'EOF'
#!/bin/bash
set -euo pipefail

APP_EXEC="/Applications/Wawona.app/Contents/MacOS/Wawona"
COMPOSITOR_LABEL="com.aspauldingcode.wawona.compositorhost"
MENUBAR_LABEL="com.aspauldingcode.wawona.menubar"

if [[ ! -x "$APP_EXEC" ]]; then
  echo "error: $APP_EXEC not found. Drag Wawona.app into /Applications first, then re-run this package." >&2
  exit 1
fi

CONSOLE_UID="$(stat -f %u /dev/console 2>/dev/null || echo "")"
if [[ -z "$CONSOLE_UID" || "$CONSOLE_UID" == "0" ]]; then
  # Fallback: installing user (non-root pkg installs run as the user).
  CONSOLE_UID="$(id -u)"
fi
CONSOLE_USER="$(id -un "$CONSOLE_UID")"
HOME_DIR="$(dscl . -read "/Users/$CONSOLE_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
if [[ -z "${HOME_DIR:-}" ]]; then
  HOME_DIR=$(eval echo "~$CONSOLE_USER")
fi

LAUNCH_AGENTS_DIR="$HOME_DIR/Library/LaunchAgents"
RUNTIME_DIR="/tmp/wawona-$CONSOLE_UID"
DOMAIN="gui/$CONSOLE_UID"

mkdir -p "$LAUNCH_AGENTS_DIR"
mkdir -p "$RUNTIME_DIR"
chmod 700 "$RUNTIME_DIR" || true
chown "$CONSOLE_USER" "$LAUNCH_AGENTS_DIR" "$RUNTIME_DIR" 2>/dev/null || true

write_agent() {
  local label="$1" mode="$2" log_prefix="$3"
  local plist_path="$LAUNCH_AGENTS_DIR/$label.plist"
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
  <string>/tmp/$log_prefix-$CONSOLE_UID.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/$log_prefix-$CONSOLE_UID.error.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>XDG_RUNTIME_DIR</key>
    <string>$RUNTIME_DIR</string>
    <key>WAYLAND_DISPLAY</key>
    <string>wayland-0</string>
    <key>WAWONA_SKIP_LAUNCH_AGENT_BOOTSTRAP</key>
    <string>1</string>
  </dict>
</dict>
</plist>
PLIST
  chown "$CONSOLE_USER" "$plist_path" 2>/dev/null || true
}

as_user() {
  if [[ "$(id -u)" -eq 0 ]]; then
    launchctl asuser "$CONSOLE_UID" "$@"
  else
    "$@"
  fi
}

ensure_loaded() {
  local label="$1"
  local plist_path="$LAUNCH_AGENTS_DIR/$label.plist"
  local target="$DOMAIN/$label"
  as_user launchctl bootout "$target" >/dev/null 2>&1 || true
  as_user launchctl bootstrap "$DOMAIN" "$plist_path"
  as_user launchctl kickstart -k "$target" >/dev/null 2>&1 || true
}

write_agent "$COMPOSITOR_LABEL" "--compositor-host" "wawona-compositor"
write_agent "$MENUBAR_LABEL" "--menubar" "wawona-menubar"
ensure_loaded "$COMPOSITOR_LABEL"
ensure_loaded "$MENUBAR_LABEL"

# Session-wide env so GUI/CLI Wayland clients can find Wawona's socket without
# the main app window being open (compositor-host agent owns the socket).
as_user launchctl setenv XDG_RUNTIME_DIR "$RUNTIME_DIR" || true
as_user launchctl setenv WAYLAND_DISPLAY wayland-0 || true

echo "Wawona LaunchAgents installed for $CONSOLE_USER:"
echo "  - $COMPOSITOR_LABEL"
echo "  - $MENUBAR_LABEL"
echo "Published: XDG_RUNTIME_DIR=$RUNTIME_DIR WAYLAND_DISPLAY=wayland-0"
exit 0
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
