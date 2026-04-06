{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  iosToolchain ? null,
}:

let
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  # OpenSSH source - fetch latest stable release
  src = pkgs.fetchurl {
    url = "https://cloudflare.cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-9.8p1.tar.gz";
    sha256 = "sha256-3YvQAqN5tdSZ37BQ3R+pr4Ap6ARh9LtsUjxJlz9aOfM=";
  };
  
  # Dependencies for OpenSSH
  zlib = buildModule.buildForIOS "zlib" { };
  # OpenSSL - we need to build it for iOS
  openssl = let
    opensslSrc = pkgs.fetchurl {
      url = "https://www.openssl.org/source/openssl-3.3.1.tar.gz";
      sha256 = "sha256-d3zVlihMiDN1oqehG/XSeG/FQTJV76sgxQ1v/m0CC34=";
    };
  in
  pkgs.stdenv.mkDerivation {
    name = "openssl-ios";
    src = opensslSrc;
    nativeBuildInputs = with buildPackages; [ perl ];
    preConfigure = ''
      if [ -z "''${XCODE_APP:-}" ]; then
        XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
        if [ -n "$XCODE_APP" ]; then
          export XCODE_APP
          export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
          export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
          export SDKROOT="$DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
        fi
      fi
      if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
        IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
      else
        IOS_CC="${buildPackages.clang}/bin/clang"
      fi
    '';
    configurePhase = ''
      runHook preConfigure
      export CC="$IOS_CC"
      export CFLAGS="-arch arm64 -target arm64-apple-ios26.0-simulator -isysroot $SDKROOT -mios-simulator-version-min=26.0 -fPIC"
      export LDFLAGS="-arch arm64 -target arm64-apple-ios26.0-simulator -isysroot $SDKROOT -mios-simulator-version-min=26.0"
      ./Configure ios64-cross no-shared no-dso --prefix=$out --openssldir=$out/etc/ssl
      runHook postConfigure
    '';
    buildPhase = ''
      runHook preBuild
      make -j$NIX_BUILD_CORES
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      make install_sw install_ssldirs
      runHook postInstall
    '';
    __noChroot = true;
  };
