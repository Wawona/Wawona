{
  lib,
  stdenvNoCC,
  fetchurl,
  nerd-fonts,
}:

# Shared font tree for every Wawona compositor target (macOS / iOS family /
# Android / Linux AppImage hosts). Terminals (weston-terminal, foot) and zsh
# prompts need a Nerd-patched mono; UI chrome keeps stock DejaVu Sans.
#
# Do not use pkgs.dejavu_fonts. That rebuilds TTF via fontforge, which pulls
# libtiff docs → Sphinx → mypy pytest on a cache miss.
#
# Terminal mono is DejaVuSansM Nerd Font Mono: same face family we already
# used (DejaVu Sans Mono), with Nerd glyphs patched in. Do not swap the
# terminal to an unrelated family (e.g. JetBrains) just for icons.
#
# Layout (stable paths for runtime probes):
#   share/fonts/truetype/DejaVuSans{,-Bold}.ttf
#   share/fonts/truetype/DejaVuSansMono{,-Bold}.ttf   (unpatched fallback)
#   share/fonts/truetype/DejaVuSansMNerdFontMono-{Regular,Bold,Oblique,BoldOblique}.ttf
#
# fontconfig family for mono: "DejaVuSansM Nerd Font Mono"

let
  nerdSrc = "${nerd-fonts.dejavu-sans-mono}/share/fonts/truetype/NerdFonts/DejaVuSansM";
  nerdFaces = [
    "DejaVuSansMNerdFontMono-Regular.ttf"
    "DejaVuSansMNerdFontMono-Bold.ttf"
    "DejaVuSansMNerdFontMono-Oblique.ttf"
    "DejaVuSansMNerdFontMono-BoldOblique.ttf"
  ];
  dejavuFaces = [
    "DejaVuSans.ttf"
    "DejaVuSans-Bold.ttf"
    "DejaVuSansMono.ttf"
    "DejaVuSansMono-Bold.ttf"
  ];
  dejavuTtf = fetchurl {
    url = "https://github.com/dejavu-fonts/dejavu-fonts/releases/download/version_2_37/dejavu-fonts-ttf-2.37.tar.bz2";
    sha256 = "1mqpds24wfs5cmfhj57fsfs07mji2z8812i5c4pi5pbi738s977s";
  };
in
stdenvNoCC.mkDerivation {
  pname = "wawona-bundled-fonts";
  version = "1.0.0";

  src = dejavuTtf;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/fonts/truetype"
    for f in ${lib.concatStringsSep " " dejavuFaces}; do
      cp -L "ttf/$f" "$out/share/fonts/truetype/"
    done
    for f in ${lib.concatStringsSep " " nerdFaces}; do
      src="${nerdSrc}/$f"
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
    monoFamily = "DejaVuSansM Nerd Font Mono";
    sansFamily = "DejaVu Sans";
    monoRegularRelative = "truetype/DejaVuSansMNerdFontMono-Regular.ttf";
    monoRegularFile = "DejaVuSansMNerdFontMono-Regular.ttf";
    inherit nerdFaces dejavuFaces;
  };

  meta = with lib; {
    description = "DejaVu Sans + DejaVuSansM Nerd Font Mono for Wawona terminals";
    license = with licenses; [
      bitstreamVera
      ofl
      mit
    ];
    platforms = platforms.all;
  };
}
