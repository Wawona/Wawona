{
  nixpkgs,
  pkgs,
  lib ? pkgs.lib,
  # aarch64-linux so the guest boots natively under Apple Virtualization.framework
  # on Apple Silicon. x86_64-linux guests are possible too but slower (no Rosetta
  # for the whole kernel), so the default targets Apple Silicon hosts.
  system ? "aarch64-linux",
  wawonaVersion ? "dev",
  # Optional extra NixOS module to customize the guest (packages, session, etc).
  extraModule ? { },
  # vsock port the guest waypipe server binds; the host `wawona-vz` bridge
  # forwards this into Wawona's Wayland socket.
  vsockPort ? 6000,
}:

# wawona-nixos-guest — a prebuilt NixOS guest for the p26 "NixOS VM" machine
# type. Produces the three artifacts `wawona-vz` needs for direct-kernel boot:
#
#   result/Image     uncompressed arm64 kernel (VZLinuxBootLoader requirement)
#   result/initrd    initramfs
#   result/rootfs.img  raw ext4 root filesystem (mounted as /dev/vda)
#
# BUILD LOCATION: this is an aarch64-linux derivation. It MUST be built on an
# aarch64-linux machine or via a configured Linux builder — e.g. the user's
# NixOS host, `nix-darwin`'s linux-builder, or a remote builder. It cannot be
# realized on aarch64-darwin directly. See docs/2026-nixos-vm-bridge.md.

let
  guestSystem = nixpkgs.lib.nixosSystem {
    modules = [
      { nixpkgs.hostPlatform = system; }
      (
        { config, pkgs, lib, modulesPath, ... }:
        {
          # Direct-kernel boot: no bootloader, root on the single virtio disk.
          boot.loader.grub.enable = false;
          boot.loader.systemd-boot.enable = false;
          boot.initrd.availableKernelModules = [
            "virtio_pci"
            "virtio_blk"
            "virtio_console"
            "virtio_net"
            "virtiofs"
          ];
          # virtio-vsock guest transport — the Wayland pipe to the host.
          boot.kernelModules = [ "vsock" "vmw_vsock_virtio_transport" ];
          boot.kernelParams = [ "console=hvc0" ];

          fileSystems."/" = {
            device = "/dev/vda";
            fsType = "ext4";
            autoResize = true;
          };

          # Optional host dir shared over virtiofs (tag matches `wawona-vz --share-tag`).
          fileSystems."/mnt/host" = lib.mkDefault {
            device = "wawona";
            fsType = "virtiofs";
            options = [ "nofail" ];
          };

          networking.hostName = "wawona-guest";
          networking.useDHCP = lib.mkDefault true;

          users.users.wawona = {
            isNormalUser = true;
            initialPassword = "wawona";
            extraGroups = [ "wheel" "video" "input" ];
          };
          services.getty.autologinUser = "wawona";
          security.sudo.wheelNeedsPassword = false;

          environment.systemPackages = with pkgs; [
            waypipe
            foot
            wayland-utils
            cage
            git
            vim
          ];

          # Wayland bridge: run a minimal Wayland session (cage kiosk) and forward
          # its clients to the host (Wawona) via waypipe over vsock. `cage` hosts
          # `foot` by default; swap `extraModule` in for a full DE (wwn-niri etc).
          #
          # NOTE: the exact waypipe vsock client/server direction is validated on
          # the NixOS host (see docs/2026-nixos-vm-bridge.md). This service is the
          # integration point, deliberately simple.
          systemd.services.wawona-wayland-bridge = {
            description = "Wawona Wayland session forwarded to host over vsock";
            wantedBy = [ "multi-user.target" ];
            after = [ "systemd-user-sessions.service" ];
            serviceConfig = {
              User = "wawona";
              PAMName = "login";
              WorkingDirectory = "/home/wawona";
              TTYPath = "/dev/tty7";
              Restart = "always";
              RestartSec = "2s";
            };
            environment = {
              XDG_RUNTIME_DIR = "/run/user/1000";
              WAWONA_VSOCK_PORT = toString vsockPort;
            };
            script = ''
              mkdir -p "$XDG_RUNTIME_DIR"
              # waypipe server binds the vsock port; host `wawona-vz` connects and
              # relays into Wawona's Wayland socket. cage provides the guest session.
              exec ${pkgs.waypipe}/bin/waypipe --vsock -s ${toString vsockPort} \
                server -- ${pkgs.cage}/bin/cage -- ${pkgs.foot}/bin/foot
            '';
          };

          system.stateVersion = "24.11";
        }
      )
      extraModule
    ];
  };

  cfg = guestSystem.config;

  # Raw, partition-table-less ext4 image → mount straight as /dev/vda.
  rootfs = import (nixpkgs + "/nixos/lib/make-disk-image.nix") {
    inherit pkgs lib;
    config = cfg;
    partitionTableType = "none";
    format = "raw";
    label = "nixos";
    diskSize = 8192; # MiB; grows via autoResize on first boot
  };
in
pkgs.runCommand "wawona-nixos-guest-${wawonaVersion}"
{
  meta = with lib; {
    description = "Prebuilt NixOS guest (kernel+initrd+rootfs) for Wawona's Virtualization.framework VM bridge";
    platforms = [ "aarch64-linux" "x86_64-linux" ];
  };
} ''
  mkdir -p "$out"
  # Uncompressed arm64 kernel Image (VZ requirement); fall back to bzImage name.
  if [ -e "${cfg.system.build.kernel}/Image" ]; then
    ln -s "${cfg.system.build.kernel}/Image" "$out/Image"
  elif [ -e "${cfg.system.build.kernel}/Image.gz" ]; then
    echo "WARNING: only a compressed kernel Image.gz is available; VZ needs an uncompressed Image." >&2
    ln -s "${cfg.system.build.kernel}/Image.gz" "$out/Image.gz"
  else
    ln -s "${cfg.system.build.kernel}" "$out/kernel"
  fi
  ln -s "${cfg.system.build.initialRamdisk}/initrd" "$out/initrd"
  # make-disk-image emits nixos.img (raw) under the derivation.
  if [ -e "${rootfs}/nixos.img" ]; then
    ln -s "${rootfs}/nixos.img" "$out/rootfs.img"
  else
    for f in ${rootfs}/*.img; do ln -s "$f" "$out/rootfs.img"; break; done
  fi
  cat > "$out/boot-hint.txt" <<EOF
  Boot with:
    wawona-vz --kernel $out/Image --initrd $out/initrd --disk <writable-copy-of>/rootfs.img \\
              --vsock-listen ${toString vsockPort} --forward-unix \$XDG_RUNTIME_DIR/wayland-0
  (copy rootfs.img somewhere writable first — the store copy is read-only)
EOF
''
