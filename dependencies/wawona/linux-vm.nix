{
  pkgs,
  wawonaVersion,
  ...
}:

pkgs.writeShellApplication {
  name = "wawona-linux-vm-run";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.cloud-hypervisor
  ];
  text = ''
    set -euo pipefail

    usage() {
      cat <<'EOF'
Usage: wawona-linux-vm-run [--memory-mb N] [--cpus N] --kernel PATH --rootfs PATH

Launches a NixOS guest with KVM via cloud-hypervisor.
Requires /dev/kvm. No QEMU. No TCG fallback.
EOF
    }

    memory_mb="2048"
    cpus="2"
    kernel=""
    rootfs=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --memory-mb) memory_mb="$2"; shift 2 ;;
        --cpus) cpus="$2"; shift 2 ;;
        --kernel) kernel="$2"; shift 2 ;;
        --rootfs) rootfs="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
      esac
    done

    if [ ! -e /dev/kvm ]; then
      echo "[linux-vm] /dev/kvm missing. Fail closed. No QEMU TCG." >&2
      exit 1
    fi
    if [ -z "$kernel" ] || [ ! -f "$kernel" ]; then
      echo "[linux-vm] --kernel is required (NixOS Image)." >&2
      exit 1
    fi
    if [ -z "$rootfs" ] || [ ! -f "$rootfs" ]; then
      echo "[linux-vm] --rootfs is required (NixOS disk)." >&2
      exit 1
    fi

    echo "[linux-vm] Relay KVM cloud-hypervisor RAM=$memory_mb MB CPUs=$cpus"
    exec cloud-hypervisor \
      --cpus "boot=$cpus" \
      --memory "size=''${memory_mb}M" \
      --kernel "$kernel" \
      --disk "path=$rootfs" \
      --serial tty \
      --console off
  '';
  meta = with pkgs.lib; {
    description = "Run a NixOS guest with Relay KVM (cloud-hypervisor). No QEMU.";
    platforms = platforms.linux;
  };
}
