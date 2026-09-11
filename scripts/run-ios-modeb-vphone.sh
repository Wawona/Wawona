#!/usr/bin/env bash
# Run Mode B Wawona on the TrollStore / Sileo vphone lab.
#
#   nix run .#wawona-ios-trollstore   # or .#wawona-ios-ts / .#wawona-ios-modeb
#   nix run .#wawona-ios-jailbreak    # or .#wawona-ios-jb
#
# This is not the Xcode Simulator. That is `nix run .#wawona-ios`.
# Not App Store / TestFlight / Ship: beta.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "${WAWONA_MODEB_SCRIPTS:-}" && -f "${WAWONA_MODEB_SCRIPTS}/lib/vphone-ensure-guest.sh" ]]; then
  # shellcheck source=lib/vphone-ensure-guest.sh
  source "${WAWONA_MODEB_SCRIPTS}/lib/vphone-ensure-guest.sh"
else
  # shellcheck source=lib/vphone-ensure-guest.sh
  source "$HERE/lib/vphone-ensure-guest.sh"
fi

BUNDLE="com.aspauldingcode.Wawona.ModeB"
DEVICE="${WAWONA_VPHONE_DEVICE:-vphone wawona-jb}"
# Install/launch SSH is root/alpine (same as lab helper; mobile auth fails).
export WAWONA_VPHONE_INSTALL_SSH_USER="${WAWONA_VPHONE_INSTALL_SSH_USER:-root}"
SSH_USER="$WAWONA_VPHONE_INSTALL_SSH_USER"

abspath() {
  local p="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath "$p"
    return
  fi
  python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$p"
}

usage() {
  cat <<'EOF'
usage: run-ios-modeb-vphone.sh [--trollstore|--jailbreak] [--slim|--official]
                               [--rootless|--rootful] [--no-install] [artifact]

Install Mode B on vphone and launch it.

  nix run .#wawona-ios-trollstore        # tipa + TrollStore (short: .#wawona-ios-ts)
  nix run .#wawona-ios-jailbreak         # rootless .deb + apt (short: .#wawona-ios-jb)
  nix run .#wawona-ios-modeb             # alias of trollstore

Options:
  --trollstore  TrollStore .tipa channel (default)
  --jailbreak   Sileo / Procursus .deb channel (rootless on vphone lab)
  --slim        slim iteration artifact (default)
  --official    guest-bearing tipa / matching deb (needs guest disk headroom)
  --rootless    jailbreak scheme (default for --jailbreak)
  --rootful     jailbreak scheme (separate build; not the vphone lab default)
  --no-install  launch the installed app only
  --help        this text

Env:
  WAWONA_MODEB_TIPA / WAWONA_MODEB_DEB
  WAWONA_VPHONE_PROFILE    vphone-wawona-jb.json
  WAWONA_VPHONE_SSH_HOST   guest IP when the profile is missing
  WAWONA_VPHONE_CLI        vphone-cli binary (vm launch)
EOF
  exit 2
}

CHANNEL="${WAWONA_MODEB_CHANNEL:-trollstore}"
KIND="${WAWONA_MODEB_KIND:-slim}"
SCHEME="${WAWONA_MODEB_SCHEME:-rootless}"
NO_INSTALL=0
ARTIFACT="${WAWONA_MODEB_ARTIFACT:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage ;;
    --trollstore|--tipa|--ts) CHANNEL=trollstore; shift ;;
    --jailbreak|--jb|--sileo|--apt) CHANNEL=jailbreak; shift ;;
    --slim) KIND=slim; shift ;;
    --official) KIND=official; shift ;;
    --rootless) SCHEME=rootless; shift ;;
    --rootful) SCHEME=rootful; shift ;;
    --no-install) NO_INSTALL=1; shift ;;
    --) shift; break ;;
    -*)
      echo "unknown option: $1" >&2
      usage
      ;;
    *)
      ARTIFACT="$1"
      shift
      break
      ;;
  esac
done

PROFILE="$(vphone_find_profile || true)"

