#!/usr/bin/env bash
# Shared vphone wawona-jb guest bring-up for Mode B tipa / jailbreak runners.
# Sourced only. Never foreground `vphone-cli vm launch` in an agent Shell.
# Never `pkill -f vphone`.

: "${VM_NAME:=${WAWONA_VPHONE_VM:-wawona-jb}}"
: "${SSH_USER:=${WAWONA_VPHONE_SSH_USER:-mobile}}"
: "${SSH_PORT:=${WAWONA_VPHONE_SSH_PORT:-22222}}"
: "${SSH_PASS:=${WAWONA_VPHONE_SSH_PASS:-alpine}}"

vphone_find_profile() {
  if [[ -n "${WAWONA_VPHONE_PROFILE:-}" && -f "${WAWONA_VPHONE_PROFILE}" ]]; then
    echo "${WAWONA_VPHONE_PROFILE}"
    return
  fi
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/.agent-device/vphone-wawona-jb.json" ]]; then
      echo "$dir/.agent-device/vphone-wawona-jb.json"
      return
    fi
    if [[ -f "$dir/Wawona/.agent-device/vphone-wawona-jb.json" ]]; then
      echo "$dir/Wawona/.agent-device/vphone-wawona-jb.json"
      return
    fi
    dir="$(dirname "$dir")"
  done
  if [[ -f "$HOME/.vphone/VMs/${VM_NAME}/vphone-wawona-jb.json" ]]; then
    echo "$HOME/.vphone/VMs/${VM_NAME}/vphone-wawona-jb.json"
  fi
}

# vmnet DHCP often issues a new 192.168.64.N after reboot.
vphone_guest_ip_candidates() {
  local profile="${1:-}"
  python3 - "$profile" "$HOME/.vphone/VMs/${VM_NAME}/guest-ip.txt" \
    "${WAWONA_VPHONE_SSH_HOST:-}" <<'PY'
import json, re, sys
seen = []
def add(ip):
    ip = (ip or "").strip()
    if ip and ip not in seen:
        seen.append(ip)

add(sys.argv[3])
try:
    add(open(sys.argv[2]).read())
except OSError:
    pass
try:
    data = json.load(open(sys.argv[1]))
    add(data.get("sshHost") or data.get("host") or data.get("ip"))
except (OSError, json.JSONDecodeError, TypeError):
    pass
try:
    text = open("/var/db/dhcpd_leases").read()
    blocks = re.findall(r"\{[^}]+\}", text)
    scored = []
    for b in blocks:
        ip = re.search(r"ip_address=([0-9.]+)", b)
        lease = re.search(r"lease=(0x[0-9a-fA-F]+)", b)
        name = re.search(r"name=(\S+)", b)
        if not ip:
            continue
        scored.append((int(lease.group(1), 16) if lease else 0,
                       1 if name and "iPhone" in name.group(1) else 0,
                       ip.group(1)))
    for _lease, _iphone, ip in sorted(scored, reverse=True)[:12]:
        add(ip)
except OSError:
    pass
print("\n".join(seen))
PY
}

vphone_remember_guest_ip() {
  local host="$1"
  local profile="${2:-}"
  [[ -n "$host" ]] || return 0
  mkdir -p "$HOME/.vphone/VMs/${VM_NAME}"
  printf '%s\n' "$host" >"$HOME/.vphone/VMs/${VM_NAME}/guest-ip.txt"
  if [[ -n "$profile" && -f "$profile" ]]; then
    python3 - "$profile" "$host" <<'PY'
import json, sys
path, host = sys.argv[1], sys.argv[2]
data = json.load(open(path))
data["sshHost"] = host
data["host"] = host
json.dump(data, open(path, "w"), indent=2)
open(path, "a").write("\n")
PY
  fi
}

vphone_ssh_ready() {
  local host="$1"
  [[ -n "$host" ]] || return 1
  local ncbin
  ncbin="$(command -v nc || true)"
  [[ -x "$ncbin" ]] || ncbin="/usr/bin/nc"
  "$ncbin" -z -G 1 "$host" "$SSH_PORT" >/dev/null 2>&1
}

