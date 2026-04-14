{
  pkgs,
  wawonaVersion,
  ...
}:

pkgs.stdenv.mkDerivation {
  pname = "wawona-visionos";
  version = wawonaVersion;
  dontUnpack = true;

  installPhase = ''
    mkdir -p "$out/bin"
    cat > "$out/bin/wawona-visionos-run" <<'EOF'
    #!/usr/bin/env bash
    set -euo pipefail
    echo "VisionOS shell scaffold is ready. Build/install via Xcode visionOS target."
    EOF
    chmod +x "$out/bin/wawona-visionos-run"
  '';

  meta = with pkgs.lib; {
    description = "Wawona visionOS scaffold package";
    platforms = platforms.darwin;
  };
}
