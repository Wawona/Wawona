{
  lib,
  stdenvNoCC,
  xkeyboard_config,
}:

# Nested weston/niri still compile RMLVO. Wawona's own seat does not (HostKeymapBridge).
# Keep libxkbcommon linked. Do not copy all of symbols/ (the 2+ MB language dump).
# L4 packaging only. libxkbcommon recipe stays L0 wwn-toolchain.

stdenvNoCC.mkDerivation {
  pname = "wawona-xkb-trimmed";
  version = xkeyboard_config.version;
  dontUnpack = true;
  # types + compat + keycodes are small. symbols/ is the bulk; take us/pc/inet
  # plus the files those include for evdev + pc105 + layout us.
  installPhase = ''
    src="${xkeyboard_config}/share/X11/xkb"
    dest="$out/share/X11/xkb"
    mkdir -p "$dest/rules" "$dest/symbols"
    cp -R "$src/types" "$dest/types"
    cp -R "$src/compat" "$dest/compat"
    cp -R "$src/keycodes" "$dest/keycodes"
    cp -L "$src/rules/evdev" "$src/rules/evdev.xml" "$src/rules/evdev.lst" "$dest/rules/"
    for f in us pc inet empty srvr_ctrl keypad level3 eurosign altwin \
             capslock compose nbsp group level5 shift ctrl terminate; do
      if [ -e "$src/symbols/$f" ]; then
        cp -RL "$src/symbols/$f" "$dest/symbols/$f"
      fi
    done
    chmod -R u+w "$dest"
    test -f "$dest/rules/evdev"
    test -f "$dest/symbols/us"
    test -d "$dest/types"
    test -d "$dest/compat"
    test -d "$dest/keycodes"
  '';

  meta = {
    description = "Trimmed xkeyboard-config (us/evdev) for nested weston/niri";
    license = xkeyboard_config.meta.license or lib.licenses.mit;
  };
}
