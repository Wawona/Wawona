{
  pkgs,
  wawonaVersion ? "dev",
  ...
}:

# wawona-vz — native Apple Virtualization.framework launcher for the "NixOS VM"
# machine type (plan p26-vm-nixos). Boots a prebuilt NixOS guest (kernel +
# initrd + rootfs) and bridges its Wayland session into Wawona over
# vsock + waypipe — the OrbStack model (Virtualization.framework + vsock),
# never WSLg's RDP.
#
# Like the other `wawona-*` Apple wrappers in this flake, the Nix build stays
# pure: we only stage the Swift source + entitlements into the store. The actual
# compile + ad-hoc codesign (with the `com.apple.security.virtualization`
# entitlement) happens on first run using the host Xcode toolchain (`xcrun`),
# and the compiled binary is cached under $XDG_CACHE_HOME keyed by the store
# path so it is rebuilt only when the source changes.

let
  swiftSrc = ../../src/platform/macos/vm/WawonaLinuxVZ.swift;
  entitlements = ../../src/platform/macos/vm/wawona-vz.entitlements;
in
pkgs.writeShellApplication {
  name = "wawona-vz-run";
  runtimeInputs = [ pkgs.coreutils ];
  text = ''
    set -euo pipefail

    # System toolchain (not from Nix): Virtualization.framework + codesign live
    # in the host Xcode / macOS. Resolve via absolute paths so writeShellApplication's
    # sanitized PATH doesn't hide them.
    XCRUN=/usr/bin/xcrun
    CODESIGN=/usr/bin/codesign
    if [ ! -x "$XCRUN" ]; then
      echo "wawona-vz: /usr/bin/xcrun not found — Xcode command line tools required." >&2
      exit 1
    fi

    SWIFT_SRC="${swiftSrc}"
    ENTITLEMENTS="${entitlements}"

    # Cache the compiled+signed binary, keyed by the immutable store hash of the
    # source so upgrades recompile automatically.
    SRC_KEY="$(basename "$(dirname "$SWIFT_SRC")")-$(basename "$SWIFT_SRC")"
    CACHE_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/wawona-vz"
    mkdir -p "$CACHE_DIR"
    BIN="$CACHE_DIR/wawona-vz-${wawonaVersion}-$SRC_KEY"

    if [ ! -x "$BIN" ]; then
      echo "[wawona-vz] compiling launcher (one-time) → $BIN" >&2
      SDK="$("$XCRUN" --sdk macosx --show-sdk-path)"
      "$XCRUN" swiftc -O \
        -sdk "$SDK" \
        -framework Virtualization -framework Foundation \
        -o "$BIN.tmp" "$SWIFT_SRC"
      # Ad-hoc sign with the virtualization entitlement (required to boot a VM).
      "$CODESIGN" --force --sign - --entitlements "$ENTITLEMENTS" "$BIN.tmp"
      mv -f "$BIN.tmp" "$BIN"
    fi

    exec "$BIN" "$@"
  '';
  meta = with pkgs.lib; {
    description = "Boot a NixOS guest via Virtualization.framework and bridge Wayland into Wawona over vsock+waypipe";
    platforms = platforms.darwin;
  };
}