vphone_find_cli() {
  local cand
  if [[ -n "${WAWONA_VPHONE_CLI:-}" && -x "${WAWONA_VPHONE_CLI}" ]]; then
    echo "${WAWONA_VPHONE_CLI}"
    return
  fi
  if command -v vphone-cli >/dev/null 2>&1; then
    command -v vphone-cli
    return
  fi
  for cand in \
    "$PWD/result-vphone/bin/vphone-cli" \
    "$HOME/.vphone/src/vphone-cli/.build/vphone-cli.app/Contents/MacOS/vphone-cli" \
    "$HOME/.vphone/src/vphone-cli/.build/release/vphone-cli"
  do
    if [[ -x "$cand" ]]; then
      echo "$cand"
      return
    fi
  done
}

vphone_probe_ssh() {
  local profile="${1:-}"
  local host
  while IFS= read -r host; do
    [[ -n "$host" ]] || continue
    if vphone_ssh_ready "$host"; then
      vphone_remember_guest_ip "$host" "$profile"
      echo "$host"
      return 0
    fi
  done < <(vphone_guest_ip_candidates "$profile")
  return 1
}

vphone_wait_ssh() {
  local profile="${1:-}"
  local i host
  for i in $(seq 1 150); do
    if host="$(vphone_probe_ssh "$profile")"; then
      echo "$host"
      return 0
    fi
    sleep 2
  done
  return 1
}

# vm launch is the VM process. Must stay running (visible window for sock).
vphone_launch() {
  local cli="$1"
  local log="$HOME/.vphone/VMs/${VM_NAME}/launch.log"
  mkdir -p "$(dirname "$log")"
  echo "== vphone SSH closed. Launching ${VM_NAME} via ${cli} ==" >&2
  echo "log: $log" >&2
  nohup "$cli" vm launch "$VM_NAME" >>"$log" 2>&1 &
  local pid=$!
  disown "$pid" 2>/dev/null || true
  echo "vphone-cli pid $pid" >&2
}

vphone_running() {
  pgrep -f "vphone-cli.*${VM_NAME}|vphone-cli --config.*${VM_NAME}" >/dev/null 2>&1
}

