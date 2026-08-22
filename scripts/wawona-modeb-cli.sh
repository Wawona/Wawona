#!/bin/bash
# Headless Desktop Replacement (Mode B) operator. Same jobs as
# Wawona --mode-b-status / --mode-b-probe / --mode-b-engage / --mode-b-disengage.
# Logs to stdout and /tmp/wawona-modeb-cli.log so an agent can drive Take Over
# without the Machines UI.
set -u
CLI_LOG=/tmp/wawona-modeb-cli.log
HELPER_LOG=/tmp/wawona-modeb.log
PIDFILE=/tmp/libwayland-support/modeb-compositor.pid
REASON=/tmp/wawona-modeb-failed.reason
LOCK=/tmp/libwayland-support/modeb.lock
HELPER="/Library/Application Support/Wawona/run-modeb.sh"
LABEL=com.aspauldingcode.wawona.modeb-login
UID_NUM="$(id -u)"
TARGET="gui/${UID_NUM}/${LABEL}"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$CLI_LOG"
}

pid_live() {
  local pid="${1:-0}"
  python3 -c '
import os, errno, sys
pid = int(sys.argv[1])
if pid <= 0:
    sys.exit(1)
try:
    os.kill(pid, 0)
    sys.exit(0)
except OSError as e:
    sys.exit(0 if e.errno == errno.EPERM else 1)
' "$pid"
}

read_pid() {
  if [ -f "$PIDFILE" ]; then
    tr -d '[:space:]' < "$PIDFILE"
  else
    echo 0
  fi
}

ws_up() {
  launchctl print system/com.apple.WindowServer >/dev/null 2>&1
}

cmd_status() {
  local pid raw kr
  raw="$(read_pid)"
  pid=0
  if pid_live "$raw"; then
    pid="$raw"
  fi
  log "mode-b-status"
  log "  sip:"
  csrutil status 2>/dev/null | tee -a "$CLI_LOG" | sed 's/^/    /'
  log "  DesktopReplacementEnabled=$(defaults read com.aspauldingcode.Wawona DesktopReplacementEnabled 2>/dev/null || echo missing)"
  log "  DesktopReplacementMachineId=$(defaults read com.aspauldingcode.Wawona DesktopReplacementMachineId 2>/dev/null || echo missing)"
  log "  helper=$HELPER executable=$( [ -x "$HELPER" ] && echo 1 || echo 0 )"
  log "  sudoers helper: $(sudo -n -l 2>/dev/null | grep -c run-modeb.sh || true) matches"
  log "  pidfile=$raw live=$pid"
  if [ "$raw" != 0 ] && [ -n "$raw" ]; then
    python3 -c '
import os, errno, sys
pid=int(sys.argv[1])
try:
    os.kill(pid,0); print("  kill0=0 errno=0")
except OSError as e:
    print("  kill0=-1 errno=%d (%s)" % (e.errno, errno.errorcode.get(e.errno, "?")))
' "$raw" | tee -a "$CLI_LOG"
    ps -p "$raw" -o pid,user,ppid,stat,etime,command 2>/dev/null | tee -a "$CLI_LOG" || true
  fi
  log "  WindowServer=$(ws_up && echo 1 || echo 0) loginAgent=$(launchctl print "$TARGET" >/dev/null 2>&1 && echo 1 || echo 0)"
  log "  helper-log:"
  if [ -f "$HELPER_LOG" ]; then
    tail -n 40 "$HELPER_LOG" | tee -a "$CLI_LOG"
  else
    log "    (missing)"
  fi
  if [ -f "$REASON" ]; then
    log "  fail-reason=$(cat "$REASON")"
  fi
  if [ "$pid" != 0 ]; then
    log "RESULT live compositor pid=$pid"
    return 0
  fi
  log "RESULT no live compositor pid"
  return 1
}

cmd_probe() {
  log "mode-b-probe"
  local raw
  raw="$(read_pid)"
  if pid_live "$raw"; then
    log "probe: live root compositor pid=$raw (EPERM-aware). Not restarting."
    log "RESULT success pid=$raw"
    return 0
  fi
  log "probe: no live pid (pidfile=$raw). Not starting a helper that would unload WindowServer."
  return 1
}

cmd_disengage() {
  log "mode-b-disengage"
  defaults write com.aspauldingcode.Wawona DesktopReplacementEnabled -bool false
  launchctl bootout "$TARGET" >/dev/null 2>&1 || true
  sudo -n "$HELPER" --restore-aqua >>"$CLI_LOG" 2>&1 || true
  sleep 1
  local pid
  pid="$(read_pid)"
  log "after disengage pidfile=$pid live=$(pid_live "$pid" && echo 1 || echo 0) WindowServer=$(ws_up && echo 1 || echo 0)"
  if ws_up && ! pid_live "$pid"; then
    log "RESULT aqua restored"
    return 0
  fi
  log "RESULT disengage incomplete (old helper does not kill niri on --restore-aqua)"
  return 1
}

