# Extend a platform nativeDeps attrset with the weston toytoolkit (cairo/pango) closure.
{ buildFn, simulator ? false }:
{
  freetype = buildFn "freetype" { inherit simulator; };
  fribidi = buildFn "fribidi" { inherit simulator; };
  pcre2 = buildFn "pcre2" { inherit simulator; };
  fontconfig = buildFn "fontconfig" { inherit simulator; };
  glib = buildFn "glib" { inherit simulator; };
  harfbuzz = buildFn "harfbuzz" { inherit simulator; };
  cairo = buildFn "cairo" { inherit simulator; };
  pango = buildFn "pango" { inherit simulator; };
  libpng = buildFn "libpng" { inherit simulator; };
  expat = buildFn "expat" { inherit simulator; };
  libintl = buildFn "libintl" { inherit simulator; };
}
