# libintl passthrough stub for Android (static). Bionic does not ship gettext, and
# glib unconditionally requires an `intl` dependency. Upstream glib falls back to
# the proxy-libintl subproject, which needs git/network at configure time (not
# available in the Nix sandbox). This provides the same thing offline: a tiny
# static libintl.a + libintl.h whose gettext/ngettext/etc. are identity
# passthroughs, discoverable via cc.find_library('intl').
{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  androidToolchain ? (import ../../toolchains/android.nix { inherit lib pkgs; }),
  ...
}:

pkgs.stdenv.mkDerivation {
  name = "libintl-android";
  dontUnpack = true;

  nativeBuildInputs = [ ];

  buildPhase = ''
    cat > libintl.h <<'EOF'
    #ifndef _LIBINTL_H
    #define _LIBINTL_H 1
    #ifdef __cplusplus
    extern "C" {
    #endif
    /* Identity passthrough stubs (proxy-libintl compatible). Macros avoid
     * -Wformat-security failures when glib expands _("msg") -> gettext(msg). */
    #ifndef gettext
    # define gettext(msgid) ((char *) (msgid))
    #endif
    #ifndef dgettext
    # define dgettext(domainname, msgid) ((void) (domainname), (char *) (msgid))
    #endif
    #ifndef dcgettext
    # define dcgettext(domainname, msgid, category) \
        ((void) (domainname), (void) (category), (char *) (msgid))
    #endif
    extern char *ngettext (const char *__msgid1, const char *__msgid2, unsigned long int __n);
    extern char *dngettext (const char *__domainname, const char *__msgid1, const char *__msgid2, unsigned long int __n);
    extern char *dcngettext (const char *__domainname, const char *__msgid1, const char *__msgid2, unsigned long int __n, int __category);
    extern char *textdomain (const char *__domainname);
    extern char *bindtextdomain (const char *__domainname, const char *__dirname);
    extern char *bind_textdomain_codeset (const char *__domainname, const char *__codeset);
    #ifdef __cplusplus
    }
    #endif
    #endif /* libintl.h */
    EOF

    cat > libintl.c <<'EOF'
    #include "libintl.h"
    char *ngettext (const char *msgid1, const char *msgid2, unsigned long int n) {
      return (char *) (n == 1 ? msgid1 : msgid2);
    }
    char *dngettext (const char *domainname, const char *msgid1, const char *msgid2, unsigned long int n) {
      (void) domainname;
      return (char *) (n == 1 ? msgid1 : msgid2);
    }
    char *dcngettext (const char *domainname, const char *msgid1, const char *msgid2, unsigned long int n, int category) {
      (void) domainname; (void) category;
      return (char *) (n == 1 ? msgid1 : msgid2);
    }
    char *textdomain (const char *domainname) { return (char *) (domainname ? domainname : "messages"); }
    char *bindtextdomain (const char *domainname, const char *dirname) { (void) domainname; return (char *) dirname; }
    char *bind_textdomain_codeset (const char *domainname, const char *codeset) { (void) domainname; return (char *) codeset; }
    EOF

    "${androidToolchain.androidCC}" -fPIC -O2 -c libintl.c -o libintl.o
    "${androidToolchain.androidAR}" rcs libintl.a libintl.o
  '';

  installPhase = ''
    mkdir -p $out/lib/pkgconfig $out/include
    cp libintl.a $out/lib/
    cp libintl.h $out/include/
    cat > $out/lib/pkgconfig/intl.pc <<EOF
    prefix=$out
    libdir=$out/lib
    includedir=$out/include

    Name: intl
    Description: libintl passthrough stub (Android)
    Version: 0.22
    Libs: -L\''${libdir} -lintl
    Cflags: -I\''${includedir}
    EOF
  '';
}