resolve_tipa() {
  if [[ -n "$ARTIFACT" && -f "$ARTIFACT" ]]; then
    abspath "$ARTIFACT"
    return
  fi
  if [[ -n "${WAWONA_MODEB_TIPA:-}" && -f "${WAWONA_MODEB_TIPA}" ]]; then
    abspath "${WAWONA_MODEB_TIPA}"
    return
  fi
  local cand flake out built
  if [[ "$KIND" == "official" ]]; then
    for cand in \
      result/Wawona-*-iOS-arm64.tipa \
      result-modeb/Wawona-*-iOS-arm64.tipa; do
      if [[ -f $cand ]]; then
        abspath "$cand"
        return
      fi
    done
    echo "official tipa not found. Build it first:" >&2
    echo "  nix build --impure .#wawona-ios-modeb-tipa -o result-modeb" >&2
    exit 1
  fi
  for cand in result-modeb-slim/Wawona-*-iOS-arm64.tipa; do
    if [[ -f $cand ]]; then
      abspath "$cand"
      return
    fi
  done
  echo "slim tipa not found. Building .#wawona-ios-modeb-tipa-slim..." >&2
  flake="${WAWONA_MODEB_FLAKE:-.}"
  out="$(mktemp -d /tmp/wawona-ios-modeb.XXXXXX)"
  nix build --impure "${flake}#wawona-ios-modeb-tipa-slim" -o "$out/result"
  built="$(ls "$out"/result/Wawona-*-iOS-arm64.tipa 2>/dev/null | head -1 || true)"
  if [[ -z "$built" || ! -f "$built" ]]; then
    echo "nix build produced no tipa under $out/result" >&2
    exit 1
  fi
  abspath "$built"
}

resolve_deb() {
  if [[ -n "$ARTIFACT" && -f "$ARTIFACT" ]]; then
    abspath "$ARTIFACT"
    return
  fi
  if [[ -n "${WAWONA_MODEB_DEB:-}" && -f "${WAWONA_MODEB_DEB}" ]]; then
    abspath "${WAWONA_MODEB_DEB}"
    return
  fi
  local attr cand flake out built cand_glob
  if [[ "$SCHEME" == "rootful" ]]; then
    attr="wawona-ios-modeb-deb-rootful"
    cand_glob="result-modeb-deb-rootful/Wawona-*-iOS-arm64-rootful.deb"
  else
    attr="wawona-ios-modeb-deb-rootless"
    if [[ "$KIND" == "official" ]]; then
      cand_glob="result-modeb-deb/Wawona-*-iOS-arm64-rootless.deb"
    else
      cand_glob="result-modeb-deb-slim/Wawona-*-iOS-arm64-rootless.deb"
      attr="wawona-ios-modeb-deb-rootless-slim"
    fi
  fi
  for cand in $cand_glob; do
    if [[ -f $cand ]]; then
      abspath "$cand"
      return
    fi
  done
  echo "${SCHEME} deb not found. Building .#${attr}..." >&2
  flake="${WAWONA_MODEB_FLAKE:-.}"
  out="$(mktemp -d /tmp/wawona-ios-modeb-deb.XXXXXX)"
  nix build --impure "${flake}#${attr}" -o "$out/result"
  built="$(ls "$out"/result/Wawona-*-iOS-arm64-*.deb 2>/dev/null | head -1 || true)"
  if [[ -z "$built" || ! -f "$built" ]]; then
    echo "nix build produced no deb under $out/result" >&2
    exit 1
  fi
  abspath "$built"
}

find_tipa_install() {
  if [[ -n "${WAWONA_MODEB_INSTALL:-}" && -f "${WAWONA_MODEB_INSTALL}" ]]; then
    echo "${WAWONA_MODEB_INSTALL}"
    return
  fi
  if [[ -f "$HERE/install-ios-modeb-tipa.sh" ]]; then
    echo "$HERE/install-ios-modeb-tipa.sh"
    return
  fi
  if [[ -f "$PWD/scripts/install-ios-modeb-tipa.sh" ]]; then
    echo "$PWD/scripts/install-ios-modeb-tipa.sh"
  fi
}

