{
  stdenvNoCC,
  lib,
}:

# Weston toytoolkit (weston-terminal and the other bundled clients) calls
# xkb_compose_table_new_from_locale() when the keymap arrives. iOS locale is
# "C", and the app has no /usr/share/X11/locale, so libxkbcommon logs
# "couldn't find a Compose file" and the client disables compose.
#
# iso8859-1/Compose is not valid UTF-8. libxkbcommon rejects it. Locale C
# maps at a UTF-8 table instead.

stdenvNoCC.mkDerivation {
  pname = "wawona-x11-locale-trimmed";
  version = "1";
  dontUnpack = true;
  installPhase = ''
    dest="$out/share/X11/locale"
    mkdir -p "$dest/en_US.UTF-8"
    cat > "$dest/compose.dir" <<'EOF'
en_US.UTF-8/Compose:	C
en_US.UTF-8/Compose:	POSIX
en_US.UTF-8/Compose:	C.UTF-8
en_US.UTF-8/Compose:	en_US.UTF-8
en_US.UTF-8/Compose:	en_US
EOF
    cat > "$dest/en_US.UTF-8/Compose" <<'EOF'
# UTF-8 compose sequences for locale C on hosts without X11 locale data.
<dead_acute> <space> : "'" apostrophe
<dead_acute> <a> : "á" aacute
<dead_acute> <A> : "Á" Aacute
<dead_acute> <e> : "é" eacute
<dead_acute> <E> : "É" Eacute
<dead_acute> <i> : "í" iacute
<dead_acute> <I> : "Í" Iacute
<dead_acute> <o> : "ó" oacute
<dead_acute> <O> : "Ó" Oacute
<dead_acute> <u> : "ú" uacute
<dead_acute> <U> : "Ú" Uacute
<dead_grave> <a> : "à" agrave
<dead_grave> <e> : "è" egrave
<dead_grave> <i> : "ì" igrave
<dead_grave> <o> : "ò" ograve
<dead_grave> <u> : "ù" ugrave
<dead_diaeresis> <a> : "ä" adiaeresis
<dead_diaeresis> <e> : "ë" ediaeresis
<dead_diaeresis> <i> : "ï" idiaeresis
<dead_diaeresis> <o> : "ö" odiaeresis
<dead_diaeresis> <u> : "ü" udiaeresis
<dead_tilde> <n> : "ñ" ntilde
<dead_tilde> <N> : "Ñ" Ntilde
<dead_tilde> <a> : "ã" atilde
<dead_circumflex> <a> : "â" acircumflex
<dead_circumflex> <e> : "ê" ecircumflex
<dead_circumflex> <i> : "î" icircumflex
<dead_circumflex> <o> : "ô" ocircumflex
<dead_circumflex> <u> : "û" ucircumflex
<Multi_key> <a> <e> : "æ" ae
<Multi_key> <o> <e> : "œ" oe
<Multi_key> <s> <s> : "ß" ssharp
EOF
    test -f "$dest/compose.dir"
    test -f "$dest/en_US.UTF-8/Compose"
  '';
  meta = {
    description = "UTF-8 X11 Compose table for locale C";
    license = lib.licenses.mit;
  };
}