# Echo guest IP on stdout. Exit 1 if the lab VM is missing or SSH never opens.
vphone_ensure_guest() {
  local profile="${1:-}"
  local host cli flake
  if host="$(vphone_probe_ssh "$profile")"; then
    echo "$host"
    return
  fi

  if [[ ! -d "$HOME/.vphone/VMs/${VM_NAME}" ]]; then
    echo "No vphone VM at $HOME/.vphone/VMs/${VM_NAME}." >&2
    echo "Create the jailbroken lab once (not the Xcode Simulator):" >&2
    echo "  nix run .#vphone-jb-lab" >&2
    echo "  # or: nix run github:Wawona/wwn-vphone#vphone-jb-lab" >&2
    exit 1
  fi

  if vphone_running; then
    echo "== vphone ${VM_NAME} is up. Waiting for SSH (IP may have changed) ==" >&2
    if host="$(vphone_wait_ssh "$profile")"; then
      echo "$host"
      return
    fi
    echo "vphone is running but SSH :${SSH_PORT} never opened." >&2
    exit 1
  fi

  cli="$(vphone_find_cli || true)"
  if [[ -n "${cli:-}" ]]; then
    vphone_launch "$cli"
    if host="$(vphone_wait_ssh "$profile")"; then
      echo "$host"
      return
    fi
    echo "vphone launched but SSH :${SSH_PORT} never opened. Last log:" >&2
    tail -n 40 "$HOME/.vphone/VMs/${VM_NAME}/launch.log" >&2 || true
    exit 1
  fi

  flake="${WAWONA_MODEB_FLAKE:-.}"
  if command -v nix >/dev/null 2>&1; then
    echo "== vphone-cli not on PATH. nix run ${flake}#vphone-cli vm launch ==" >&2
    mkdir -p "$HOME/.vphone/VMs/${VM_NAME}"
    nohup nix run --impure "${flake}#vphone-cli" -- vm launch "$VM_NAME" \
      >>"$HOME/.vphone/VMs/${VM_NAME}/launch.log" 2>&1 &
    disown $! 2>/dev/null || true
    if host="$(vphone_wait_ssh "$profile")"; then
      echo "$host"
      return
    fi
  fi

  echo "vphone VM exists but vphone-cli was not found and SSH is down." >&2
  echo "Expected: $HOME/.vphone/src/vphone-cli/.build/vphone-cli.app/Contents/MacOS/vphone-cli" >&2
  echo "or: nix run .#vphone-cli -- vm launch ${VM_NAME}" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Guest SSH (same contract as wwn-vphone vphone-jb-lab.sh guest_ssh).
#
# The research guest runs iosbinpack dropbear. Pubkey auth is rejected there
# today; lab credentials are password alpine via sshpass. That is the paired
# lab setup. Never fall through to interactive ssh-askpass (nix OpenSSH sets
# SSH_ASKPASS to a missing binary and prompts thrice).
# ---------------------------------------------------------------------------

vphone_ssh_env() {
  # Strip nix/OpenSSH askpass entirely. REQUIRE=never alone is not enough
  # when SSH_ASKPASS points at a missing helper.
  env -u SSH_ASKPASS -u SSH_ASKPASS_REQUIRE -u DISPLAY \
    SSH_ASKPASS_REQUIRE=never "$@"
}

vphone_ssh() {
  local host="$1"
  shift
  local user="${WAWONA_VPHONE_INSTALL_SSH_USER:-root}"
  local pass="${WAWONA_VPHONE_SSH_PASS:-${SSH_PASS:-alpine}}"
  local port="${WAWONA_VPHONE_SSH_PORT:-${SSH_PORT:-22222}}"
  if ! command -v sshpass >/dev/null 2>&1; then
    echo "sshpass is required (same as nix run .#vphone-jb-lab). Install it or use the flake app PATH." >&2
    exit 1
  fi
  vphone_ssh_env sshpass -p "$pass" ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no \
    -o NumberOfPasswordPrompts=1 \
    -o ConnectTimeout=15 \
    -p "$port" "${user}@${host}" \
    "export PATH=/var/jb/usr/bin:/var/jb/bin:/usr/bin:/bin:/sbin:/usr/sbin:/iosbinpack64/usr/local/bin; $*"
}

# vphone_ssh_script <host>  (script on stdin via sh -s)
vphone_ssh_script() {
  local host="$1"
  local user="${WAWONA_VPHONE_INSTALL_SSH_USER:-root}"
  local pass="${WAWONA_VPHONE_SSH_PASS:-${SSH_PASS:-alpine}}"
  local port="${WAWONA_VPHONE_SSH_PORT:-${SSH_PORT:-22222}}"
  if ! command -v sshpass >/dev/null 2>&1; then
    echo "sshpass is required (same as nix run .#vphone-jb-lab)." >&2
    exit 1
  fi
  {
    echo 'export PATH=/var/jb/usr/bin:/var/jb/bin:/usr/bin:/bin:/sbin:/usr/sbin:/iosbinpack64/usr/local/bin'
    cat
  } | vphone_ssh_env sshpass -p "$pass" ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no \
    -o NumberOfPasswordPrompts=1 \
    -o ConnectTimeout=15 \
    -p "$port" "${user}@${host}" \
    'export PATH=/var/jb/usr/bin:/var/jb/bin:/usr/bin:/bin:/sbin:/usr/sbin:/iosbinpack64/usr/local/bin; exec sh -s'
}

# vphone_ssh_put <host> <remote-path> <local-file>
vphone_ssh_put() {
  local host="$1" remote="$2" local_file="$3"
  local user="${WAWONA_VPHONE_INSTALL_SSH_USER:-root}"
  local pass="${WAWONA_VPHONE_SSH_PASS:-${SSH_PASS:-alpine}}"
  local port="${WAWONA_VPHONE_SSH_PORT:-${SSH_PORT:-22222}}"
  if ! command -v sshpass >/dev/null 2>&1; then
    echo "sshpass is required (same as nix run .#vphone-jb-lab)." >&2
    exit 1
  fi
  vphone_ssh_env sshpass -p "$pass" ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no \
    -o NumberOfPasswordPrompts=1 \
    -o ConnectTimeout=15 \
    -p "$port" "${user}@${host}" \
    "export PATH=/var/jb/usr/bin:/var/jb/bin:/usr/bin:/bin:/sbin:/usr/sbin; mkdir -p \"$(dirname "$remote")\" && cat > \"$remote\"" \
    <"$local_file"
}