find_deb_install() {
  if [[ -n "${WAWONA_MODEB_DEB_INSTALL:-}" && -f "${WAWONA_MODEB_DEB_INSTALL}" ]]; then
    echo "${WAWONA_MODEB_DEB_INSTALL}"
    return
  fi
  if [[ -f "$HERE/install-ios-modeb-deb.sh" ]]; then
    echo "$HERE/install-ios-modeb-deb.sh"
    return
  fi
  if [[ -f "$PWD/scripts/install-ios-modeb-deb.sh" ]]; then
    echo "$PWD/scripts/install-ios-modeb-deb.sh"
  fi
}

echo "== Wawona Mode B on vphone (${CHANNEL}) =="
echo "Not the Xcode Simulator. Simulator is: nix run .#wawona-ios"
HOST="$(vphone_ensure_guest "${PROFILE:-}")"
echo "guest: ${SSH_USER}@${HOST}:${SSH_PORT}  device=${DEVICE}"

if [[ "$NO_INSTALL" -eq 0 ]]; then
  if [[ "$CHANNEL" == "jailbreak" ]]; then
    DEB="$(resolve_deb)"
    echo "deb: $DEB ($SCHEME/$KIND)"
    INSTALL="$(find_deb_install || true)"
    if [[ -z "${INSTALL:-}" ]]; then
      echo "install-ios-modeb-deb.sh is missing." >&2
      exit 1
    fi
    if [[ -n "${PROFILE:-}" ]]; then
      export WAWONA_VPHONE_PROFILE="$PROFILE"
    fi
    export WAWONA_VPHONE_SSH_HOST="$HOST"
    bash "$INSTALL" "--$SCHEME" "$DEB"
  else
    TIPA="$(resolve_tipa)"
    echo "tipa: $TIPA ($KIND)"
    INSTALL="$(find_tipa_install || true)"
    if [[ -z "${INSTALL:-}" ]]; then
      echo "install-ios-modeb-tipa.sh is missing." >&2
      exit 1
    fi
    if [[ -n "${PROFILE:-}" ]]; then
      export WAWONA_VPHONE_PROFILE="$PROFILE"
    fi
    export WAWONA_VPHONE_SSH_HOST="$HOST"
    bash "$INSTALL" "--$KIND" "$TIPA"
  fi
else
  echo "skipping install (--no-install)"
fi

echo "== launching ${BUNDLE} =="
# Install script already launches + open-jit for tipa. For --no-install,
# or as a second chance, bounce into a live PID then open-jit.
# Guest often has no pgrep; use ps|grep. SSH: lab sshpass, never askpass.
vphone_ssh_script "$HOST" <<EOF
set -e
killall WawonaIomfbSmoke WawonaIomfbMetal WawonaModeBDemo 2>/dev/null || true
alive() { ps aux | grep -F 'Wawona.app/Wawona' | grep -v grep >/dev/null 2>&1; }
if ! alive; then
  uiopen --app Wawona || uiopen --bundleid ${BUNDLE} || true
  sleep 3
fi
if ! alive; then
  echo 'uiopen missed; bouncing SpringBoard' >&2
  killall -9 SpringBoard 2>/dev/null || true
  sleep 8
  uiopen --app Wawona || uiopen --bundleid ${BUNDLE} || true
  sleep 4
fi
ps aux | grep -F 'Wawona.app/Wawona' | grep -v grep || true
EOF

if [[ "$CHANNEL" == "trollstore" ]] && command -v agent-device >/dev/null 2>&1; then
  echo "== tipa open-jit (CS_DEBUGGED attach) =="
  agent-device packages tipa open-jit "$BUNDLE" --device "$DEVICE" || true
fi

echo "Mode B launch requested on ${HOST} (${CHANNEL})"
echo "Picker: Settings → Desktop → Replace now, or echo weston >/tmp/wwn-modeb-select"
