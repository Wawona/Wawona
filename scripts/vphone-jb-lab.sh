#!/usr/bin/env bash
# vphone-jb-lab.sh: one-shot jailbroken iOS VM for Wawona Mode B proof.
#
# Automates: host gate → vphone-cli ensure → create/restore/CFW(jb) → launch
# → wait SSH → verify Sileo + TrollStore Lite.
#
# Operator owns Recovery/nvram. This script never flips csrutil/nvram.
#
# Usage (via nix):
#   nix run .#vphone-jb-lab
#   nix run .#vphone-jb-lab -- --smoke-only
#   nix run .#vphone-jb-lab -- --gate-only
#
# Env:
#   VPHONE_ROOT          default ~/.vphone
#   VPHONE_VM_NAME       default wawona-jb
#   VPHONE_DISK_GB       default 32
#   VPHONE_IOS_URL       optional iPhone IPSW URL (default: catalog iOS 26.1)
#   VPHONE_CLOUDOS_URL   optional cloudOS URL (default: catalog cloudOS 26.1)
#   VPHONE_ARTIFACTS     default <repo>/.agent-device/test-artifacts/dmabuf/vphone-jb
set -euo pipefail

ROOT="${VPHONE_ROOT:-$HOME/.vphone}"
VM_NAME="${VPHONE_VM_NAME:-wawona-jb}"
DISK_GB="${VPHONE_DISK_GB:-32}"
SRC="$ROOT/src/vphone-cli"
VM_DIR="$ROOT/VMs/$VM_NAME"
# Artifacts: prefer an explicit path, then a Wawona checkout, then ~/.vphone.
if [[ -n "${VPHONE_ARTIFACTS:-}" ]]; then
  ART="$VPHONE_ARTIFACTS"
elif [[ -n "${WAWONA_ROOT:-}" ]]; then
  ART="$WAWONA_ROOT/.agent-device/test-artifacts/dmabuf/vphone-jb"
elif [[ -d "$PWD/.agent-device" || -f "$PWD/flake.nix" ]]; then
  ART="$PWD/.agent-device/test-artifacts/dmabuf/vphone-jb"
else
  ART="$ROOT/artifacts/vphone-jb"
fi
mkdir -p "$ART" "$ROOT"

# Catalog pairing: iOS 26.1 ↔ cloudOS 26.1 (iPhone17,3). Override via env.
IPHONE_URL="${VPHONE_IOS_URL:-https://updates.cdn-apple.com/2025FallFCS/fullrestores/089-13864/668EFC0E-5911-454C-96C6-E1063CB80042/iPhone17,3_26.1_23B85_Restore.ipsw}"
CLOUDOS_URL="${VPHONE_CLOUDOS_URL:-https://updates.cdn-apple.com/private-cloud-compute/399b664dd623358c3de118ffc114e42dcd51c9309e751d43bc949b98f4e31349}"

SMOKE_ONLY=0
GATE_ONLY=0
CREATE_FORCE=0
for arg in "$@"; do
  case "$arg" in
    --smoke-only) SMOKE_ONLY=1 ;;
    --gate-only) GATE_ONLY=1 ;;
    --force-create) CREATE_FORCE=1 ;;
    -h|--help)
      sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "unknown arg: $arg" >&2
      exit 2
      ;;
  esac
done