cmd_engage() {
  log "mode-b-engage"
  cmd_ready
  ready=$?
  if [ "$ready" = 2 ]; then
    log "opening native macOS Restart sheet (loginwindow kAERestart)"
    osascript -e 'tell application "loginwindow" to «event aevtrrst»' >>"$CLI_LOG" 2>&1
    return 2
  fi
  if [ "$ready" != 0 ]; then
    log "engage aborted (not takeover-now)"
    return "$ready"
  fi
  defaults write com.aspauldingcode.Wawona DesktopReplacementEnabled -bool true
  local raw
  raw="$(read_pid)"
  if pid_live "$raw" && ! ws_up; then
    log "already engaged pid=$raw (WindowServer down)"
    log "RESULT success pid=$raw"
    return 0
  fi
  if [ ! -x "$HELPER" ]; then
    log "helper missing at $HELPER"
    return 2
  fi
  if ! sudo -n -l 2>/dev/null | grep -q run-modeb.sh; then
    log "sudo -n helper is not allowed"
    return 2
  fi
  log "restore leftover session"
  sudo -n "$HELPER" --restore-aqua >>"$CLI_LOG" 2>&1 || true
  sleep 0.5
  log "bootout $TARGET"
  launchctl bootout "$TARGET" >/dev/null 2>&1 || true
  i=0
  while pgrep -f "/Library/Application Support/Wawona/run-modeb.sh" >/dev/null 2>&1 && [ "$i" -lt 40 ]; do
    log "waiting for leftover helper to exit ($i)"
    sudo -n "$HELPER" --restore-aqua >/dev/null 2>&1 || true
    sleep 0.25
    i=$((i + 1))
  done
  i=0
  while [ -d "$LOCK" ] && [ "$i" -lt 25 ]; do
    log "waiting for leftover helper lock"
    sudo -n "$HELPER" --restore-aqua >/dev/null 2>&1 || true
    sleep 0.2
    i=$((i + 1))
  done
  : > "$HELPER_LOG"
  chmod 666 "$HELPER_LOG" 2>/dev/null || true
  rm -f "$REASON"
  log "starting sudo -n helper (WindowServer stays up until framebufferd)"
  sudo -n "$HELPER" >>"$HELPER_LOG" 2>&1 &
  sudo_pid=$!
  log "sudo helper wrapper pid=$sudo_pid"
  n=0
  while [ "$n" -lt 150 ]; do
    if [ -f "$REASON" ] && [ -s "$REASON" ]; then
      log "helper reported failure: $(cat "$REASON")"
      log "helper-log:"; tail -n 80 "$HELPER_LOG" | tee -a "$CLI_LOG"
      return 1
    fi
    raw="$(read_pid)"
    if pid_live "$raw"; then
      log "compositor pid=$raw WindowServer=$(ws_up && echo 1 || echo 0)"
      if ! ws_up; then
        log "helper-log:"; tail -n 80 "$HELPER_LOG" | tee -a "$CLI_LOG"
        log "RESULT success pid=$raw ws=0"
        return 0
      fi
    fi
    if [ $((n % 10)) -eq 0 ]; then
      log "wait $n/150 pidfile=$raw helper-bytes=$(wc -c < "$HELPER_LOG" 2>/dev/null || echo 0) ws=$(ws_up && echo 1 || echo 0)"
    fi
    sleep 0.1
    n=$((n + 1))
  done
  log "timed out waiting for compositor pid"
  log "helper-log:"; tail -n 80 "$HELPER_LOG" | tee -a "$CLI_LOG"
  return 1
}

cmd_ready() {
  log "mode-b-ready"
  log "  sip:"
  csrutil status 2>/dev/null | tee -a "$CLI_LOG" | sed 's/^/    /'
  if [ ! -x "$HELPER" ]; then
    log "VERDICT blocked"
    log "REASON Mode B helper is missing at $HELPER"
    log "next: Wawona --mode-b-stage"
    return 3
  fi
  set +e
  out=$(sudo -n "$HELPER" --ack-status 2>/dev/null)
  st=$?
  set +e
  printf '%s\n' "$out" | tee -a "$CLI_LOG"
  verdict=$(printf '%s\n' "$out" | awk -F= '/^verdict=/{print $2; exit}')
  reason=$(printf '%s\n' "$out" | awk -F= '/^reason=/{sub(/^[^=]+=/,""); print; exit}')
  if [ "$st" = 0 ] || [ "$verdict" = "takeover-now" ]; then
    log "VERDICT takeover-now"
    log "REASON ${reason:-Path B live. Classic Take Over may run now.}"
    log "next: Wawona --mode-b-engage"
    return 0
  fi
  if [ "$st" = 2 ] || [ "$verdict" = "reboot" ]; then
    log "VERDICT reboot"
    log "REASON ${reason:-Path B armed but sock not done=1. Reboot first.}"
    log "next: Wawona --mode-b-engage opens the native Restart sheet"
    return 2
  fi
  log "VERDICT blocked"
  log "REASON ${reason:-Classic Take Over is blocked. See --ack-status above.}"
  log "next: arm Path B (claim-install --path-b), reboot, then Wawona --mode-b-ready"
  return 3
}

usage() {
  cat <<'EOF'
Usage: wawona-modeb-cli.sh status|ready|probe|engage|disengage
  ready    Can Classic Take Over run now, or is a reboot required?
Logs: /tmp/wawona-modeb-cli.log /tmp/wawona-modeb.log
EOF
}

cmd="${1:-}"
case "$cmd" in
  status) cmd_status ;;
  ready) cmd_ready ;;
  probe) cmd_probe ;;
  engage) cmd_engage ;;
  disengage) cmd_disengage ;;
  -h|--help|help|"") usage; exit 2 ;;
  *) log "unknown command $cmd"; usage; exit 2 ;;
esac