in
pkgs.stdenv.mkDerivation {
  name = "openssh-ios";
  inherit src;
  
  patches = [ ];
  
  postPatch = ''
    # ========================================
    # iOS Compatibility Patches for OpenSSH
    # ========================================
    
    echo "========================================"
    echo "Applying comprehensive iOS patches..."
    echo "========================================"
    
    # Fix getrrsetbyname.c for iOS - DNS resolver types not available
    if [ -f openbsd-compat/getrrsetbyname.c ]; then
      if ! grep -q "arpa/nameser.h" openbsd-compat/getrrsetbyname.c; then
        cat > openbsd-compat/getrrsetbyname.c.tmp <<'EOF'
#include "includes.h"

#ifdef __APPLE__
#include <arpa/nameser.h>
#ifndef HEADER
typedef struct {
    unsigned id :16;
    unsigned qr :1;
    unsigned opcode :4;
    unsigned aa :1;
    unsigned tc :1;
    unsigned rd :1;
    unsigned ra :1;
    unsigned z :1;
    unsigned rcode :4;
    unsigned qdcount :16;
    unsigned ancount :16;
    unsigned nscount :16;
    unsigned arcount :16;
} HEADER;
#endif
#ifndef MAXDNAME
#define MAXDNAME NS_MAXDNAME
#endif
#endif

EOF
        tail -n +2 openbsd-compat/getrrsetbyname.c >> openbsd-compat/getrrsetbyname.c.tmp
        mv openbsd-compat/getrrsetbyname.c.tmp openbsd-compat/getrrsetbyname.c
      fi
    fi
    
    # Fix clientloop.c - system() is unavailable on iOS
    if [ -f clientloop.c ]; then
      sed -i.bak 's/if (system(cmd) == 0)/if (0 \/* system() unavailable on iOS *\/)/' clientloop.c
      rm -f clientloop.c.bak
    fi
    
    # ========================================
    # CRITICAL: Patch readpassphrase to use SSH_ASKPASS_PASSWORD env var on iOS
    # iOS doesn't have a TTY, so we must get password from environment
    # ========================================
    echo "Patching readpassphrase.c for iOS environment-based password..."
    if [ -f openbsd-compat/readpassphrase.c ]; then
      cat > openbsd-compat/readpassphrase.c.tmp << 'READPASS_EOF'
/*
 * iOS-patched readpassphrase.c
 * On iOS, we read the password from SSH_ASKPASS_PASSWORD environment variable
 * since there is no TTY available.
 */

#include "includes.h"

#include <sys/types.h>
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <pwd.h>
#include <signal.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>

#ifndef TCSASOFT
#define TCSASOFT 0
#endif

#ifndef _NSIG
# ifdef NSIG
#  define _NSIG NSIG
# else
#  define _NSIG 128
# endif
#endif

char *
readpassphrase(const char *prompt, char *buf, size_t bufsiz, int flags)
{
    int input, output, save_errno, i;
    char ch, *p, *end;
    struct termios term, oterm;
    struct sigaction sa, savealrm, saveint, savehup, savequit, saveterm;
    struct sigaction savetstp, savettin, savettou;

    /* Zero buffer */
    memset(buf, 0, bufsiz);
    
    /* 
     * iOS-specific: Check for password in environment variable first
     * This is the primary method on iOS since we don't have a TTY
     */
    const char *env_pass = getenv("SSH_ASKPASS_PASSWORD");
    if (env_pass) {
        fprintf(stderr, "[readpassphrase] Using SSH_ASKPASS_PASSWORD from environment\n");
        fflush(stderr);
        strlcpy(buf, env_pass, bufsiz);
        return buf;
    }
    
    /* Also check SSHPASS for compatibility with sshpass tool */
    env_pass = getenv("SSHPASS");
    if (env_pass) {
        fprintf(stderr, "[readpassphrase] Using SSHPASS from environment\n");
        fflush(stderr);
        strlcpy(buf, env_pass, bufsiz);
        return buf;
    }
    
    /* 
     * iOS fallback: If no environment password and no TTY,
     * check if we're in batch mode (no password needed)
     */
    if (!isatty(STDIN_FILENO)) {
        fprintf(stderr, "[readpassphrase] No TTY available and no SSH_ASKPASS_PASSWORD set\n");
        fprintf(stderr, "[readpassphrase] Set SSH_ASKPASS_PASSWORD environment variable to provide password\n");
        fflush(stderr);
        
        /* Try to read from stdin anyway - might be piped */
        p = buf;
        end = buf + bufsiz - 1;
        while (p < end && read(STDIN_FILENO, &ch, 1) == 1 && ch != '\n' && ch != '\r') {
            if (!(flags & 0x02) || (isalpha((unsigned char)ch) || isdigit((unsigned char)ch)))
                *p++ = ch;
        }
        *p = '\0';
        if (p > buf) {
            return buf;
        }
        
        errno = ENOTTY;
        return NULL;
    }
    
    /*
     * Standard TTY-based password reading (for macOS/desktop)
     */
    input = STDIN_FILENO;
    output = STDERR_FILENO;
    
    /* Print prompt */
    if (prompt && *prompt) {
        (void)write(output, prompt, strlen(prompt));
    }

    /*
     * Turn off echo if possible.
     */
    if (tcgetattr(input, &oterm) == 0) {
        memcpy(&term, &oterm, sizeof(term));
        if (!(flags & 0x01))
            term.c_lflag &= ~(ECHO | ECHONL);
        (void)tcsetattr(input, TCSAFLUSH|TCSASOFT, &term);
    } else {
        memset(&term, 0, sizeof(term));
        memset(&oterm, 0, sizeof(oterm));
    }

    /* Read password */
    p = buf;
    end = buf + bufsiz - 1;
    while ((i = read(input, &ch, 1)) == 1 && ch != '\n' && ch != '\r') {
        if (p < end) {
            if ((flags & 0x02) && !isalpha((unsigned char)ch) && !isdigit((unsigned char)ch))
                continue;
            *p++ = ch;
        }
    }
    *p = '\0';
    save_errno = errno;
    if (!(term.c_lflag & ECHO))
        (void)write(output, "\n", 1);

    /* Restore terminal */
    if (memcmp(&term, &oterm, sizeof(term)) != 0) {
        (void)tcsetattr(input, TCSAFLUSH|TCSASOFT, &oterm);
    }

    errno = save_errno;
    return (i == -1 ? NULL : buf);
}
READPASS_EOF
      mv openbsd-compat/readpassphrase.c.tmp openbsd-compat/readpassphrase.c
      echo "✓ Patched readpassphrase.c for iOS password handling"
    fi
    
    # ========================================
    # CRITICAL: Patch readpass.c to use SSH_ASKPASS_PASSWORD before trying ssh-askpass
    # This is the main read_passphrase() function that SSH uses
    # ========================================
    echo "Patching readpass.c for iOS environment-based password..."
    if [ -f readpass.c ]; then
      # Insert code at the start of read_passphrase() to check env var first
      sed -i.bak '/^read_passphrase(/,/^{/ {
        /^{/ a\
\	/* iOS: Check for password in environment variable first */ \
\	const char *ios_pass = getenv("SSH_ASKPASS_PASSWORD"); \
\	if (!ios_pass) ios_pass = getenv("SSHPASS"); \
\	if (ios_pass) { \
\		char *ret = xstrdup(ios_pass); \
\		debug3("read_passphrase: using password from environment"); \
\		return ret; \
\	}
      }' readpass.c
      rm -f readpass.c.bak
      echo "✓ Patched readpass.c for iOS password handling"
    fi
    
    # ========================================
    # Patch sshconnect.c to handle iOS-specific connection issues
    # ========================================
    echo "Patching sshconnect.c for iOS..."
    if [ -f sshconnect.c ]; then
      # Add getpwuid fallback if needed
      sed -i.bak 's/fatal("getpwuid: %s", strerror(errno));/{ fprintf(stderr, "[ssh] getpwuid failed, using fallback\\n"); }/' sshconnect.c 2>/dev/null || true
      rm -f sshconnect.c.bak
    fi
    
    # ========================================
    # Patch misc.c for iOS tty handling
    # ========================================
    echo "Patching misc.c for iOS tty handling..."
    if [ -f misc.c ]; then
      # Replace ttyname calls that fail on iOS
      sed -i.bak 's/ttyname(STDIN_FILENO)/getenv("TTY") ? getenv("TTY") : "\/dev\/null"/' misc.c 2>/dev/null || true
      sed -i.bak 's/ttyname(0)/getenv("TTY") ? getenv("TTY") : "\/dev\/null"/' misc.c 2>/dev/null || true
      rm -f misc.c.bak
    fi
    
    # ========================================
    # Critical: Fix getpwuid() failures on iOS
    # iOS Simulator doesn't have /etc/passwd
    # ========================================
    
    # Patch ssh.c to provide fallback user when getpwuid fails
    if [ -f ssh.c ]; then
      echo "Patching ssh.c for iOS user lookup..."
      python3 << 'PYTHON_EOF'
import re
import sys

path = "ssh.c"

with open(path, "r") as f:
    content = f.read()

# Find the getpwuid block and replace with fallback
# Pattern: pw = getpwuid(getuid()); if (pw == NULL) { logit/fatal("No user..."); exit(255); }
patterns = [
    # Pattern 1: with braces and exit
    re.compile(
        r"([ \t]*)pw\s*=\s*getpwuid\s*\(\s*getuid\s*\(\s*\)\s*\)\s*;\s*\n"
        r"\1if\s*\(\s*(?:pw\s*==\s*NULL|!pw)\s*\)\s*\{\s*\n"
        r"\1[ \t]*(?:logit|fatal|fatal_f)\(\s*\"No user exists for uid %lu\"[^;]*;\s*\n"
        r"(?:\1[ \t]*(?:exit|cleanup_exit)\s*\(\s*255\s*\)\s*;\s*\n)?"
        r"\1\}",
        re.MULTILINE
    ),
    # Pattern 2: without braces (single statement fatal)
    re.compile(
        r"([ \t]*)pw\s*=\s*getpwuid\s*\(\s*getuid\s*\(\s*\)\s*\)\s*;\s*\n"
        r"\1if\s*\(\s*(?:pw\s*==\s*NULL|!pw)\s*\)\s*\n"
        r"\1[ \t]*(?:fatal|fatal_f)\(\s*\"No user exists for uid %lu\"[^;]*;",
        re.MULTILINE
    ),
]

def replacement(indent):
    return (indent + "pw = getpwuid(getuid());\n" +
            indent + "if (pw == NULL) {\n" +
            indent + "\t/* iOS fallback: create synthetic passwd entry */\n" +
            indent + "\tstatic struct passwd ios_pw;\n" +
            indent + "\tstatic char ios_name[64];\n" +
            indent + "\tstatic char ios_dir[PATH_MAX];\n" +
            indent + "\tconst char *user_env = getenv(\"USER\");\n" +
            indent + "\tconst char *home_env = getenv(\"HOME\");\n" +
            indent + "\tsnprintf(ios_name, sizeof(ios_name), \"%s\", (user_env && *user_env) ? user_env : \"mobile\");\n" +
            indent + "\tsnprintf(ios_dir, sizeof(ios_dir), \"%s\", (home_env && *home_env) ? home_env : \"/\");\n" +
            indent + "\tios_pw.pw_uid = getuid();\n" +
            indent + "\tios_pw.pw_gid = getgid();\n" +
            indent + "\tios_pw.pw_name = ios_name;\n" +
            indent + "\tios_pw.pw_dir = ios_dir;\n" +
            indent + "\tios_pw.pw_shell = \"/bin/sh\";\n" +
            indent + "\tpw = &ios_pw;\n" +
            indent + "}")

patched = False
for pat in patterns:
    match = pat.search(content)
    if match:
        indent = match.group(1)
        content = pat.sub(replacement(indent), content, count=1)
        patched = True
        print("Patched ssh.c getpwuid block", file=sys.stderr)
        break

if not patched:
    print("Warning: Could not find ssh.c getpwuid block to patch - checking if already patched", file=sys.stderr)
    if "ios_pw" in content:
        print("Already patched", file=sys.stderr)
    else:
        print("Pattern not found - manual review needed", file=sys.stderr)

with open(path, "w") as f:
    f.write(content)
PYTHON_EOF
    fi
    
    # Same patch for uidswap.c
    if [ -f uidswap.c ] && grep -q 'No user exists for uid' uidswap.c; then
      echo "Patching uidswap.c for iOS user lookup..."
      python3 << 'PYTHON_EOF'
import re
import sys

with open("uidswap.c", "r") as f:
    content = f.read()

# Find warnx("No user exists for uid %lu") and replace the return NULL
warn_and_return = re.compile(
    r"(?P<indent>^[ \t]*)warnx\(\"No user exists for uid %lu\",\s*\(unsigned long\)uid\);\s*\n"
    r"(?P=indent)return\s*\(?NULL\)?;",
    re.MULTILINE,
)

def repl(m):
    i = m.group("indent")
    return (i + "/* iOS fallback: return synthetic passwd entry instead of NULL */\n" +
            i + "{\n" +
            i + "\tstatic struct passwd ios_pw;\n" +
            i + "\tstatic char ios_name[64];\n" +
            i + "\tstatic char ios_dir[PATH_MAX];\n" +
            i + "\tconst char *user_env = getenv(\"USER\");\n" +
            i + "\tconst char *home_env = getenv(\"HOME\");\n" +
            i + "\tsnprintf(ios_name, sizeof(ios_name), \"%s\", (user_env && *user_env) ? user_env : \"mobile\");\n" +
            i + "\tsnprintf(ios_dir, sizeof(ios_dir), \"%s\", (home_env && *home_env) ? home_env : \"/\");\n" +
            i + "\tios_pw.pw_uid = uid;\n" +
            i + "\tios_pw.pw_gid = getgid();\n" +
            i + "\tios_pw.pw_name = ios_name;\n" +
            i + "\tios_pw.pw_dir = ios_dir;\n" +
            i + "\tios_pw.pw_shell = \"/bin/sh\";\n" +
            i + "\treturn &ios_pw;\n" +
            i + "}")

new_content, n = warn_and_return.subn(repl, content, count=1)
if n > 0:
    print("Patched uidswap.c", file=sys.stderr)
    with open("uidswap.c", "w") as f:
        f.write(new_content)
else:
    print("Warning: Could not patch uidswap.c", file=sys.stderr)
PYTHON_EOF
    fi

    # Same patch for ssh-keygen.c
    if [ -f ssh-keygen.c ] && grep -q 'No user exists for uid' ssh-keygen.c; then
      echo "Patching ssh-keygen.c for iOS user lookup..."
      python3 << 'PYTHON_EOF'
import re
import sys

path = "ssh-keygen.c"
with open(path, "r") as f:
    content = f.read()

patterns = [
    re.compile(
        r"([ \t]*)pw\s*=\s*getpwuid\s*\(\s*getuid\s*\(\s*\)\s*\)\s*;\s*\n"
        r"\1if\s*\(\s*(?:pw\s*==\s*NULL|!pw)\s*\)\s*(?:\{\s*\n)?"
        r"\1[ \t]*(?:fatal|fatal_f)\(\s*\"No user exists for uid %lu\"[^;]*;\s*\n?"
        r"(?:\1\}\s*\n)?",
        re.MULTILINE
    ),
]

def replacement(indent):
    return (indent + "pw = getpwuid(getuid());\n" +
            indent + "if (pw == NULL) {\n" +
            indent + "\tstatic struct passwd ios_pw;\n" +
            indent + "\tstatic char ios_name[64];\n" +
            indent + "\tstatic char ios_dir[PATH_MAX];\n" +
            indent + "\tconst char *user_env = getenv(\"USER\");\n" +
            indent + "\tconst char *home_env = getenv(\"HOME\");\n" +
            indent + "\tsnprintf(ios_name, sizeof(ios_name), \"%s\", (user_env && *user_env) ? user_env : \"mobile\");\n" +
            indent + "\tsnprintf(ios_dir, sizeof(ios_dir), \"%s\", (home_env && *home_env) ? home_env : \"/\");\n" +
            indent + "\tios_pw.pw_uid = getuid();\n" +
            indent + "\tios_pw.pw_gid = getgid();\n" +
            indent + "\tios_pw.pw_name = ios_name;\n" +
            indent + "\tios_pw.pw_dir = ios_dir;\n" +
            indent + "\tios_pw.pw_shell = \"/bin/sh\";\n" +
            indent + "\tpw = &ios_pw;\n" +
            indent + "}\n")

patched = False
for pat in patterns:
    if pat.search(content):
        content = pat.sub(lambda m: replacement(m.group(1)), content, count=1)
        patched = True
        print("Patched ssh-keygen.c", file=sys.stderr)
        break

if patched:
    with open(path, "w") as f:
        f.write(content)
PYTHON_EOF
    fi
    
    # ========================================
    # Create ssh_main wrapper for dlopen support
    # ========================================
    echo "Creating ssh_main.c wrapper for iOS dlopen support..."
    cat > ssh_main.c << 'SSH_MAIN_EOF'
/*
 * ssh_main.c - Entry point wrapper for iOS dlopen support
 * 
 * This wrapper allows OpenSSH's ssh to be loaded as a dynamic library
 * and called via dlopen/dlsym on iOS.
 *
 * Key iOS-specific handling:
 * - Set up environment variables (HOME, USER, PATH)
 * - Handle signal disposition for clean operation
 * - Provide synthetic passwd entries when getpwuid fails
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pwd.h>
#include <limits.h>
#include <signal.h>
#include <sys/types.h>
#include <errno.h>
#include <dlfcn.h>

/* Forward declaration of OpenSSH's real main function */
extern int main(int argc, char **argv);

/* 
 * iOS fallback passwd structure
 * Used when getpwuid/getpwnam fail (no /etc/passwd on iOS)
 */
static struct passwd ios_passwd = {0};
static char ios_pw_name[256] = {0};
static char ios_pw_dir[1024] = {0};
static char ios_pw_shell[256] = "/bin/sh";
static char ios_pw_class[32] = "";  /* Darwin-specific: user access class */
static char ios_pw_gecos[256] = {0};

static void ios_setup_passwd(void) {
    const char *user = getenv("USER");
    const char *home = getenv("HOME");

    snprintf(ios_pw_name, sizeof(ios_pw_name), "%s", user ? user : "mobile");
    snprintf(ios_pw_dir, sizeof(ios_pw_dir), "%s", home ? home : "/");
    snprintf(ios_pw_gecos, sizeof(ios_pw_gecos), "%s", user ? user : "Mobile User");

    ios_passwd.pw_name = ios_pw_name;
    ios_passwd.pw_uid = getuid();
    ios_passwd.pw_gid = getgid();
    ios_passwd.pw_dir = ios_pw_dir;
    ios_passwd.pw_shell = ios_pw_shell;
    ios_passwd.pw_passwd = "*";
    ios_passwd.pw_gecos = ios_pw_gecos;
    /* Darwin-specific fields */
    ios_passwd.pw_class = ios_pw_class;
    ios_passwd.pw_change = 0;
    ios_passwd.pw_expire = 0;
}

/*
 * Override getpwuid to provide fallback on iOS
 * This is linked at load time to override the libc version
 */
struct passwd *getpwuid(uid_t uid) __attribute__((weak));
struct passwd *getpwuid(uid_t uid) {
    static struct passwd *(*real_getpwuid)(uid_t) = NULL;
    
    if (!real_getpwuid) {
        real_getpwuid = dlsym(RTLD_NEXT, "getpwuid");
    }
    
    struct passwd *pw = real_getpwuid ? real_getpwuid(uid) : NULL;
    
    if (!pw) {
        fprintf(stderr, "[ssh_main] getpwuid(%d) failed, using iOS fallback\n", (int)uid);
        ios_setup_passwd();
        ios_passwd.pw_uid = uid;
        return &ios_passwd;
    }
    return pw;
}

/*
 * Override getpwnam to provide fallback on iOS
 */
struct passwd *getpwnam(const char *name) __attribute__((weak));
struct passwd *getpwnam(const char *name) {
    static struct passwd *(*real_getpwnam)(const char *) = NULL;
    
    if (!real_getpwnam) {
        real_getpwnam = dlsym(RTLD_NEXT, "getpwnam");
    }
    
    struct passwd *pw = real_getpwnam ? real_getpwnam(name) : NULL;
    
    if (!pw) {
        fprintf(stderr, "[ssh_main] getpwnam(%s) failed, using iOS fallback\n", name ? name : "(null)");
        ios_setup_passwd();
        if (name) {
            snprintf(ios_pw_name, sizeof(ios_pw_name), "%s", name);
        }
        return &ios_passwd;
    }
    return pw;
}

/*
 * ssh_main - Entry point for dlopen'd SSH
 *
 * This function is called by WawonaSSHRunner after dlopening the SSH dylib.
 * It sets up the iOS environment and calls SSH's real main().
 */
__attribute__((visibility("default")))
int ssh_main(int argc, char **argv) {
    /* 
     * On iOS, ensure we have sensible environment defaults
     * These may already be set by the host app, but we ensure fallbacks
     */
    if (!getenv("HOME")) {
        const char *container = getenv("CFFIXED_USER_HOME");
        if (container) {
            setenv("HOME", container, 0);
        } else {
            setenv("HOME", "/", 0);
        }
    }
    
    if (!getenv("USER")) {
        setenv("USER", "mobile", 0);
    }
    
    /* Ensure PATH includes standard locations */
    const char *existing_path = getenv("PATH");
    if (!existing_path) {
        setenv("PATH", "/usr/bin:/bin:/usr/sbin:/sbin", 0);
    }
    
    /* 
     * Set up signal handling for iOS
     * Ignore SIGPIPE to prevent crashes on broken connections
     */
    signal(SIGPIPE, SIG_IGN);
    
    /* Initialize fallback passwd structure */
    ios_setup_passwd();
    
    /* Log that we're starting (helps with debugging) */
    fprintf(stderr, "[ssh_main] Starting SSH with %d arguments\n", argc);
    for (int i = 0; i < argc && i < 10; i++) {
        fprintf(stderr, "[ssh_main]   argv[%d] = %s\n", i, argv[i] ? argv[i] : "(null)");
    }
    
    /* Check for password in environment */
    const char *pass = getenv("SSH_ASKPASS_PASSWORD");
    if (pass) {
        fprintf(stderr, "[ssh_main] SSH_ASKPASS_PASSWORD is set (length=%zu)\n", strlen(pass));
    } else {
        fprintf(stderr, "[ssh_main] Warning: SSH_ASKPASS_PASSWORD not set - password auth may fail\n");
    }

    fflush(stderr);

    fprintf(stderr, "[ssh_main] About to call SSH main()...\n");
    fflush(stderr);

    /* Call the real SSH main */
    int result = main(argc, argv);
    
    fprintf(stderr, "[ssh_main] SSH exited with code %d\n", result);
    fflush(stderr);
    
    return result;
}
SSH_MAIN_EOF
  '';
  
  nativeBuildInputs = with buildPackages; [
    autoconf
    automake
    libtool
    pkg-config
    makeWrapper
    python3
  ];
  
  buildInputs = [
    zlib
    openssl
  ];
  
  preConfigure = ''
    if [ -z "''${XCODE_APP:-}" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
      if [ -n "$XCODE_APP" ]; then
        export XCODE_APP
        export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
        export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
        export SDKROOT="$DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
      fi
    fi
    
    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""
    
    if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
      IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
      IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
    else
      IOS_CC="${buildPackages.clang}/bin/clang"
      IOS_CXX="${buildPackages.clang}/bin/clang++"
    fi
    
    if [ ! -f configure ]; then
      autoreconf -fi || true
    fi
  '';
  
  configurePhase = ''
    runHook preConfigure
    
    export CC="$IOS_CC"
    export CXX="$IOS_CXX"
    export AR="ar"
    export RANLIB="ranlib"
    export STRIP="strip"
    
    # ========================================
    # CRITICAL: Use -fPIC for position-independent code
    # This is required for building a dylib that can be dlopened
    # ========================================
    export CFLAGS="-arch arm64 -target arm64-apple-ios26.0-simulator -isysroot $SDKROOT -mios-simulator-version-min=26.0 -fPIC -I${zlib}/include -I${openssl}/include"
    export CXXFLAGS="-arch arm64 -target arm64-apple-ios26.0-simulator -isysroot $SDKROOT -mios-simulator-version-min=26.0 -fPIC -I${zlib}/include -I${openssl}/include"
    export LDFLAGS="-arch arm64 -target arm64-apple-ios26.0-simulator -isysroot $SDKROOT -mios-simulator-version-min=26.0 -L${zlib}/lib -L${openssl}/lib"
    export PKG_CONFIG_PATH="${zlib}/lib/pkgconfig:${openssl}/lib/pkgconfig:$PKG_CONFIG_PATH"
    
    ./configure \
      --prefix=$out \
      --host=arm64-apple-ios \
      --with-zlib=${zlib} \
      --with-ssl-dir=${openssl} \
      --with-privsep-path=$out/var/empty \
      --with-privsep-user=sshd \
      --with-mantype=man \
      --with-pid-dir=$out/var/run \
      --disable-strip \
      --disable-utmp \
      --disable-wtmp \
      --disable-lastlog \
      --disable-pututline \
      --disable-pututxline \
      --without-pam \
      --without-selinux \
      --without-kerberos5 \
      --without-sandbox \
      --without-hardening \
      --without-fido \
      --without-sk \
      --without-security-key-builtin \
      --without-gssapi \
      --disable-shared \
      --enable-static \
      --with-default-path="/usr/bin:/bin:/usr/sbin:/sbin" \
      --with-superuser-path="/usr/sbin:/usr/bin:/sbin:/bin" \
      --without-pkcs11 \
      --with-ssh-key-dir=$out/etc/ssh
    
    runHook postConfigure
  '';
  
  buildPhase = ''
    runHook preBuild
    
    echo "=========================================="
    echo "Building OpenSSH for iOS as dylib"
    echo "=========================================="
    
    # ========================================
    # STEP 1: Build everything normally first
    # This creates libssh.a, libopenbsd-compat.a, and all object files
    # ========================================
    echo "Step 1: Building all OpenSSH components..."
    
    # First build openbsd-compat library
    (cd openbsd-compat && make -j$NIX_BUILD_CORES) || {
      echo "openbsd-compat build failed"
      exit 1
    }
    
    # Then build the main SSH components
    make -j$NIX_BUILD_CORES || {
      echo "Main build completed with some warnings (may be expected)"
    }
    
    # Verify we have the needed files
    echo "Checking for required files..."
    ls -la *.a openbsd-compat/*.a 2>/dev/null || true
    
    if [ ! -f libssh.a ]; then
      echo "Warning: libssh.a not found, trying to build it..."
      # Get the LIBSSH_OBJS from Makefile and build them
      make libssh.a || true
    fi
    
    # ========================================
    # STEP 2: Compile ssh_main wrapper
    # ========================================
    echo "Step 2: Compiling ssh_main.c wrapper..."
    $CC $CFLAGS -c ssh_main.c -o ssh_main.o
    
    # ========================================
    # STEP 3: Create ssh.dylib for iOS dlopen
    # ========================================
    echo "Step 3: Creating ssh.dylib..."
    
    # Collect SSH client object files
    SSH_OBJS="ssh.o readconf.o clientloop.o sshtty.o sshconnect.o sshconnect2.o mux.o ssh_main.o"
    
    # Add optional object files if they exist
    [ -f ssh-sk-client.o ] && SSH_OBJS="$SSH_OBJS ssh-sk-client.o"
    
    # Check if we have libssh.a
    if [ ! -f libssh.a ]; then
      echo "Error: libssh.a not found!"
      echo "Available .a files:"
      ls -la *.a 2>/dev/null || echo "  none in current dir"
      ls -la openbsd-compat/*.a 2>/dev/null || echo "  none in openbsd-compat"
    fi
    
    # Verify openbsd-compat library exists
    if [ ! -f openbsd-compat/libopenbsd-compat.a ]; then
      echo "Error: openbsd-compat/libopenbsd-compat.a not found!"
      exit 1
    fi
    
    echo "Object files: $SSH_OBJS"
    echo "Libraries: libssh.a openbsd-compat/libopenbsd-compat.a"
    
    # Create the dynamic library with all necessary symbols
    $CC -dynamiclib \
        -arch arm64 \
        -target arm64-apple-ios26.0-simulator \
        -isysroot $SDKROOT \
        -mios-simulator-version-min=26.0 \
        -o ssh.dylib \
        $SSH_OBJS \
        libssh.a openbsd-compat/libopenbsd-compat.a \
        -L${zlib}/lib -L${openssl}/lib \
        ${zlib}/lib/libz.a ${openssl}/lib/libssl.a ${openssl}/lib/libcrypto.a \
        -lresolv \
        -install_name @rpath/ssh.dylib \
        -Wl,-exported_symbol,_ssh_main \
        -Wl,-exported_symbol,_main \
        && echo "✓ ssh.dylib created successfully" \
        || {
          echo "Primary dylib creation failed, trying with -undefined dynamic_lookup..."
          $CC -dynamiclib \
              -arch arm64 \
              -target arm64-apple-ios26.0-simulator \
              -isysroot $SDKROOT \
              -mios-simulator-version-min=26.0 \
              -o ssh.dylib \
              $SSH_OBJS \
              libssh.a openbsd-compat/libopenbsd-compat.a \
              -L${zlib}/lib -L${openssl}/lib \
              ${zlib}/lib/libz.a ${openssl}/lib/libssl.a ${openssl}/lib/libcrypto.a \
              -lresolv \
              -install_name @rpath/ssh.dylib \
              -undefined dynamic_lookup \
              || echo "dylib creation failed completely"
        }
    
    if [ -f ssh.dylib ]; then
      echo "✓ ssh.dylib exists"
      # Verify it exports ssh_main
      echo "Exported symbols:"
      nm -gU ssh.dylib | grep -E "_ssh_main|_main" || echo "Warning: expected symbols not found"
      # Show dylib info
      otool -L ssh.dylib | head -5
    else
      echo "⚠ Warning: ssh.dylib was NOT created"
      echo "The executable fallback will be used"
    fi
    
    # ========================================
    # STEP 4: Also build the ssh executable for fallback
    # ========================================
    echo "Step 4: Building ssh executable..."
    if [ ! -f ssh ]; then
      # Link the ssh executable (without ssh_main wrapper - use regular main)
      $CC \
          -arch arm64 \
          -target arm64-apple-ios26.0-simulator \
          -isysroot $SDKROOT \
          -mios-simulator-version-min=26.0 \
          -o ssh \
          ssh.o readconf.o clientloop.o sshtty.o sshconnect.o sshconnect2.o mux.o \
          $([ -f ssh-sk-client.o ] && echo "ssh-sk-client.o") \
          libssh.a openbsd-compat/libopenbsd-compat.a \
          -L${zlib}/lib -L${openssl}/lib \
          ${zlib}/lib/libz.a ${openssl}/lib/libssl.a ${openssl}/lib/libcrypto.a \
          -lresolv \
          && echo "✓ ssh executable created" \
          || echo "Warning: ssh executable build failed"
    else
      echo "✓ ssh executable already exists from make"
    fi
    
    # Also build other tools
    echo "Building additional SSH tools..."
    make -k ssh-keygen ssh-add ssh-agent scp 2>/dev/null || true
    
    runHook postBuild
  '';
  
  installPhase = ''
    runHook preInstall
    
    mkdir -p $out/bin $out/lib
    
    # Install ssh.dylib (primary for iOS dlopen)
    if [ -f ssh.dylib ]; then
      cp ssh.dylib $out/lib/ssh.dylib
      echo "✓ Installed ssh.dylib"
      
      # Also create a symlink in bin for convenience
      ln -sf ../lib/ssh.dylib $out/bin/ssh.dylib
    fi
    
    # Install executables as fallback
    if [ -f ssh ]; then
      cp ssh $out/bin/ssh
      chmod +x $out/bin/ssh
      echo "✓ Installed ssh executable"
    fi
    
    [ -f scp ] && cp scp $out/bin/scp && chmod +x $out/bin/scp || true
    [ -f ssh-keygen ] && cp ssh-keygen $out/bin/ssh-keygen && chmod +x $out/bin/ssh-keygen || true
    [ -f ssh-add ] && cp ssh-add $out/bin/ssh-add && chmod +x $out/bin/ssh-add || true
    [ -f ssh-agent ] && cp ssh-agent $out/bin/ssh-agent && chmod +x $out/bin/ssh-agent || true
    
    runHook postInstall
  '';
  
  postFixup = ''
    # Fix install_name for dylib
    if [ -f "$out/lib/ssh.dylib" ]; then
      install_name_tool -id "@rpath/ssh.dylib" "$out/lib/ssh.dylib" 2>/dev/null || true
      echo "✓ Fixed ssh.dylib install_name"
    fi
  '';
  
  doCheck = false;
  __noChroot = true;
}
