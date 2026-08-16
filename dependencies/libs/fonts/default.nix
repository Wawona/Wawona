{
  lib,
  stdenvNoCC,
  dejavu_fonts,
  nerd-fonts,
}:

# Shared font tree for every Wawona compositor target (macOS / iOS family /
# Android / Linux AppImage hosts). Terminals (weston-terminal, foot) and zsh
# prompts need a patched Nerd Font; UI chrome keeps DejaVu Sans.
#
# Trimmed on purpose: full jetbrains-mono is ~59MB. We ship NL (no ligatures)
# Nerd Font Mono Regular/Bold/Italic/BoldItalic (~10MB) plus the four DejaVu
# faces already required for weston desktop-shell.
#
# Layout (stable paths for runtime probes):
#   share/fonts/truetype/DejaVuSans{,Mono}{,-Bold}.ttf
#   share/fonts/truetype/JetBrainsMonoNLNerdFontMono-{Regular,Bold,Italic,BoldItalic}.ttf
#
# fontconfig family for mono: "JetBrainsMonoNL Nerd Font Mono"

let
  jbSrc = "${nerd-fonts.jetbrains-mono}/share/fonts/truetype/NerdFonts/JetBrainsMono";
  nerdFaces = [
    "JetBrainsMonoNLNerdFontMono-Regular.ttf"
    "JetBrainsMonoNLNerdFontMono-Bold.ttf"
    "JetBrainsMonoNLNerdFontMono-Italic.ttf"
    "JetBrainsMonoNLNerdFontMono-BoldItalic.ttf"
  ];
  dejavuFaces = [
    "DejaVuSans.ttf"
    "DejaVuSans-Bold.ttf"
    "DejaVuSansMono.ttf"
    "DejaVuSansMono-Bold.ttf"
  ];
in
stdenvNoCC.mkDerivation {
  pname = "wawona-bundled-fonts";
  version = "1.0.0";

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/fonts/truetype"
    for f in ${lib.concatStringsSep " " dejavuFaces}; do
      cp -L "${dejavu_fonts}/share/fonts/truetype/$f" "$out/share/fonts/truetype/"
    done
    for f in ${lib.concatStringsSep " " nerdFaces}; do
      src="${jbSrc}/$f"
      if [ ! -f "$src" ]; then
        echo "missing Nerd Font face: $src" >&2
        exit 1
      fi
      cp -L "$src" "$out/share/fonts/truetype/"
    done
    chmod -R u+w "$out/share/fonts"
    runHook postInstall
  '';

  passthru = {
    monoFamily = "JetBrainsMonoNL Nerd Font Mono";
    sansFamily = "DejaVu Sans";
    monoRegularRelative = "truetype/JetBrainsMonoNLNerdFontMono-Regular.ttf";
    monoRegularFile = "JetBrainsMonoNLNerdFontMono-Regular.ttf";
    inherit nerdFaces dejavuFaces;
  };

  meta = with lib; {
    description = "DejaVu + JetBrainsMono NL Nerd Font Mono for Wawona terminals";
    license = with licenses; [
      # DejaVu
      bitstreamVera
      # JetBrains Mono + Nerd Fonts patcher
      ofl
      mit
    ];
    platforms = platforms.all;
  };
}
