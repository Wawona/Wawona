#!/bin/bash
# Run as 8amps (admin) or root to stop Mode B login WindowServer crash loop.
# Usage: bash /tmp/WAWONA_MODEB_RECOVERY_2026-08-19.sh

set -euo pipefail
LOG=/tmp/wawona-modeb.log
UID8=$(id -u 8amps 2>/dev/null || echo 503)

echo "[1/8] Restore Aqua / kill Mode B compositor..."
sudo -n "/Library/Application Support/Wawona/run-modeb.sh" --restore-aqua 2>/dev/null || \
  sudo "/Library/Application Support/Wawona/run-modeb.sh" --restore-aqua || true

echo "[2/8] Boot out login LaunchAgent..."
launchctl bootout "gui/${UID8}/com.aspauldingcode.wawona.modeb-login" 2>/dev/null || true
sudo launchctl bootout "gui/${UID8}/com.aspauldingcode.wawona.modeb-login" 2>/dev/null || true

echo "[3/8] Remove login agent plist..."
rm -f "/Users/8amps/Library/LaunchAgents/com.aspauldingcode.wawona.modeb-login.plist" \
      "/Users/8amps/Library/LaunchAgents/com.aspauldingcode.wawona.modeb-login.plist.DISABLED" 2>/dev/null || true

echo "[4/8] Disable Desktop Replacement pref..."
defaults write com.aspauldingcode.wawona DesktopReplacementEnabled -bool false
defaults read com.aspauldingcode.wawona DesktopReplacementEnabled

echo "[5/8] Kill stray root helpers/compositors..."
sudo pkill -KILL -f '/Library/Application Support/Wawona/run-modeb.sh' 2>/dev/null || true
sudo pkill -KILL -x niri 2>/dev/null || true
sudo pkill -KILL -x weston 2>/dev/null || true
sudo pkill -KILL -x framebufferd 2>/dev/null || true
sudo pkill -KILL -x inputd 2>/dev/null || true
sudo rm -rf /tmp/libwayland-support/modeb.lock /tmp/libwayland-support/modeb-compositor.pid

echo "[6/8] Replace helper with safe stub + lock sudoers..."
sudo tee "/Library/Application Support/Wawona/run-modeb.sh" >/dev/null <<'EOF'
#!/bin/bash
# DISABLED 2026-08-19: Mode B login crash loop. See docs/incident-reports.
LOG=/tmp/wawona-modeb.log
printf "%s Mode B helper DISABLED (recovery stub). args=%s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"
WS_PLIST=/System/Library/LaunchDaemons/com.apple.WindowServer.plist
/bin/launchctl enable system/com.apple.WindowServer >/dev/null 2>&1 || true
/bin/launchctl load -w "$WS_PLIST" >/dev/null 2>&1 || true
/bin/launchctl bootstrap system "$WS_PLIST" >/dev/null 2>&1 || true
/bin/launchctl kickstart -kp system/com.apple.WindowServer >/dev/null 2>&1 || true
exit 0
EOF
sudo chmod 755 "/Library/Application Support/Wawona/run-modeb.sh"
sudo chown root:wheel "/Library/Application Support/Wawona/run-modeb.sh"

sudo tee /etc/sudoers.d/wawona-modeb >/dev/null <<'EOF'
# Wawona Mode B recovery lockdown 2026-08-19
Defaults:8amps !requiretty
8amps ALL=(root) NOPASSWD: /Library/Application\ Support/Wawona/run-modeb.sh --restore-aqua
EOF
sudo chmod 440 /etc/sudoers.d/wawona-modeb
sudo visudo -cf /etc/sudoers.d/wawona-modeb

echo "[7/8] Restore WindowServer..."
sudo launchctl bootout system/com.aspauldingcode.wawona.ws-guard 2>/dev/null || true
sudo launchctl enable system/com.apple.WindowServer || true
sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.WindowServer.plist || true
sudo launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.WindowServer.plist 2>/dev/null || true
if ! pgrep -x WindowServer >/dev/null; then
  sudo launchctl kickstart -kp system/com.apple.WindowServer || true
fi

echo "[8/8] Verify..."
launchctl print system/com.apple.WindowServer 2>&1 | rg 'state =|pid =' || true
pgrep -lf 'run-modeb|niri|framebufferd' || echo 'no modeb processes'
ls "/Users/8amps/Library/LaunchAgents/" 2>/dev/null | rg modeb || echo 'no modeb launch agents'
echo "Recovery complete. Log stub writes to $LOG"
