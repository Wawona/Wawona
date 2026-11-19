#!/usr/bin/env bash
# macOS Relay container GUI smoke: Apple Containerization + waypipe → Wawona.
# Requires: live Wawona compositor (wayland-0), Apple container apiserver,
# tip wwn-containerd with --waypipe-guest-root, waypipe-guest-root, host waypipe.
set -euo pipefail

UID_N="$(id -u)"
RUNTIME="${WAWONA_RUNTIME:-/tmp/wawona-${UID_N}}"
SOCKET="${RUNTIME}/wayland-0"
KERNEL="${WAWONA_VM_KERNEL:-${HOME}/Library/Application Support/com.apple.container/kernels/default.kernel-arm64}"
WCD="${WAWONA_CONTAINERD:-}"
GUEST_ROOT="${WAWONA_WAYPIPE_GUEST_ROOT:-/tmp/wawona-waypipe-guest-root}"
HOST_WP="${WWNP_WAYPIPE_BIN:-/tmp/wawona-waypipe-splitfd/bin/waypipe}"

if [[ -z "${WCD}" ]]; then
  for c in \
    "${HOME}/Wawona/wwn-containers/dependencies/containers/macos/.build/arm64-apple-macosx/release/wwn-containerd" \
    /Users/8amps/Wawona/wwn-containers/dependencies/containers/macos/.build/arm64-apple-macosx/release/wwn-containerd \
    "${HOME}/Wawona/wwn-containers/result-1/bin/wwn-containerd"
  do
    if [[ -x "${c}" ]]; then WCD="${c}"; break; fi
  done
fi

die() { echo "macos-container-gui-smoke: $*" >&2; exit 1; }

[[ -S "${SOCKET}" ]] || die "compositor socket missing at ${SOCKET}. Start Wawona tip first."
[[ -x "${WCD}" ]] || die "wwn-containerd not found. Set WAWONA_CONTAINERD."
[[ -e "${KERNEL}" ]] || die "kernel missing: ${KERNEL}"
[[ -x "${GUEST_ROOT}/bin/waypipe" ]] || die "guest waypipe missing under ${GUEST_ROOT}"
[[ -x "${HOST_WP}" ]] || die "host waypipe missing: ${HOST_WP}"

export XDG_RUNTIME_DIR="${RUNTIME}"
export WAYLAND_DISPLAY=wayland-0
export WWNP_WAYPIPE_BIN="${HOST_WP}"
export WAWONA_WAYPIPE_GUEST="${GUEST_ROOT}/bin/waypipe"
export WAWONA_WAYPIPE_GUEST_ROOT="${GUEST_ROOT}"
export WAWONA_WAYPIPE_NO_GPU="${WAWONA_WAYPIPE_NO_GPU:-1}"

CMD="${1:-/bin/echo CONTAINER-GUI-SMOKE-OK}"
ID="wawona-smoke-$$"

echo "using containerd=${WCD}"
echo "guest-root=${GUEST_ROOT} host-waypipe=${HOST_WP}"
exec script -q /dev/null "${WCD}" run \
  --kernel "${KERNEL}" \
  --id "${ID}" \
  -m "${WAWONA_CONTAINER_MEMORY:-2048}" \
  --wayland-vsock-port "${WAWONA_CONTAINER_VSOCK:-1042}" \
  --waypipe-guest-bin "${GUEST_ROOT}/bin/waypipe" \
  --waypipe-guest-root "${GUEST_ROOT}" \
  -i "${WAWONA_CONTAINER_IMAGE:-docker.io/library/alpine:3.20}" \
  /bin/sh -c "${CMD}"
