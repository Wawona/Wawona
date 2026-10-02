# Minimal NixOS aarch64-linux guest artifacts for Relay (data only).
# Kernel + rootfs are bundled data. Never downloaded executable code.
#
# Kept tiny: a headless wlroots session (cage + foot). Pixels go to Wawona
# by waypipe over vsock. Relay CPU boots this, not QEMU, not UTM.
#
# Evaluates on any host. Kernel/rootfs build on an aarch64-linux builder.
# Embed in the iOS tipa only after a Relay frame exists on IOMFB.
{
  nixpkgs,
  guestSystem ? "aarch64-linux",
  pageSize ? 4096,
  # vsock port the guest's waypipe server binds; the host engine relays it into
  # Wawona (matches the macOS microvm/vz topology).
  vsockPort ? 1024,
  extraModule ? { },
}:

assert builtins.elem pageSize [
  4096
  16384
];

nixpkgs.lib.nixosSystem {
  system = guestSystem;
  modules = [
    (
      {
        config,
        pkgs,
        lib,
        ...
      }:
      let
        baseKernel = pkgs.linux_latest;
        # Determinate's native Linux builder has a small scratch disk. A full
        # NixOS kernel + thousands of =m objects hits ENOSPC (seen linking
        # net/dsa and vmlinux.o). Start from the NixOS config (ACPI/PCI boot
        # under Apple VZ), flip to 16 KiB pages, drop unused trees and DWARF,
        # disable OF (no DTB forest), then turn every leftover =m off and
        # force Relay virtio/ext4/vsock builtins. Keep MODULES=y so NixOS
        # initrd can read modules.builtin.
        config16k = (pkgs.linuxKernel.linuxConfig {
          inherit (baseKernel) src version;
          makeTarget = "olddefconfig";
          name = "wawona-arm64-16k.config";
        }).overrideAttrs (old: {
          postPatch = (old.postPatch or "") + ''
            cp ${baseKernel.configfile} .config
          '';
          buildPhase = ''
            set -x
            make ARCH=arm64 HOSTCC=gcc olddefconfig
          '';
          installPhase = ''
            scripts/config --disable ARM64_4K_PAGES
            scripts/config --enable ARM64_16K_PAGES
            scripts/config --disable ARM64_64K_PAGES
            scripts/config --disable USB_SUPPORT
            scripts/config --disable SOUND
            scripts/config --disable MEDIA_SUPPORT
            scripts/config --disable WLAN
            scripts/config --disable WIRELESS
            scripts/config --disable BT
            scripts/config --disable DRM
            scripts/config --disable INFINIBAND
            scripts/config --disable CAN
            scripts/config --disable NFC
            scripts/config --disable XEN
            scripts/config --disable HYPERV
            scripts/config --disable CHROME_PLATFORMS
            scripts/config --disable SURFACE_PLATFORMS
            scripts/config --disable FPGA
            scripts/config --disable STAGING
            scripts/config --disable NETFILTER
            scripts/config --disable DEBUG_INFO
            scripts/config --disable DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT
            scripts/config --enable DEBUG_INFO_NONE
            scripts/config --disable KALLSYMS_ALL
            make ARCH=arm64 olddefconfig
            # Force OF off after olddefconfig (deps reselect it). Apple VZ is
            # ACPI; OF rebuilds every arm64 DTB on the builder.
            scripts/config --disable OF
            scripts/config --disable OF_FLATTREE
            scripts/config --disable OF_EARLY_FLATTREE
            scripts/config --disable OF_ADDRESS
            scripts/config --disable OF_IRQ
            sed -i 's/^CONFIG_OF=y$/# CONFIG_OF is not set/' .config
            sed -i 's/^CONFIG_OF_FLATTREE=y$/# CONFIG_OF_FLATTREE is not set/' .config
            # Drop the loadable-module forest that filled the builder disk.
            # Re-enable only what the Relay VZ guest needs as builtins.
            sed -i 's/^CONFIG_\(.*\)=m$/# CONFIG_\1 is not set/' .config
            for opt in \
              MODULES \
              EXT4_FS \
              VIRTIO \
              VIRTIO_PCI \
              VIRTIO_MMIO \
              VIRTIO_MMIO_CMDLINE_DEVICES \
              VIRTIO_BLK \
              VIRTIO_CONSOLE \
              VIRTIO_NET \
              VSOCKETS \
              VIRTIO_VSOCKETS \
              VIRTIO_VSOCKETS_COMMON \
              FUSE_FS \
              VIRTIO_FS \
              HVC_DRIVER \
              DEVTMPFS \
              DEVTMPFS_MOUNT \
              TMPFS \
              OVERLAY_FS \
              BINFMT_ELF \
              ACPI \
              PCI
            do
              scripts/config --enable "$opt"
            done
            make ARCH=arm64 olddefconfig
            # olddefconfig may promote deps back to =m. Purge again, then
            # re-assert builtins without a third olddefconfig.
            if grep -q '=m$' .config; then
              sed -i 's/^CONFIG_\(.*\)=m$/# CONFIG_\1 is not set/' .config
              for opt in \
                MODULES \
                EXT4_FS \
                VIRTIO \
                VIRTIO_PCI \
                VIRTIO_MMIO \
                VIRTIO_MMIO_CMDLINE_DEVICES \
                VIRTIO_BLK \
                VIRTIO_CONSOLE \
                VIRTIO_NET \
                VSOCKETS \
                VIRTIO_VSOCKETS \
                VIRTIO_VSOCKETS_COMMON \
                FUSE_FS \
                VIRTIO_FS \
                HVC_DRIVER \
                DEVTMPFS \
                DEVTMPFS_MOUNT \
                TMPFS \
                OVERLAY_FS \
                BINFMT_ELF \
                ACPI \
                PCI
              do
                scripts/config --enable "$opt"
              done
            fi
            if grep -q '=m$' .config; then
              # scripts/config --enable can revive a few =m deps. Force them
              # builtin so the builder never links a module tree.
              sed -i 's/=m$/=y/' .config
            fi
            if grep -q '=m$' .config; then
              echo "16k config still has loadable modules:" >&2
              grep '=m$' .config >&2
              exit 1
            fi
            # Final OF kill. Enabling ACPI/PCI deps can rewrite OF=y.
            scripts/config --disable OF
            scripts/config --disable OF_FLATTREE
            sed -i 's/^CONFIG_OF=y$/# CONFIG_OF is not set/' .config
            sed -i 's/^CONFIG_OF_FLATTREE=y$/# CONFIG_OF_FLATTREE is not set/' .config
            scripts/config --disable DEBUG_INFO
            scripts/config --enable DEBUG_INFO_NONE
            grep -qx 'CONFIG_ARM64_16K_PAGES=y' .config
            grep -qx 'CONFIG_MODULES=y' .config
            grep -qx 'CONFIG_EXT4_FS=y' .config
            grep -qx 'CONFIG_VIRTIO_CONSOLE=y' .config
            grep -qx 'CONFIG_VIRTIO_VSOCKETS=y' .config
            grep -qx 'CONFIG_VIRTIO_FS=y' .config
            grep -qx 'CONFIG_ACPI=y' .config
            grep -qx '# CONFIG_OF is not set' .config
            grep -qx 'CONFIG_DEBUG_INFO_NONE=y' .config || grep -qx '# CONFIG_DEBUG_INFO is not set' .config
            cp .config $out
          '';
        });
        kernel16k = (pkgs.linuxManualConfig {
          inherit (baseKernel) src version;
          configfile = config16k;
          allowImportFromDerivation = true;
        }).overrideAttrs (old: {
          # Apple VZ Linux boots via ACPI. Do not spend builder disk on every
          # vendor DTB under arch/arm64/boot/dts. Keep parallelism modest: the
          # builder is 1 vCPU with a small scratch disk, but a fully serial
          # Image build already took ~30m once modules were purged.
          enableParallelBuilding = true;
          enableParallelInstalling = false;
          NIX_BUILD_CORES = "2";
          installTargets = [ "install" ];
          installFlags = builtins.filter (
            flag:
            flag != "dtbs_install" && !(builtins.match "INSTALL_DTBS_PATH=.*" flag != null)
          ) (old.installFlags or [ ]);
          buildFlags = [
            "KBUILD_BUILD_VERSION=1-NixOS"
            "Image"
            "modules"
          ];
          # NixOS postInstall copies gdb constants.py and a full source tree
          # into $dev. We disable GDB_SCRIPTS and do not build OOT modules for
          # this guest, so keep $dev minimal and only ship modules.builtin.
          postInstall = ''
            mkdir -p "$dev" "$modules"
            if [ -z "''${dontStrip-}" ]; then
              installFlags+=("INSTALL_MOD_STRIP=1")
            fi
            make modules_install "''${makeFlags[@]}" "''${installFlags[@]}"
            mkdir -p "$dev/lib/modules/${baseKernel.version}"
            if [ -d "$modules/lib/modules/${baseKernel.version}" ]; then
              ln -sfn "$modules/lib/modules/${baseKernel.version}" \
                "$dev/lib/modules/${baseKernel.version}"
            fi
            cp -f "$buildRoot/.config" "$dev/config" || true
            cp -f System.map "$dev/System.map" || true
          '';
        });
      in
      {
        nixpkgs.hostPlatform = guestSystem;
        networking.hostName = "wawona-mobile-guest";
        system.stateVersion = "24.11";

        # Keep the direct-kernel mobile initrd small. It only discovers the
        # Relay virtio-mmio root disk and hands off to stage 2.
        # Avoid staging systemd's broad closure, including ncurses' colliding
        # terminfo names, through the native macOS Linux builder's VirtioFS
        # mount.
        boot.initrd.systemd.enable = false;
        boot.initrd.includeDefaultModules = false;
        boot.loader.grub.enable = false;
        boot.kernelPackages =
          if pageSize == 16384 then pkgs.linuxPackagesFor kernel16k else pkgs.linuxPackages_latest;
        boot.kernelParams = [
          "console=hvc0"
          "quiet"
        ];
        # Relay CPU boots the ext4 rootfs off virtio-blk (/dev/vda). The
        # engine passes the kernel + this rootfs directly (no bootloader).
        boot.initrd.availableKernelModules = {
          virtio_mmio = true;
          virtio_blk = true;
          virtio_console = true;
          vmw_vsock_virtio_transport = true;
          virtiofs = true;
          fuse = true;
          overlay = true;
          # ext4.nix also adds ext2. Relay exposes only an ext4 root disk, and
          # the case-insensitive VirtioFS builder cannot safely stage ext2.
          ext2 = lib.mkForce false;
        };
        fileSystems."/" = {
          device = "/dev/vda";
          fsType = "ext4";
          autoResize = true;
        };
        # Host Relay shares an OCI runtime bundle (config.json + rootfs/) with
        # tag `oci-bundle` via Virtualization.framework virtiofs. Absent share
        # → mount fails with nofail; wawona-session keeps the default Foot path.
        fileSystems."/run/wawona/oci-bundle" = {
          device = "oci-bundle";
          fsType = "virtiofs";
          options = [
            "ro"
            "nofail"
          ];
        };

        users.users.wawona = {
          isNormalUser = true;
          uid = 1000;
          initialPassword = "wawona";
          # Linger starts user@1000 at boot so /run/user/1000 exists before
          # wawona-session. Without it, getty autologin and the system service
          # race on session scopes (observed as session-1/2.scope failures on
          # the slower 16 KiB guest) and Multi-User never settles cleanly.
          linger = true;
          extraGroups = [
            "wheel"
            "video"
            "input"
          ];
        };
        services.getty.autologinUser = "wawona";
        security.sudo.wheelNeedsPassword = false;

        # Full coldplug with block/tty/net first. Keep upstream
        # systemd-udev-trigger deadlines and dependencies; only replace the
        # trigger command so virtio disks/consoles appear before late probes.
        systemd.services.systemd-udev-trigger.serviceConfig.ExecStart = lib.mkForce [
          ""
          "-${config.systemd.package}/bin/udevadm trigger --type=all --action=add --prioritized-subsystem=block,tty,net,input,module,tpmrm"
        ];

        # Software rendering only. Relay presents guest Wayland SHM through
        # Wawona's userspace display path; no guest GPU passthrough.
        environment.variables = {
          WLR_RENDERER = "pixman";
          WLR_NO_HARDWARE_CURSORS = "1";
        };

        environment.systemPackages = with pkgs; [
          waypipe
          cage
          foot
          wayland-utils
          crun
        ];

        # Headless Wayland session forwarded to the host over vsock on boot.
        # When the host shares an OCI bundle, skip Foot and run crun instead.
        systemd.services.wawona-session = {
          description = "Wawona mobile Wayland session forwarded over vsock";
          wantedBy = [ "multi-user.target" ];
          after = [
            "systemd-user-sessions.service"
            "user-runtime-dir@1000.service"
            "user@1000.service"
          ];
          wants = [
            "user-runtime-dir@1000.service"
            "user@1000.service"
          ];
          unitConfig = {
            ConditionPathExists = "!/run/wawona/oci-bundle/config.json";
            # Bound readiness: always-restart hid Multi-User settling failures.
            StartLimitIntervalSec = 60;
            StartLimitBurst = 10;
          };
          serviceConfig = {
            User = "wawona";
            WorkingDirectory = "/home/wawona";
            Restart = "on-failure";
            RestartSec = "2s";
            StandardOutput = "journal+console";
            StandardError = "journal+console";
          };
          environment = {
            XDG_RUNTIME_DIR = "/run/user/1000";
            WLR_BACKENDS = "headless";
            WLR_RENDERER = "pixman";
            WLR_NO_HARDWARE_CURSORS = "1";
          };
          script = ''
            set -euo pipefail
            # Runtime dir must already exist from linger/user@1000. Refuse to
            # mkdir as a fallback: that raced getty sessions on 16 KiB boots.
            test -d "$XDG_RUNTIME_DIR"
            exec ${pkgs.waypipe}/bin/waypipe --vsock -s ${toString vsockPort} server -- \
              ${pkgs.cage}/bin/cage -- ${pkgs.foot}/bin/foot
          '';
          postStart = ''
            sleep 2
            printf 'WAWONA_RELAY_READY=1\n' > /dev/hvc0
          '';
        };

        systemd.services.wawona-container = {
          description = "Wawona OCI-in-VM client forwarded over vsock";
          wantedBy = [ "multi-user.target" ];
          after = [
            "local-fs.target"
            "systemd-user-sessions.service"
            "user-runtime-dir@1000.service"
            "user@1000.service"
          ];
          wants = [
            "user-runtime-dir@1000.service"
            "user@1000.service"
          ];
          unitConfig = {
            ConditionPathExists = "/run/wawona/oci-bundle/config.json";
            RequiresMountsFor = "/run/wawona/oci-bundle";
          };
          serviceConfig = {
            Restart = "on-failure";
            RestartSec = "3s";
            RuntimeDirectory = "wawona-container";
            StandardOutput = "journal+console";
            StandardError = "journal+console";
          };
          environment = {
            XDG_RUNTIME_DIR = "/run/user/1000";
          };
          script = ''
            set -euo pipefail
            bundle=/run/wawona/oci-bundle
            work=/run/wawona-container/bundle
            upper=/run/wawona-container/upper
            overlay_work=/run/wawona-container/overlay-work
            test -d "$XDG_RUNTIME_DIR"
            mkdir -p "$work/rootfs" "$upper" "$overlay_work"
            cp "$bundle/config.json" "$work/config.json"
            if ! ${pkgs.util-linux}/bin/mount -t overlay overlay \
              -o "lowerdir=$bundle/rootfs,upperdir=$upper,workdir=$overlay_work" \
              "$work/rootfs"; then
              echo "wawona-container: overlay mount failed" >&2
              exit 1
            fi
            printf 'WAWONA_RELAY_READY=1\n' > /dev/hvc0
            exec ${pkgs.waypipe}/bin/waypipe --vsock -s ${toString vsockPort} server -- \
              ${pkgs.crun}/bin/crun run --bundle "$work" wawona-oci
          '';
          postStop = ''
            ${pkgs.crun}/bin/crun delete --force wawona-oci >/dev/null 2>&1 || true
          '';
        };

        # Trim the closure hard for the mobile RAM/space ceiling.
        # No Nix inside the guest: drops nix-daemon AND the pinned nixpkgs
        # flake-registry/NIX_PATH source (~400MB of nixpkgs tree in the image).
        nix.enable = false;
        nixpkgs.flake.setNixPath = false;
        nixpkgs.flake.setFlakeRegistry = false;
        documentation.enable = false;
        documentation.nixos.enable = false;
        documentation.man.enable = false;
        services.udisks2.enable = false;
        fonts.fontconfig.enable = lib.mkDefault true;
      }
    )
    extraModule
  ];
}