log() { printf '[vphone-jb-lab] %s\n' "$*"; }
die() { printf '[vphone-jb-lab] ERROR: %s\n' "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

# ── Host gate (never mutate Recovery / nvram) ───────────────────
check_gate() {
  local sip research args arch nested
  arch="$(uname -m)"
  [[ "$arch" == "arm64" ]] || die "Apple Silicon required (got $arch)"

  nested="$(sysctl -n kern.hv_vmm_present 2>/dev/null || echo 0)"
  [[ "$nested" == "0" ]] || die "host is nested (kern.hv_vmm_present=$nested); PV=3 cannot nest"

  sip="$(csrutil status 2>/dev/null || true)"
  echo "$sip" | grep -qi 'status: disabled' \
    || die "SIP must be fully disabled (csrutil disable in Recovery). Got: $sip"

  research="$(csrutil allow-research-guests status </dev/null 2>/dev/null || true)"
  echo "$research" | grep -qi 'status: enabled' \
    || die "allow-research-guests must be enabled (Recovery: csrutil allow-research-guests enable). Got: $research"

  args="$(nvram boot-args 2>/dev/null || true)"
  echo "$args" | grep -q 'amfi_get_out_of_my_way=1' \
    || die "nvram boot-args must include amfi_get_out_of_my_way=1 (operator sets after SIP off)"

  # Optional: warn if sysctl lagging after research-guests enable (reboot usually fixes).
  local sr
  sr="$(sysctl -n hw.features.allows_security_research 2>/dev/null || echo '?')"
  if [[ "$sr" != "1" ]]; then
    log "warn: hw.features.allows_security_research=$sr (research-guests text says enabled; reboot if DFU start fails)"
  fi

  local free_g
  # Prefer BSD df (-g); nix runtimeInputs may put GNU df first.
  if free_g="$(/bin/df -g / 2>/dev/null | awk 'NR==2{print $4}')"; then
    :
  else
    free_g="$(df -BG / 2>/dev/null | awk 'NR==2{gsub(/G/,"",$4); print $4}')"
  fi
  if [[ -n "$free_g" && "$free_g" =~ ^[0-9]+$ && "$free_g" -lt 40 ]]; then
    log "warn: only ${free_g}G free on /; prefer ≥64G (128G+ for cold IPSW create)"
  fi

  {
    echo "=== host-gate $(date) ==="
    echo "$sip"
    echo "$research"
    echo "boot-args: $args"
    echo "allows_security_research: $sr"
    echo "free_g: ${free_g:-unknown}"
  } | tee "$ART/host-gate.txt" >/dev/null

  log "host gate OK"
}

# ── Resolve vphone-cli ──────────────────────────────────────────
resolve_vphone() {
  if command -v vphone-cli >/dev/null 2>&1; then
    VPHONE="$(command -v vphone-cli)"
  elif [[ -x "$SRC/.build/release/vphone-cli" ]]; then
    VPHONE="$SRC/.build/release/vphone-cli"
  elif [[ -x "$SRC/.build/vphone-cli.app/Contents/MacOS/vphone-cli" ]]; then
    VPHONE="$SRC/.build/vphone-cli.app/Contents/MacOS/vphone-cli"
  else
    die "vphone-cli not on PATH; run via: nix run .#vphone-jb-lab"
  fi
  log "vphone-cli: $VPHONE"
  PATH="$(dirname "$VPHONE"):${PATH}"
  export PATH
  if [[ -x "$SRC/.venv/bin/python3" ]]; then
    export VPHONE_PYTHON="$SRC/.venv/bin/python3"
  fi
}

# Run under a pseudo-TTY so CFW sudo can use NOPASSWD without --sudo-password
# (sudo -A / askpass fails when NOPASSWD is set but askpass returns a dummy).
with_tty() {
  if [[ -t 0 ]]; then
    "$@"
  else
    script -q /dev/null "$@"
  fi
}

vm_exists() { [[ -d "$VM_DIR" && -f "$VM_DIR/Disk.img" ]]; }

cfw_done() {
  [[ -f "$VM_DIR/restore-info.json" ]] || return 1
  [[ -f "$VM_DIR/.vphoned.signed" ]] || return 1
  grep -q '"variant"[[:space:]]*:[[:space:]]*"jb"' "$VM_DIR/restore-info.json" 2>/dev/null
}

restored() {
  [[ -f "$VM_DIR/restore-info.json" ]]
}

guest_ips() {
  # Prefer live iPhone DHCP leases; fall back to scanning the VZ NAT range.
  local ips
  ips="$(awk '
    /name=iPhone/ { want=1; next }
    want && /ip_address=/ {
      gsub(/ip_address=|;/, "", $1); print $1; want=0
    }
  ' /var/db/dhcpd_leases 2>/dev/null || true)"
  if [[ -n "$ips" ]]; then
    printf '%s\n' "$ips"
  else
    # VZ NAT often assigns mid/high .64.x; cover the common lease range.
    printf '%s\n' 192.168.64.{2..120}
  fi
}

ssh_ready() {
  local ip port=22222
  for ip in $(guest_ips); do
    if nc -z -G 1 "$ip" "$port" 2>/dev/null; then
      echo "$ip"
      return 0
    fi
  done
  return 1
}

# SSH to guest: always password auth, never askpass (nix openssh sets SSH_ASKPASS).
guest_ssh() {
  local ip="$1"
  shift
  env -u SSH_ASKPASS -u SSH_ASKPASS_REQUIRE SSH_ASKPASS_REQUIRE=never \
    sshpass -p alpine ssh \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o PreferredAuthentications=password \
      -o PubkeyAuthentication=no \
      -o NumberOfPasswordPrompts=1 \
      -o ConnectTimeout=15 \
      -p 22222 "mobile@$ip" "$@"
}

# Auto-lock Must Be Off for agent-device / tipa demos. Otherwise SpringBoard
# locks mid-run and sock taps hit the lock screen. Idempotent bootstrap step.
disable_autolock() {
  local ip="$1"
  local plist_host="$ART/springboard-nolock.plist"
  local b64
  log "disabling guest auto-lock (SBAutoLockTime=0)…"
  cat >"$ART/springboard-minimal.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>SBAutoLockTime</key>
  <integer>0</integer>
  <key>SBAutoLockDisabled</key>
  <true/>
</dict>
</plist>
XML
  if command -v plutil >/dev/null 2>&1; then
    /usr/bin/plutil -convert binary1 "$ART/springboard-minimal.xml" -o "$plist_host"
  else
    cp "$ART/springboard-minimal.xml" "$plist_host"
  fi
  b64="$(/usr/bin/base64 -i "$plist_host" 2>/dev/null | tr -d '\n' || base64 <"$plist_host" | tr -d '\n')"
  # Merge via defaults when available; always stamp the two keys; never leave a 0-byte plist.
  guest_ssh "$ip" "export PATH=\"/var/jb/usr/bin:/var/jb/bin:/usr/bin:/bin:\$PATH\"
    set -e
    # Ensure Procursus defaults exists (best path for future boots).
    if ! command -v defaults >/dev/null 2>&1; then
      echo alpine | sudo -S apt-get install -y defaults >/dev/null 2>&1 || true
    fi
    if command -v defaults >/dev/null 2>&1; then
      defaults write com.apple.springboard SBAutoLockTime -int 0
      defaults write com.apple.springboard SBAutoLockDisabled -bool true
    else
      printf '%s' '$b64' | base64 -d > /var/mobile/Library/Preferences/com.apple.springboard.plist.tmp
      sz=\$(wc -c < /var/mobile/Library/Preferences/com.apple.springboard.plist.tmp | tr -d ' ')
      if [[ \"\$sz\" -lt 20 ]]; then
        echo 'autolock plist too small; abort' >&2
        exit 12
      fi
      mv /var/mobile/Library/Preferences/com.apple.springboard.plist.tmp \\
         /var/mobile/Library/Preferences/com.apple.springboard.plist
      chmod 600 /var/mobile/Library/Preferences/com.apple.springboard.plist
    fi
    killall -9 SpringBoard 2>/dev/null || true
    sleep 2
    if command -v defaults >/dev/null 2>&1; then
      echo \"SBAutoLockTime=\$(defaults read com.apple.springboard SBAutoLockTime 2>/dev/null || echo ?)\"
      echo \"SBAutoLockDisabled=\$(defaults read com.apple.springboard SBAutoLockDisabled 2>/dev/null || echo ?)\"
    fi
    echo autolock=never
  " 2>&1 | tee "$ART/autolock.txt"
  grep -q 'autolock=never' "$ART/autolock.txt" || die "failed to disable guest auto-lock"
  log "guest auto-lock disabled"
}

wait_ssh() {
  local timeout="${1:-600}" waited=0 ip
  log "waiting for guest SSH (dhcp/NAT :22222, timeout=${timeout}s)..."
  while (( waited < timeout )); do
    if ip="$(ssh_ready)"; then
      echo "$ip" | tee "$ART/guest-ip.txt" >/dev/null
      log "SSH ready at $ip:22222"
      return 0
    fi
    if ! pgrep -f "vphone-cli.*${VM_NAME}|vphone-cli --config.*${VM_NAME}" >/dev/null 2>&1 \
      && ! pgrep -f "config.plist --variant jb" >/dev/null 2>&1 \
      && ! pgrep -f "${VM_DIR}/config.plist" >/dev/null 2>&1; then
      # Still allow a few seconds after launch spawn.
      if (( waited > 30 )); then
        log "warn: no vphone process seen at waited=${waited}s"
      fi
    fi
    if (( waited % 30 == 0 )); then
      log "… ${waited}s"
    fi
    sleep 5
    waited=$((waited + 5))
  done
  die "guest SSH not ready after ${timeout}s"
}

launch_vm() {
  if pgrep -f "${VM_DIR}/config.plist" >/dev/null 2>&1; then
    log "VM already running"
    return 0
  fi
  log "launching $VM_NAME (jb)..."
  # Keep display awake so the GUI VM is less likely to power-gate.
  caffeinate -dims -t 7200 >/dev/null 2>&1 &
  nohup "$VPHONE" vm launch "$VM_NAME" -V jb -p "$SRC" -v \
    >"$ART/launch.serial" 2>&1 &
  echo $! >"$ART/launch.pid"
  sleep 3
}

smoke() {
  local ip
  need_cmd sshpass
  need_cmd nc
  ip="$(cat "$ART/guest-ip.txt" 2>/dev/null || true)"
  [[ -n "$ip" ]] || ip="$(ssh_ready)" || die "no guest IP for smoke"
  log "smoke SSH mobile@$ip"
  # Remote body must stay single-quoted so it runs on the guest, not the host.
  # shellcheck disable=SC2016
  guest_ssh "$ip" '
      export PATH="/var/jb/usr/bin:/var/jb/bin:/var/jb/usr/sbin:/usr/bin:/bin:/usr/sbin:/sbin:/var/binpack/usr/bin:$PATH"
      set -e
      echo "uname: $(uname -a)"
      echo "sw_vers: $(sw_vers 2>/dev/null | tr "\n" " ")"
      test -d /var/jb/Applications/Sileo.app && echo Sileo=ok || { echo Sileo=missing; exit 10; }
      if grep -q "TrollStore Lite installed\|vphone_jb_setup.sh complete\|Already completed" /var/log/vphone_jb_setup.log 2>/dev/null; then
        echo TrollStore=ok
      else
        echo "TrollStore=pending (log missing markers)"
        tail -20 /var/log/vphone_jb_setup.log 2>/dev/null || true
        exit 11
      fi
      echo "SBAutoLockTime=$(defaults read com.apple.springboard SBAutoLockTime 2>/dev/null || echo unset)"
      echo jb_root=/var/jb
    ' 2>&1 | tee "$ART/ssh-smoke.txt"

  {
    echo "=== ready $(date) ==="
    echo "guest: $ip"
    echo "SSH:   ssh -p 22222 mobile@$ip   # password alpine"
    echo "VNC:   vnc://$ip:5901"
    echo "vm:    $VM_NAME"
    echo "Sileo + TrollStore Lite: verified"
  } | tee "$ART/ready.txt"

  # agent-device connection profile (Wawona fork discovers vphone:* devices).
  local profile_dir profile_path sock
  if [[ -n "${WAWONA_ROOT:-}" ]]; then
    profile_dir="$WAWONA_ROOT/.agent-device"
  elif [[ -d "$PWD/.agent-device" || -f "$PWD/flake.nix" ]]; then
    profile_dir="$PWD/.agent-device"
  else
    profile_dir="$ROOT/artifacts"
  fi
  mkdir -p "$profile_dir"
  sock="$VM_DIR/vphone.sock"
  profile_path="$profile_dir/vphone-${VM_NAME}.json"
  cat >"$profile_path" <<EOF
{
  "vmName": "$VM_NAME",
  "sockPath": "$sock",
  "sshHost": "$ip",
  "sshPort": 22222,
  "sshUser": "mobile",
  "sshPassword": "alpine",
  "variant": "jb",
  "vnc": "vnc://$ip:5901",
  "vmDir": "$VM_DIR"
}
EOF
  log "wrote agent-device profile: $profile_path"
  log "READY"
}

ensure_create() {
  if vm_exists && [[ "$CREATE_FORCE" != 1 ]]; then
    log "VM bundle exists: $VM_DIR"
    return 0
  fi
  if vm_exists && [[ "$CREATE_FORCE" == 1 ]]; then
    die "--force-create with existing VM: delete $VM_DIR manually first"
  fi
  need_cmd aria2c
  need_cmd ldid
  log "creating $VM_NAME (jb, disk=${DISK_GB}G, iOS 26.1)…"
  log "this downloads ~12G+ IPSWs; may take a long time"
  with_tty "$VPHONE" vm create "$VM_NAME" -V jb --disk-size "$DISK_GB" \
    -i "$IPHONE_URL" -c "$CLOUDOS_URL" -p "$SRC" -v \
    | tee "$ART/create.log"
  cfw_done || die "vm create finished but CFW jb markers missing"
}

ensure_restored_cfw() {
  if cfw_done; then
    log "CFW jb already installed"
    return 0
  fi
  vm_exists || die "no VM at $VM_DIR"
  need_cmd ldid
  # ldid must be procursus (PKCS12 empty password).
  if ! ldid 2>&1 | head -1 | grep -qi procursus; then
    log "warn: ldid may not be ldid-procursus; CFW signing can fail"
  fi

  if ! restored; then
    log "DFU restore…"
    "$VPHONE" vm stop "$VM_NAME" -t 10 2>/dev/null || true
    with_tty bash -c "
      set -euo pipefail
      '$VPHONE' vm launch '$VM_NAME' --dfu -p '$SRC' -v >'$ART/dfu.serial' 2>&1 &
      dfu=\$!
      ok=0
      for i in \$(seq 1 90); do
        if ! kill -0 \$dfu 2>/dev/null; then
          echo 'DFU process exited' >&2
          tail -40 '$ART/dfu.serial' >&2 || true
          exit 1
        fi
        ecid=\$(awk -F= '/^ECID=/{print \$2}' '$VM_DIR/udid-prediction.txt' 2>/dev/null || true)
        if [[ -z \"\$ecid\" ]]; then sleep 2; continue; fi
        if \"\${VPHONE_PYTHON:-python3}\" '$SRC/scripts/pymobiledevice3_bridge.py' \
            recovery-probe --ecid \"0x\$ecid\" --timeout 2 >/dev/null 2>&1; then
          ok=1; break
        fi
        sleep 2
      done
      [[ \$ok == 1 ]] || { echo 'DFU probe timeout' >&2; exit 1; }
      '$VPHONE' restore '$VM_NAME' -p '$SRC' -v | tee '$ART/restore.log'
      '$VPHONE' vm stop '$VM_NAME' -t 30 2>/dev/null || true
      kill \$dfu 2>/dev/null || true
    "
  fi

  log "CFW install (jb)…"
  "$VPHONE" vm stop "$VM_NAME" -t 10 2>/dev/null || true
  with_tty "$VPHONE" cfw install "$VM_NAME" -V jb -p "$SRC" -v \
    | tee "$ART/cfw.log"
  cfw_done || die "CFW jb install did not leave expected markers"
}

# ── Main ────────────────────────────────────────────────────────
check_gate
[[ "$GATE_ONLY" == 1 ]] && { log "gate-only done"; exit 0; }

resolve_vphone
need_cmd nc

if [[ "$SMOKE_ONLY" == 1 ]]; then
  ip="$(ssh_ready)" || die "guest SSH not up; run without --smoke-only"
  echo "$ip" >"$ART/guest-ip.txt"
  disable_autolock "$ip"
  smoke
  exit 0
fi

if ! cfw_done; then
  if ! vm_exists; then
    # Prefer full upstream create (prepare→patch→restore→CFW→first boot).
    ensure_create
  else
    ensure_restored_cfw
  fi
fi

launch_vm
wait_ssh 900
disable_autolock "$(cat "$ART/guest-ip.txt")"
smoke
exit 0
