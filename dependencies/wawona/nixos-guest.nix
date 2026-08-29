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

# wawona-nixos-guest. A prebuilt NixOS guest for the p26 "NixOS VM" machine
# type. Produces the three artifacts `wawona-vz` needs for direct-kernel boot:
#
#   result/Image     uncompressed arm64 kernel (VZLinuxBootLoader requirement)
#   result/initrd    initramfs
#   result/rootfs.img  raw ext4 root filesystem (mounted as /dev/vda)
#
# BUILD LOCATION: this is an aarch64-linux derivation, but it builds LOCALLY on
# an Apple Silicon Mac via Determinate Nix's native (Virtualization.framework)
# Linux builder. No separate NixOS host needed. The rootfs is assembled with
# `make-ext4-fs` (a plain derivation, like NixOS sd-images) specifically so it
# does NOT need `make-disk-image`'s QEMU/KVM VM, which can't run nested inside
# the VZ builder. See docs/2026-nixos-vm-bridge.md.

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
          # Modern systemd initrd (also clears the 26.11 scripted-initrd
          # deprecation). NOTE: this does NOT currently build on the Determinate
          # VZ Linux builder. `make-initrd-ng` aborts on a dangling ncurses
          # terminfo symlink (share/terminfo/l/linux) in this store view. The
          # microvm/vfkit track (microvm-guest.nix) builds its own initrd fine and
          # is the working p26 path; this wawona-vz artifact track is deferred
          # until the ncurses/make-initrd-ng issue is resolved. See
          # docs/2026-nixos-vm-bridge.md "Known gaps".
          boot.initrd.systemd.enable = true;
          boot.initrd.availableKernelModules = [
            "virtio_pci"
            "virtio_blk"
            "virtio_console"
            "virtio_net"
            "virtiofs"
          ];
          # virtio-vsock guest transport. The Wayland pipe to the host.
          boot.kernelModules = [ "vsock" "vmw_vsock_virtio_transport" ];
          boot.kernelParams = [ "console=hvc0" ];

          fileSystems."/" = {
            device = "/dev/vda";
            fsType = "ext4";
            autoResize = true;
          };

          # The rootfs is a bare ext4 built by make-ext4-fs containing only the
          # store closure (no partition table, no bootloader). On first boot,
          # grow it to fill the disk and register the store paths in the Nix DB
          # (the sd-image pattern). nix-path-registration is written into the
          # image via populateImageCommands below.
          boot.postBootCommands = ''
            if [ -f /nix-path-registration ]; then
              ${config.nix.package.out}/bin/nix-store --load-db < /nix-path-registration &&
                rm -f /nix-path-registration
            fi
          '';

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

  toplevel = cfg.system.build.toplevel;
  closureInfo = pkgs.closureInfo { rootPaths = [ toplevel ]; };

  # Bare ext4 image containing the store closure. Built by a plain derivation
  # (mkfs.ext4 -d), so NO QEMU/KVM VM is required and it realizes fine on the
  # Determinate VZ Linux builder. Mounted directly as /dev/vda; grows on first
  # boot via autoResize.
  rootfs = pkgs.callPackage (nixpkgs + "/nixos/lib/make-ext4-fs.nix") {
    storePaths = [ toplevel ];
    volumeLabel = "nixos";
    populateImageCommands = ''
      mkdir -p ./files
      cp ${closureInfo}/registration ./files/nix-path-registration
      mkdir -p ./files/{proc,sys,dev,run,tmp,var,root,etc,bin}
    '';
  };

  # Authoritative kernel command line for direct-kernel boot. `init=` points at
  # the built system's stage-2 init (normally a bootloader would append this).
  kernelCmdline =
    "init=${toplevel}/init console=hvc0 root=/dev/vda rw loglevel=4";
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
  # make-ext4-fs emits the image file directly as its $out.
  ln -s "${rootfs}" "$out/rootfs.img"
  # Authoritative kernel cmdline (includes the init= path); pass to wawona-vz.
  printf '%s\n' "${kernelCmdline}" > "$out/cmdline"
  cat > "$out/boot-hint.txt" <<EOF
  # copy rootfs.img somewhere writable first. The store copy is read-only
  cp $out/rootfs.img /tmp/wawona-rootfs.img && chmod u+w /tmp/wawona-rootfs.img
  wawona-vz --kernel $out/Image --initrd $out/initrd --disk /tmp/wawona-rootfs.img \\
            --cmdline "$(cat $out/cmdline)" \\
            --vsock-listen ${toString vsockPort} --forward-unix \$XDG_RUNTIME_DIR/wayland-0
EOF
''
