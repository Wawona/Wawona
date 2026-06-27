#!/usr/bin/env python3
"""Patch zsh Src/exec.c so external commands in the in-process safe subset run
WITHOUT fork/exec on the Apple sandbox (App Store compliant).

Strategy (mirrors how zsh already runs builtins in-process):
  1. At the fork-decision point in execcmd_exec(), if the command is a plain
     external simple command whose argv[0] basename is dispatchable
     (wawona_dispatch_can_handle), set a local flag `wwn_inproc`.
  2. Guard the fork so `wwn_inproc` commands do NOT fork, and add an else-if so
     they do NOT take the fake-exec (entersubsh + execve-replace) path either.
  3. Let zsh apply io redirections into its `save` table as usual, then at the
     point it would call execute() (which execve's), instead call
     wawona_dispatch_inprocess(), restore fds via fixfds(save), and `goto done`
     exactly like the builtin path.

The patch is anchor-based and idempotent. If an anchor is missing (upstream zsh
drift), it exits non-zero so the build fails loudly. Pinned against zsh 5.9.
"""
import sys
from pathlib import Path

EXEC_C = "Src/exec.c"


def fail(msg: str):
    sys.stderr.write("patch-zsh-exec.py: " + msg + "\n")
    sys.exit(1)


def main():
    p = Path(EXEC_C)
    if not p.is_file():
        fail(f"{EXEC_C} not found (run from the zsh source root)")
    src = p.read_text()

    if "WWN_INPROC_DISPATCH" in src:
        print("patch-zsh-exec.py: already applied (idempotent)")
        return

    # 1) FFI declarations + feature macro, right after the exec.c prototypes.
    anchor_inc = '#include "exec.pro"'
    if anchor_inc not in src:
        fail('anchor `#include "exec.pro"` missing in exec.c')
    ffi = anchor_inc + """

#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif
#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
/* In-process external-command dispatch (no fork/exec). See wwn_pty.h. */
#define WWN_INPROC_DISPATCH 1
#define WWN_DISPATCH_NOT_HANDLED (-1)
extern int wawona_dispatch_inprocess(const char *path, char *const argv[],
                                     char *const envp[]);
extern int wawona_dispatch_can_handle(const char *argv0);
extern char **environ;
#endif
"""
    src = src.replace(anchor_inc, ffi, 1)

    # 2) Local flag in execcmd_exec().
    anchor_decl = "    int is_shfunc = 0, is_builtin = 0, is_exec = 0, use_defpath = 0;"
    if anchor_decl not in src:
        fail("execcmd_exec local-decl anchor missing")
    src = src.replace(
        anchor_decl,
        anchor_decl + "\n#ifdef WWN_INPROC_DISPATCH\n    int wwn_inproc = 0;\n#endif",
        1,
    )

    # 3) Decide wwn_inproc right after is_cursh is computed.
    anchor_cursh = (
        "    /* This is nonzero if the command is a current shell procedure? */\n"
        "    is_cursh = (is_builtin || is_shfunc || nullexec || type >= WC_CURSH);"
    )
    if anchor_cursh not in src:
        fail("is_cursh anchor missing")
    src = src.replace(
        anchor_cursh,
        anchor_cursh
        + """
#ifdef WWN_INPROC_DISPATCH
    /* Apple sandbox: a plain external simple command in the in-process safe
     * subset runs builtin-like (no fork, no exec). */
    if (!is_cursh && !do_exec && type == WC_SIMPLE && args && firstnode(args)) {
	char *wwn_a0 = (char *) peekfirst(args);
	if (wwn_a0 && wawona_dispatch_can_handle(wwn_a0))
	    wwn_inproc = 1;
    }
#endif""",
        1,
    )

    # 4) Don't fork when wwn_inproc.
    anchor_fork = (
        "	if (!do_exec &&\n"
        "	    (((is_builtin || is_shfunc) && output) ||\n"
        "	     (!is_cursh && (last1 != 1 || nsigtrapped || havefiles() ||\n"
        "			    fdtable_flocks)))) {"
    )
    if anchor_fork not in src:
        fail("fork-decision anchor missing")
    src = src.replace(
        anchor_fork,
        "	if (!do_exec &&\n"
        "#ifdef WWN_INPROC_DISPATCH\n"
        "	    !wwn_inproc &&\n"
        "#endif\n"
        "	    (((is_builtin || is_shfunc) && output) ||\n"
        "	     (!is_cursh && (last1 != 1 || nsigtrapped || havefiles() ||\n"
        "			    fdtable_flocks)))) {",
        1,
    )

    # 5) Don't fake-exec when wwn_inproc: add an else-if before the external else.
    anchor_else = (
        "	} else {\n"
        "	    /* This is an exec (real or fake) for an external command.    *\n"
        "	     * Note that any form of exec means that the subshell is fake *"
    )
    if anchor_else not in src:
        fail("external-exec else anchor missing")
    src = src.replace(
        anchor_else,
        "#ifdef WWN_INPROC_DISPATCH\n"
        "	} else if (wwn_inproc) {\n"
        "	    /* in-process external command: neither fork nor exec */\n"
        "#endif\n"
        "	} else {\n"
        "	    /* This is an exec (real or fake) for an external command.    *\n"
        "	     * Note that any form of exec means that the subshell is fake *",
        1,
    )

    # 6) Run in-process instead of execute() at the WC_SIMPLE exec site.
    anchor_exec = (
        "	    if (type == WC_SIMPLE || type == WC_TYPESET) {\n"
        "		if (varspc) {\n"
        "		    int addflags = ADDVAR_EXPORT|ADDVAR_RESTRICT;\n"
        "		    if (forked)\n"
        "			addflags |= ADDVAR_RESTORE;\n"
        "		    addvars(state, varspc, addflags);\n"
        "		    if (errflag)\n"
        "			_exit(1);\n"
        "		}\n"
        "		closem(FDT_INTERNAL, 0);"
    )
    if anchor_exec not in src:
        fail("WC_SIMPLE execute() anchor missing")
    src = src.replace(
        anchor_exec,
        "	    if (type == WC_SIMPLE || type == WC_TYPESET) {\n"
        "		if (varspc) {\n"
        "		    int addflags = ADDVAR_EXPORT|ADDVAR_RESTRICT;\n"
        "		    if (forked)\n"
        "			addflags |= ADDVAR_RESTORE;\n"
        "		    addvars(state, varspc, addflags);\n"
        "		    if (errflag)\n"
        "			_exit(1);\n"
        "		}\n"
        "#ifdef WWN_INPROC_DISPATCH\n"
        "		if (wwn_inproc) {\n"
        "		    char **wwn_argv = makecline(args);\n"
        "		    char **wwn_pp;\n"
        "		    int wwn_rc;\n"
        "		    for (wwn_pp = wwn_argv; wwn_pp && *wwn_pp; wwn_pp++)\n"
        "			unmetafy(*wwn_pp, NULL);\n"
        "		    wwn_rc = wawona_dispatch_inprocess(\n"
        "			wwn_argv ? wwn_argv[0] : NULL, wwn_argv, environ);\n"
        "		    if (wwn_rc == WWN_DISPATCH_NOT_HANDLED)\n"
        "			lastval = 127;\n"
        "		    else\n"
        "			lastval = (wwn_rc < 0) ? 1 : (wwn_rc & 0xff);\n"
        "		    fflush(stdout);\n"
        "		    fixfds(save);\n"
        "		    goto done;\n"
        "		}\n"
        "#endif\n"
        "		closem(FDT_INTERNAL, 0);",
        1,
    )

    p.write_text(src)
    print("patch-zsh-exec.py: applied in-process external-command dispatch hook")


if __name__ == "__main__":
    main()
