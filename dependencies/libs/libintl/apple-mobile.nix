# libintl passthrough stub for Apple mobile targets (static). Darwin does not ship
# gettext; glib still references g_libintl_* even with -Dnls=disabled. This
# provides identity passthrough symbols for the final Xcode app link.
{
  lib,
  pkgs,
  buildModule,
  simulator ? false,
  iosToolchain ? null,
  pname ? "libintl-apple-mobile",
}:

let
  platformInfo = import ../../toolchains/apple-mobile-platform.nix;
  mobile = platformInfo { inherit iosToolchain simulator; };
in
pkgs.stdenv.mkDerivation {
  inherit pname;
  version = "0.22";
  dontUnpack = true;
  __noChroot = true;

  preConfigure = ''
    ${iosToolchain.mkIOSBuildEnv { inherit simulator; minVersion = mobile.minVersion; }}
  '';

  buildPhase = ''
    runHook preBuild

    cat > libintl.h <<'EOF'
    #ifndef _LIBINTL_H
    #define _LIBINTL_H 1
    #ifdef __cplusplus
    extern "C" {
    #endif
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
    char *ngettext (const char *msgid1, const char *msgid2, unsigned long int n);
    char *dngettext (const char *domainname, const char *msgid1, const char *msgid2, unsigned long int n);
    char *dcngettext (const char *domainname, const char *msgid1, const char *msgid2, unsigned long int n, int category);
    char *textdomain (const char *domainname);
    char *bindtextdomain (const char *domainname, const char *dirname);
    char *bind_textdomain_codeset (const char *domainname, const char *codeset);
    char *g_libintl_gettext (const char *msgid);
    char *g_libintl_dgettext (const char *domainname, const char *msgid);
    char *g_libintl_dcgettext (const char *domainname, const char *msgid, int category);
    char *g_libintl_dngettext (const char *domainname, const char *msgid1, const char *msgid2, unsigned long int n);
    char *g_libintl_textdomain (const char *domainname);
    char *g_libintl_bindtextdomain (const char *domainname, const char *dirname);
    char *g_libintl_bind_textdomain_codeset (const char *domainname, const char *codeset);
    #ifdef __cplusplus
    }
    #endif
    #endif
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

    char *g_libintl_gettext (const char *msgid) { return (char *) msgid; }
    char *g_libintl_dgettext (const char *domainname, const char *msgid) { (void) domainname; return (char *) msgid; }
    char *g_libintl_dcgettext (const char *domainname, const char *msgid, int category) {
      (void) domainname; (void) category; return (char *) msgid;
    }
    char *g_libintl_dngettext (const char *domainname, const char *msgid1, const char *msgid2, unsigned long int n) {
      (void) domainname; return (char *) (n == 1 ? msgid1 : msgid2);
    }
    char *g_libintl_textdomain (const char *domainname) { return (char *) (domainname ? domainname : "messages"); }
    char *g_libintl_bindtextdomain (const char *domainname, const char *dirname) { (void) domainname; return (char *) dirname; }
    char *g_libintl_bind_textdomain_codeset (const char *domainname, const char *codeset) {
      (void) domainname; return (char *) codeset;
    }
    EOF

    "$CC" -c libintl.c -o libintl.o
    "$AR" rcs libintl.a libintl.o

    runHook postBuild
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
    Description: libintl passthrough stub (Apple mobile)
    Version: 0.22
    Libs: -L\''${libdir} -lintl
    Cflags: -I\''${includedir}
    EOF
  '';
}
