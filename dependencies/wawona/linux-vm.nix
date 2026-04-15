{
  pkgs,
  wawonaVersion,
  ...
}:

pkgs.writeShellApplication {
  name = "wawona-linux-vm-run";
  runtimeInputs = [
    pkgs.nix
    pkgs.coreutils
    pkgs.qemu
    pkgs.nixos-generators
    pkgs.gnugrep
  ];
  text = ''
    set -euo pipefail

    usage() {
      cat <<'EOF'
Usage: wawona-linux-vm-run [--memory-mb N] [--cpus N] [--no-gui]

Launches a NixOS VM image with KDE Plasma 6 Wayland in QEMU.
Acceleration selection:
  - Linux: kvm (fallback tcg)
  - macOS: hvf (fallback tcg; prints virtualization.framework advisory)
EOF
    }

    memory_mb="8192"
    cpus="6"
    display_mode="cocoa"
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --memory-mb) memory_mb="$2"; shift 2 ;;
        --cpus) cpus="$2"; shift 2 ;;
        --no-gui) display_mode="headless"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
      esac
    done

    workdir="$(mktemp -d)"
    trap 'rm -rf "$workdir"' EXIT

    cat > "$workdir/nixos-plasma.nix" <<'EOF'
{ pkgs, ... }:
{
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/vda";
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;
  services.displayManager.defaultSession = "plasma";
  services.xserver.enable = true;
  services.xserver.displayManager.sddm.wayland.enable = true;
  programs.xwayland.enable = true;
  networking.hostName = "wawona-nixos-plasma";
  networking.networkmanager.enable = true;
  users.users.wawona = {
    isNormalUser = true;
    initialPassword = "wawona";
    extraGroups = [ "wheel" "networkmanager" ];
  };
  services.getty.autologinUser = "wawona";
  environment.systemPackages = with pkgs; [ kdePackages.kate kdePackages.konsole git vim ];
  system.stateVersion = "24.11";
}
EOF

    echo "[linux-vm] Building NixOS Plasma qcow image..."
    nixos-generators -f qcow -c "$workdir/nixos-plasma.nix" -o "$workdir/plasma"

    image_path="$(printf '%s\n' "$workdir"/plasma*.qcow2 | while IFS= read -r p; do
      [ -f "$p" ] && { printf '%s\n' "$p"; break; }
    done)"
    if [ ! -f "$image_path" ]; then
      echo "[linux-vm] ERROR: Generated qcow image not found." >&2
      exit 1
    fi

    accel="tcg"
    os_name="$(uname -s)"
    if [ "$os_name" = "Linux" ] && [ -e /dev/kvm ]; then
      accel="kvm"
    fi
    if [ "$os_name" = "Darwin" ]; then
      if qemu-system-x86_64 -accel help 2>/dev/null | rg -q "hvf"; then
        accel="hvf"
      else
        accel="tcg"
      fi
      if [ -d "/System/Library/Frameworks/Virtualization.framework" ] && [ "$accel" != "hvf" ]; then
        echo "[linux-vm] NOTE: Virtualization.framework exists, but QEMU HVF accel unavailable; falling back to TCG."
      fi
    fi

    display_args=()
    if [ "$display_mode" = "headless" ]; then
      display_args=(-nographic)
    else
      display_args=(-display cocoa)
    fi

    echo "[linux-vm] Launching VM (accel=$accel, RAM=$memory_mb MB, CPUs=$cpus, display=$display_mode)..."
    exec qemu-system-x86_64 \
      -machine q35,accel="$accel" \
      -m "$memory_mb" \
      -smp "$cpus" \
      -cpu max \
      -drive "file=$image_path,if=virtio,format=qcow2" \
      -device virtio-net-pci,netdev=net0 \
      -netdev user,id=net0,hostfwd=tcp::2222-:22 \
      "''${display_args[@]}"
  '';
  meta = with pkgs.lib; {
    description = "Run NixOS KDE Plasma 6 VM for Wawona Linux testing";
    platforms = platforms.linux ++ platforms.darwin;
  };
}
