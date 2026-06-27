#!/bin/bash
#
# Install weston as a launchd daemon.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_NAME="com.myland.weston.plist"
PLIST_DST="/Library/LaunchDaemons/$PLIST_NAME"

if [ "$1" = "-u" ]; then
    echo "=== Uninstalling weston daemon ==="
    sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.WindowServer.plist
    sudo launchctl unload "$PLIST_DST" 2>/dev/null || true
    sudo rm -f "$PLIST_DST"
    echo "=== Daemon removed ==="
    exit 0
fi

echo "=== Installing weston daemon ==="

# Generate plist with correct path
sudo tee "$PLIST_DST" > /dev/null << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.myland.weston</string>
    <key>ProgramArguments</key>
    <array>
        <string>${SCRIPT_DIR}/run-weston.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
	<key>POSIXSpawnType</key>
	<string>Interactive</string>
	<key>EnablePressuredExit</key>
	<false/>
    <key>StandardOutPath</key>
    <string>/tmp/weston-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/weston-stderr.log</string>
    <key>WorkingDirectory</key>
    <string>${SCRIPT_DIR}</string>
</dict>
</plist>
PLIST

# Set ownership and permissions
chown root:wheel "$PLIST_DST"
chmod 644 "$PLIST_DST"

# Unload if already loaded
sudo launchctl unload "$PLIST_DST" 2>/dev/null || true

# Load
sudo launchctl load "$PLIST_DST"

echo "=== Daemon installed: $PLIST_DST ==="
echo "=== Start with: sudo launchctl load -w $PLIST_DST ==="
echo "=== Stop with: sudo launchctl unload $PLIST_DST ==="
sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.WindowServer.plist
