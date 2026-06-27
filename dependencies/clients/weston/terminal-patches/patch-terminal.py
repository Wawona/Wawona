#!/usr/bin/env python3
"""Apply shared weston-terminal.c patches for Wawona (macOS + Apple mobile)."""

from __future__ import annotations

import sys
from pathlib import Path


def patch_ios_terminal_master(src: str) -> str:
    old = "\tterminal->master = master;\n\tterminal->pace_pipe = pipes[1];"
    new = """\tterminal->master = master;
#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
\twwn_ios_terminal_set_master(master);
#endif
\tterminal->pace_pipe = pipes[1];"""
    if "wwn_ios_terminal_set_master" in src:
        return src
    if old not in src:
        raise SystemExit("terminal master registration anchor missing")
    return src.replace(old, new, 1)


def patch_ios_terminal_destroy_master(src: str) -> str:
    old = "\tclose(terminal->master);\n\n\tcairo_scaled_font_destroy(terminal->font_bold);"
    new = """#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
\twwn_ios_terminal_clear_master(terminal->master);
#endif
\tclose(terminal->master);

\tcairo_scaled_font_destroy(terminal->font_bold);"""
    if "wwn_ios_terminal_clear_master" in src:
        return src
    if old not in src:
        raise SystemExit("terminal destroy master anchor missing")
    return src.replace(old, new, 1)


def patch_ios_terminal_font_face(src: str) -> str:
    old = """\tcairo_set_font_size(cr, option_font_size);
\tcairo_select_font_face (cr, option_font,
\t\t\t\tCAIRO_FONT_SLANT_NORMAL,
\t\t\t\tCAIRO_FONT_WEIGHT_BOLD);
\tterminal->font_bold = cairo_get_scaled_font (cr);
\tcairo_scaled_font_reference(terminal->font_bold);

\tcairo_select_font_face (cr, option_font,
\t\t\t\tCAIRO_FONT_SLANT_NORMAL,
\t\t\t\tCAIRO_FONT_WEIGHT_NORMAL);
\tterminal->font_normal = cairo_get_scaled_font (cr);
\tcairo_scaled_font_reference(terminal->font_normal);"""
    new = """\tcairo_set_font_size(cr, option_font_size);
#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
\tterminal->font_bold = terminal_ios_load_font(cr, 1);
\tterminal->font_normal = terminal_ios_load_font(cr, 0);
\tif (!terminal->font_bold || !terminal->font_normal) {
\t\tWWN_TERM_LOG("weston-terminal: fontconfig/cairo-ft load failed; "
\t\t\t     "FONTCONFIG_FILE=%s\\n",
\t\t\t     getenv("FONTCONFIG_FILE") ? getenv("FONTCONFIG_FILE") : "(unset)");
\t\tcairo_select_font_face(cr, "DejaVu Sans Mono",
\t\t\t\t\tCAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD);
\t\tterminal->font_bold = cairo_get_scaled_font(cr);
\t\tcairo_scaled_font_reference(terminal->font_bold);
\t\tcairo_select_font_face(cr, "DejaVu Sans Mono",
\t\t\t\t\tCAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL);
\t\tterminal->font_normal = cairo_get_scaled_font(cr);
\t\tcairo_scaled_font_reference(terminal->font_normal);
\t}
#else
\tcairo_select_font_face (cr, option_font,
\t\t\t\tCAIRO_FONT_SLANT_NORMAL,
\t\t\t\tCAIRO_FONT_WEIGHT_BOLD);
\tterminal->font_bold = cairo_get_scaled_font (cr);
\tcairo_scaled_font_reference(terminal->font_bold);

\tcairo_select_font_face (cr, option_font,
\t\t\t\tCAIRO_FONT_SLANT_NORMAL,
\t\t\t\tCAIRO_FONT_WEIGHT_NORMAL);
\tterminal->font_normal = cairo_get_scaled_font (cr);
\tcairo_scaled_font_reference(terminal->font_normal);
#endif"""
    if "terminal_ios_load_font" in src:
        return src
    if old not in src:
        raise SystemExit("terminal_create font face anchor missing")
    return src.replace(old, new, 1)


def patch_ios_font_default(src: str) -> str:
    old = '\tweston_config_section_get_string(s, "font", &option_font, "monospace");'
    new = """#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
\tweston_config_section_get_string(s, "font", &option_font, "DejaVu Sans Mono");
#else
\tweston_config_section_get_string(s, "font", &option_font, "monospace");
#endif"""
    if old not in src:
        raise SystemExit("terminal font default patch target not found in terminal.c")
    return src.replace(old, new, 1)


def patch_ios_fontconfig_init(src: str) -> str:
    anchor = '#include "window.h"'
    insert = """
#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
#include <fontconfig/fontconfig.h>
#include <cairo-ft.h>
#endif
"""
    if "cairo-ft.h" in src:
        return src
    if "fontconfig/fontconfig.h" in src and "cairo-ft.h" not in src:
        return src.replace(
            "#include <fontconfig/fontconfig.h>",
            "#include <fontconfig/fontconfig.h>\n#include <cairo-ft.h>",
            1,
        )
    if anchor not in src:
        raise SystemExit("window.h include anchor missing")
    return src.replace(anchor, anchor + insert, 1)


def patch_ios_font_helper_fn(src: str) -> str:
    anchor = "static struct terminal *\nterminal_create(struct display *display)\n{"
    helper = """
#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
static cairo_scaled_font_t *
terminal_ios_load_font(cairo_t *cr, int bold)
{
\tFcPattern *pattern, *match;
\tcairo_font_face_t *face;
\tcairo_scaled_font_t *sf;
\tchar spec[512];
\tconst char *family = option_font;
\tconst char *direct = getenv("WAWONA_MONO_FONT");

\tif (direct && direct[0]) {
\t\tsnprintf(spec, sizeof spec, "file:%s:size=%d:weight=%d",
\t\t\t direct, option_font_size, bold ? 200 : 80);
\t} else {
\t\tif (!family || !family[0])
\t\t\tfamily = "DejaVu Sans Mono";
\t\tsnprintf(spec, sizeof spec, "%s:size=%d:weight=%d",
\t\t\t family, option_font_size, bold ? 200 : 80);
\t}
\tpattern = FcNameParse((const FcChar8 *)spec);
\tif (!pattern)
\t\treturn NULL;
\tFcConfigSubstitute(NULL, pattern, FcMatchPattern);
\tFcDefaultSubstitute(pattern);
\tmatch = FcFontMatch(NULL, pattern, NULL);
\tFcPatternDestroy(pattern);
\tif (!match) {
\t\tWWN_TERM_LOG("weston-terminal: FcFontMatch failed for '%s'\\n", spec);
\t\treturn NULL;
\t}
\tface = cairo_ft_font_face_create_for_pattern(match);
\tFcPatternDestroy(match);
\tif (!face || cairo_font_face_status(face) != CAIRO_STATUS_SUCCESS) {
\t\tWWN_TERM_LOG("weston-terminal: cairo_ft font face failed for '%s'\\n", spec);
\t\tif (face)
\t\t\tcairo_font_face_destroy(face);
\t\treturn NULL;
\t}
\tcairo_set_font_face(cr, face);
\tcairo_set_font_size(cr, option_font_size);
\tsf = cairo_get_scaled_font(cr);
\tif (sf)
\t\tcairo_scaled_font_reference(sf);
\tcairo_font_face_destroy(face);
\treturn sf;
}
#endif

"""
    if "terminal_ios_load_font" in src:
        idx_helper = src.find("terminal_ios_load_font")
        idx_create = src.find(anchor)
        if idx_helper != -1 and (idx_create == -1 or idx_helper < idx_create):
            return src
    if anchor not in src:
        raise SystemExit("terminal_create anchor missing for font helper")
    return src.replace(anchor, helper + anchor, 1)


def patch_ios_font_metrics_log(src: str) -> str:
    old = "\tterminal->average_width = ceil(terminal->average_width);\n\n\tcairo_destroy(cr);"
    new = """\tterminal->average_width = ceil(terminal->average_width);

#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
\tWWN_TERM_LOG("weston-terminal: font cell %.1fx%.1f (avg_w=%.1f FONTCONFIG=%s)\\n",
\t\t     terminal->average_width, terminal->extents.height,
\t\t     terminal->average_width,
\t\t     getenv("FONTCONFIG_FILE") ? getenv("FONTCONFIG_FILE") : "(unset)");
\tif (terminal->average_width < 1.0 || terminal->extents.height < 1.0)
\t\tWWN_TERM_LOG("weston-terminal: WARNING: zero font metrics — text will not render\\n");
#endif

\tcairo_destroy(cr);"""
    if "font cell" in src:
        return src
    if old not in src:
        raise SystemExit("terminal font metrics log anchor missing")
    return src.replace(old, new, 1)


def patch_ios_main_fcinit(src: str) -> str:
    old = "\td = display_create(&argc, argv);"
    new = """#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
\tif (!FcInit())
\t\tWWN_TERM_LOG("weston-terminal: FcInit failed (check FONTCONFIG_FILE)\\n");
#endif
\td = display_create(&argc, argv);"""
    if "FcInit()" in src:
        return src
    if old not in src:
        raise SystemExit("terminal main display_create anchor missing")
    return src.replace(old, new, 1)


def patch_howmany_and_title(src: str) -> str:
    import re

    src = re.sub(r"\bhowmany\b", "WESTON_HOWMANY", src)
    src = src.replace("Wayland Terminal", "Weston Terminal")
    return src


def patch_ios_max_escape(src: str) -> str:
    """Raise OSC/CSI buffer — long OSC 7 cwd URIs must not overflow to the screen."""
    old = "#define MAX_ESCAPE		255"  # tabs match weston terminal.c
    new = "#define MAX_ESCAPE		4096"
    if new in src:
        return src
    if old not in src:
        raise SystemExit("MAX_ESCAPE patch target not found in terminal.c")
    return src.replace(old, new, 1)


def patch_osc7_and_prompt(src: str) -> str:
    old_osc7 = "\tcase 7: /* shell cwd as uri */\n\t\tbreak;"
    new_osc7 = (
        "\tcase 7: { /* shell cwd as uri - extract path for title */\n"
        "\t\tconst char *fp = \"file://\";\n"
        "\t\tif (strncmp(p, fp, 7) == 0) {\n"
        "\t\t\tconst char *sl = strchr(p + 7, '/');\n"
        "\t\t\tif (sl) {\n"
        "\t\t\t\tconst char *hm = getenv(\"HOME\");\n"
        "\t\t\t\tsize_t hlen = hm ? strlen(hm) : 0;\n"
        "\t\t\t\tchar *t = NULL;\n"
        "\t\t\t\tif (hm && strncmp(sl, hm, hlen) == 0\n"
        "\t\t\t\t    && (sl[hlen] == '/' || sl[hlen] == '\\0'))\n"
        "\t\t\t\t\tasprintf(&t, \"~%s\", sl + hlen);\n"
        "\t\t\t\telse\n"
        "\t\t\t\t\tt = strdup(sl);\n"
        "\t\t\t\tif (t) {\n"
        "\t\t\t\t\tfree(terminal->title);\n"
        "\t\t\t\t\tterminal->title = t;\n"
        "\t\t\t\t\twindow_set_title(terminal->window, t);\n"
        "\t\t\t\t}\n"
        "\t\t\t}\n"
        "\t\t}\n"
        "\t\tbreak;\n"
        "\t}"
    )
    if old_osc7 not in src:
        raise SystemExit("OSC 7 patch target not found in terminal.c")
    src = src.replace(old_osc7, new_osc7)

    old_env = '\t\tsetenv("COLORTERM", option_term, 1);'
    prompt = (
        r"printf '\033]0;%s@%s:%s\007' "
        r"\"$USER\" "
        r"\"${HOSTNAME%%.*}\" "
        r"\"${PWD/#$HOME/~}\""
    )
    # PROMPT_COMMAND is a bash-ism. The Apple mobile path runs in-process zsh,
    # which ignores it (and drives its own OSC 7 / title via .zshrc), so only
    # emit it for the non-mobile (macOS/Linux) builds to avoid confusion.
    new_env = (
        old_env
        + "\n#if !defined(__APPLE__) || (!TARGET_OS_IPHONE && !TARGET_OS_TV && !TARGET_OS_WATCH)"
        + '\n\t\tsetenv("PROMPT_COMMAND", "'
        + prompt
        + '", 0);'
        + "\n#endif"
    )
    if old_env not in src:
        raise SystemExit("COLORTERM patch target not found in terminal.c")
    src = src.replace(old_env, new_env)
    return src


def patch_ios_sigpipe(src: str) -> str:
    old_decl = "\tstruct sigaction sigpipe;\n"
    new_decl = """#if !defined(__APPLE__) || (!TARGET_OS_IPHONE && !TARGET_OS_TV && !TARGET_OS_WATCH)
\tstruct sigaction sigpipe;
#endif
"""
    if old_decl in src:
        src = src.replace(old_decl, new_decl, 1)

    old_block = """\tsigpipe.sa_handler = SIG_IGN;
\tsigemptyset(&sigpipe.sa_mask);
\tsigpipe.sa_flags = 0;
\tsigaction(SIGPIPE, &sigpipe, NULL);"""
    new_block = """#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
\tsignal(SIGPIPE, SIG_IGN);
#else
\tsigpipe.sa_handler = SIG_IGN;
\tsigemptyset(&sigpipe.sa_mask);
\tsigpipe.sa_flags = 0;
\tsigaction(SIGPIPE, &sigpipe, NULL);
#endif"""
    if old_block not in src:
        raise SystemExit("SIGPIPE patch target not found in terminal.c")
    return src.replace(old_block, new_block, 1)


def patch_ios_terminal_write(src: str) -> str:
    """Route keyboard bytes to the shell stdin pipe, not the display socketpair."""
    marker = "wwn_ios_terminal_inject(data, length)"
    if marker in src:
        return src
    old = """static void
terminal_write(struct terminal *terminal, const char *data, size_t length)
{
\tif (write(terminal->master, data, length) < 0)
\t\tabort();"""
    new = """static void
terminal_write(struct terminal *terminal, const char *data, size_t length)
{
#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
\tif (wwn_ios_terminal_inject(data, length) < 0)
\t\tabort();
#else
\tif (write(terminal->master, data, length) < 0)
\t\tabort();
#endif"""
    if old not in src:
        raise SystemExit("terminal_write inject anchor missing in terminal.c")
    return src.replace(old, new, 1)


def patch_ios_spawn(src: str) -> str:
    mobile_bootstrap = """
#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif
#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
#define _DARWIN_C_SOURCE
extern char **environ;
#endif
"""
    config_anchor = '#include "config.h"'
    if config_anchor in src and "extern char **environ" not in src:
        src = src.replace(config_anchor, config_anchor + mobile_bootstrap, 1)

    pty_include = """#ifdef __APPLE__
#include <TargetConditionals.h>
#endif
#if !defined(__APPLE__) || (!TARGET_OS_IPHONE && !TARGET_OS_TV && !TARGET_OS_WATCH)
#include <pty.h>
#endif"""
    if "#include <pty.h>" in src:
        src = src.replace("#include <pty.h>", pty_include, 1)

    ios_include = """
#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
#include "wwn_pty.h"
#include <stdlib.h>
static int wwn_term_log_enabled(void) {
\tstatic int enabled = -1;
\tif (enabled < 0)
\t\tenabled = getenv("WAWONA_PTY_QUIET") != NULL ? 0 : 1;
\treturn enabled;
}
#define WWN_TERM_LOG(fmt, ...) do { \\
\tif (wwn_term_log_enabled()) \\
\t\tdprintf(wwn_app_log_fd(), fmt, ##__VA_ARGS__); \\
} while (0)
#define WWN_TERM_INFO(fmt, ...) WWN_TERM_LOG(fmt, ##__VA_ARGS__)
#endif
"""
    anchor = '#include "window.h"'
    if anchor not in src:
        raise SystemExit("window.h include anchor missing")
    if "wwn_pty.h" not in src:
        src = src.replace(anchor, anchor + ios_include, 1)

    waitpid_hook = """
#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
#undef waitpid
#define waitpid(pid, status, options) wwn_pty_ios_waitpid((pid), (status), (options))
#endif
"""
    if "wwn_pty_ios_waitpid" not in src and "wwn_pty.h" in src:
        src = src.replace('#include "wwn_pty.h"', '#include "wwn_pty.h"' + waitpid_hook, 1)

    old_block = """\tpid = forkpty(&master, NULL, NULL, NULL);
\tif (pid == 0) {
\t\tint ret;

\t\tclose(pipes[1]);
\t\tdo {
\t\t\tchar tmp;
\t\t\tret = read(pipes[0], &tmp, 1);
\t\t} while (ret == -1 && errno == EINTR);
\t\tclose(pipes[0]);
\t\tsetenv("TERM", option_term, 1);
\t\tsetenv("COLORTERM", option_term, 1);
\t\tif (execl(path, path, NULL)) {
\t\t\tprintf("exec failed: %s\\n", strerror(errno));
\t\t\texit(EXIT_FAILURE);
\t\t}
\t} else if (pid < 0) {
\t\tfprintf(stderr, "failed to fork and create pty (%s).\\n",
\t\t\tstrerror(errno));
\t\treturn -1;
\t}"""

    new_block = """#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
\t{
\t\tint slave_fd = -1;
\t\tconst char *shell_path = getenv("WAWONA_SHELL");
\t\tchar *const spawn_argv[] = { (char *) path, NULL };

\t\tif (!shell_path || !shell_path[0])
\t\t\tshell_path = path;
\t\tWWN_TERM_LOG("weston-terminal: spawning in-process zsh (WAWONA_ZSH_IN_PROCESS=%s, label=%s)\\n",
\t\t\tgetenv("WAWONA_ZSH_IN_PROCESS") ? getenv("WAWONA_ZSH_IN_PROCESS") : "(unset)",
\t\t\tshell_path);
\t\tif (wwn_pty_open(&master, &slave_fd, NULL) != 0) {
\t\t\tWWN_TERM_LOG("weston-terminal: failed to open pty (%s).\\n", strerror(errno));
\t\t\tclose(pipes[0]);
\t\t\tclose(pipes[1]);
\t\t\treturn -1;
\t\t}
\t\tsetenv("TERM", option_term, 1);
\t\tsetenv("COLORTERM", option_term, 1);
\t\t/* Prompt is owned by zsh (.zshrc PROMPT); do not force PS1/PROMPT here. */
\t\tpid = wwn_pty_spawn_shell_paced(shell_path, spawn_argv, slave_fd,
\t\t\t\t\t\tpipes[0], environ);
\t\tclose(slave_fd);
\t\tif (pid < 0) {
\t\t\tWWN_TERM_LOG("weston-terminal: failed to spawn shell (%s).\\n", strerror(errno));
\t\t\tclose(master);
\t\t\tclose(pipes[0]);
\t\t\tclose(pipes[1]);
\t\t\treturn -1;
\t\t}
\t}
#else
\tpid = forkpty(&master, NULL, NULL, NULL);
\tif (pid == 0) {
\t\tint ret;

\t\tclose(pipes[1]);
\t\tdo {
\t\t\tchar tmp;
\t\t\tret = read(pipes[0], &tmp, 1);
\t\t} while (ret == -1 && errno == EINTR);
\t\tclose(pipes[0]);
\t\tsetenv("TERM", option_term, 1);
\t\tsetenv("COLORTERM", option_term, 1);
\t\tif (execl(path, path, NULL)) {
\t\t\tprintf("exec failed: %s\\n", strerror(errno));
\t\t\texit(EXIT_FAILURE);
\t\t}
\t} else if (pid < 0) {
\t\tfprintf(stderr, "failed to fork and create pty (%s).\\n",
\t\t\tstrerror(errno));
\t\treturn -1;
\t}
#endif"""

    if old_block not in src:
        raise SystemExit("forkpty block not found in terminal.c")
    src = src.replace(old_block, new_block, 1)
    return src


def patch_ios_io_handler_consume(src: str) -> str:
    """Route io_handler through terminal_master_consume on iOS (socketpair-safe)."""
    marker = "terminal_master_consume(terminal);\n\treturn;\n#endif\n\tchar buffer"
    if marker in src:
        return src
    old = """static void
io_handler(struct task *task, uint32_t events)
{
\tstruct terminal *terminal =
\t\tcontainer_of(task, struct terminal, io_task);
\tchar buffer[256];
\tint len;

\tif (events & EPOLLHUP) {"""
    new = """static void
io_handler(struct task *task, uint32_t events)
{
\tstruct terminal *terminal =
\t\tcontainer_of(task, struct terminal, io_task);
#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
\tif (events & (EPOLLIN | EPOLLHUP | EPOLLERR))
\t\tterminal_master_consume(terminal);
\treturn;
#endif
\tchar buffer[256];
\tint len;

\tif (events & EPOLLHUP) {"""
    if old not in src:
        raise SystemExit("io_handler consume patch anchor missing in terminal.c")
    return src.replace(old, new, 1)


def patch_ios_io_handler(src: str) -> str:
    old = """\tlen = read(terminal->master, buffer, sizeof buffer);
\tif (len < 0) {
\t\tterminal_destroy(terminal);
\t\treturn;
\t}

\tterminal_data(terminal, buffer, len);"""
    new = """\tlen = read(terminal->master, buffer, sizeof buffer);
\tif (len < 0) {
#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
\t\tif (errno == EAGAIN || errno == EWOULDBLOCK)
\t\t\treturn;
#endif
\t\tterminal_destroy(terminal);
\t\treturn;
\t}
\tif (len == 0) {
\t\tterminal_destroy(terminal);
\t\treturn;
\t}

\tif (!terminal->data)
\t\treturn;

\tterminal_data(terminal, buffer, len);"""
    if "if (!terminal->data)" in src:
        old_with_redraw = """\tterminal_data(terminal, buffer, len);
#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
\twindow_schedule_redraw(terminal->window);
#endif"""
        if old_with_redraw in src:
            return src.replace(old_with_redraw, "\tterminal_data(terminal, buffer, len);", 1)
        return src
    if old not in src:
        raise SystemExit("io_handler read patch target not found in terminal.c")
    return src.replace(old, new, 1)


def patch_ios_redraw_show_text(src: str) -> str:
    """Draw each cell with cairo_show_text; text_to_glyphs batching fails on iOS."""
    marker = "paint the foreground — cairo_show_text per cell"
    if marker in src:
        return src
    old = """\t/* paint the foreground */
\tglyph_run_init(&run, terminal, cr);
\tfor (row = 0; row < terminal->height; row++) {
\t\tp_row = terminal_get_row(terminal, row);
\t\tfor (col = 0; col < terminal->width; col++) {
\t\t\t/* get the attributes for this character cell */
\t\t\tterminal_decode_attr(terminal, row, col, &attr);

\t\t\tglyph_run_flush(&run, attr);

\t\t\ttext_x = col * average_width;
\t\t\ttext_y = extents.ascent + row * extents.height;
\t\t\tif (attr.attr.a & ATTRMASK_UNDERLINE) {
\t\t\t\tterminal_set_color(terminal, cr, attr.attr.fg);
\t\t\t\tcairo_move_to(cr, text_x, (double)text_y + 1.5);
\t\t\t\tcairo_line_to(cr, text_x + average_width, (double) text_y + 1.5);
\t\t\t\tcairo_stroke(cr);
\t\t\t}

\t\t\t/* skip space glyph (RLE) we use as a placeholder of
\t\t\t   the right half of a double-width character,
\t\t\t   because RLE is not available in every font. */
\t\t\tif (p_row[col].ch == 0x200B)
\t\t\t\tcontinue;

\t\t\tglyph_run_add(&run, text_x, text_y, &p_row[col]);
\t\t}
\t}

\tattr.key = ~0;
\tglyph_run_flush(&run, attr);"""
    new = """#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
\t/* paint the foreground — cairo_show_text per cell; text_to_glyphs unreliable on iOS */
\tfor (row = 0; row < terminal->height; row++) {
\t\tp_row = terminal_get_row(terminal, row);
\t\tfor (col = 0; col < terminal->width; col++) {
\t\t\tint byte_len;
\t\t\tchar scratch[5];
\t\t\tcairo_scaled_font_t *cell_font;

\t\t\tterminal_decode_attr(terminal, row, col, &attr);
\t\t\ttext_x = col * average_width;
\t\t\ttext_y = extents.ascent + row * extents.height;
\t\t\tif (attr.attr.a & ATTRMASK_UNDERLINE) {
\t\t\t\tterminal_set_color(terminal, cr, attr.attr.fg);
\t\t\t\tcairo_move_to(cr, text_x, (double)text_y + 1.5);
\t\t\t\tcairo_line_to(cr, text_x + average_width, (double) text_y + 1.5);
\t\t\t\tcairo_stroke(cr);
\t\t\t}
\t\t\tif (p_row[col].ch == 0x200B)
\t\t\t\tcontinue;
\t\t\tif (attr.attr.a & ATTRMASK_CONCEALED)
\t\t\t\tcontinue;
\t\t\tbyte_len = (int)strnlen((const char *)p_row[col].byte, 4);
\t\t\tif (byte_len <= 0 && p_row[col].ch != 0 && p_row[col].ch < 128) {
\t\t\t\tscratch[0] = (char)p_row[col].ch;
\t\t\t\tscratch[1] = '\\0';
\t\t\t\tbyte_len = 1;
\t\t\t} else {
\t\t\t\tmemcpy(scratch, p_row[col].byte, (size_t)byte_len);
\t\t\t\tscratch[byte_len] = '\\0';
\t\t\t}
\t\t\tif (byte_len <= 0)
\t\t\t\tcontinue;
\t\t\tif (attr.attr.a & (ATTRMASK_BOLD | ATTRMASK_BLINK))
\t\t\t\tcell_font = terminal->font_bold;
\t\t\telse
\t\t\t\tcell_font = terminal->font_normal;
\t\t\tcairo_set_scaled_font(cr, cell_font);
\t\t\tterminal_set_color(terminal, cr, attr.attr.fg);
\t\t\tcairo_move_to(cr, text_x, text_y);
\t\t\tcairo_show_text(cr, scratch);
\t\t}
\t}
#else
\t/* paint the foreground */
\tglyph_run_init(&run, terminal, cr);
\tfor (row = 0; row < terminal->height; row++) {
\t\tp_row = terminal_get_row(terminal, row);
\t\tfor (col = 0; col < terminal->width; col++) {
\t\t\t/* get the attributes for this character cell */
\t\t\tterminal_decode_attr(terminal, row, col, &attr);

\t\t\tglyph_run_flush(&run, attr);

\t\t\ttext_x = col * average_width;
\t\t\ttext_y = extents.ascent + row * extents.height;
\t\t\tif (attr.attr.a & ATTRMASK_UNDERLINE) {
\t\t\t\tterminal_set_color(terminal, cr, attr.attr.fg);
\t\t\t\tcairo_move_to(cr, text_x, (double)text_y + 1.5);
\t\t\t\tcairo_line_to(cr, text_x + average_width, (double) text_y + 1.5);
\t\t\t\tcairo_stroke(cr);
\t\t\t}

\t\t\t/* skip space glyph (RLE) we use as a placeholder of
\t\t\t   the right half of a double-width character,
\t\t\t   because RLE is not available in every font. */
\t\t\tif (p_row[col].ch == 0x200B)
\t\t\t\tcontinue;

\t\t\tglyph_run_add(&run, text_x, text_y, &p_row[col]);
\t\t}
\t}

\tattr.key = ~0;
\tglyph_run_flush(&run, attr);
#endif"""
    if old not in src:
        raise SystemExit("redraw_handler foreground patch anchor missing")
    return src.replace(old, new, 1)


def patch_ios_redraw_visible_fg(src: str) -> str:
    """Force light glyph color; indexed attrs often resolve to black on iOS."""
    if "cairo_set_source_rgb(cr, 0.92, 0.92, 0.92)" in src:
        return src
    old_ios = (
        "\t\t\tcairo_set_scaled_font(cr, cell_font);\n"
        "\t\t\tterminal_set_color(terminal, cr, attr.attr.fg);\n"
        "\t\t\tcairo_move_to(cr, text_x, text_y);\n"
        "\t\t\tcairo_show_text(cr, scratch);"
    )
    new_ios = (
        "\t\t\tcairo_set_scaled_font(cr, cell_font);\n"
        "\t\t\tterminal_set_color(terminal, cr, attr.attr.fg);\n"
        "\t\t\tcairo_set_source_rgb(cr, 0.92, 0.92, 0.92);\n"
        "\t\t\tcairo_move_to(cr, text_x, text_y);\n"
        "\t\t\tcairo_show_text(cr, scratch);"
    )
    if old_ios in src:
        src = src.replace(old_ios, new_ios, 1)
    old = (
        "\t\t\tterminal_set_color(terminal, cr, attr.attr.fg);\n"
        "\t\t\tcairo_move_to(cr, text_x, text_y);\n"
        "\t\t\tcairo_show_text(cr, scratch);"
    )
    new = (
        "\t\t\tterminal_set_color(terminal, cr, attr.attr.fg);\n"
        "\t\t\tcairo_set_source_rgb(cr, 0.92, 0.92, 0.92);\n"
        "\t\t\tcairo_move_to(cr, text_x, text_y);\n"
        "\t\t\tcairo_show_text(cr, scratch);"
    )
    if old in src:
        src = src.replace(old, new, 1)
    if "cairo_set_source_rgb(cr, 0.92, 0.92, 0.92)" not in src:
        raise SystemExit("ios redraw visible fg anchor missing in terminal.c")
    return src


def patch_ios_redraw_background(src: str) -> str:
    """Indexed terminal colors often resolve to black on iOS; force visible chrome."""
    marker = "cairo_set_source_rgb(cr, 0.12, 0.12, 0.14)"
    if marker in src:
        return src
    old = (
        "\tterminal_set_color(terminal, cr, terminal->color_scheme->border);\n"
        "\tcairo_paint(cr);"
    )
    new = (
        "\tterminal_set_color(terminal, cr, terminal->color_scheme->border);\n"
        "#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)\n"
        "\tcairo_set_source_rgb(cr, 0.12, 0.12, 0.14);\n"
        "#endif\n"
        "\tcairo_paint(cr);"
    )
    if old not in src:
        raise SystemExit("ios redraw background anchor missing in terminal.c")
    return src.replace(old, new, 1)


def patch_ios_initial_redraw(src: str) -> str:
    """Paint the first frame as soon as the terminal window exists."""
    marker = "weston-terminal: scheduled initial redraw"
    if marker in src:
        return src
    old = "\treturn terminal;\n}\n\nstatic void\nterminal_destroy"
    new = (
        "#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)\n"
        "\twindow_schedule_redraw(terminal->window);\n"
        '\tWWN_TERM_LOG("weston-terminal: scheduled initial redraw\\n");\n'
        "#endif\n"
        "\treturn terminal;\n"
        "}\n\nstatic void\nterminal_destroy"
    )
    if old not in src:
        raise SystemExit("terminal_create initial redraw anchor missing in terminal.c")
    return src.replace(old, new, 1)


def patch_ios_glyph_fallback(src: str) -> str:
    old = """\tcairo_move_to(run->cr, x, y);
\tcairo_scaled_font_text_to_glyphs (font, x, y,
\t\t\t\t\t  (char *) c->byte, 4,
\t\t\t\t\t  &run->g, &num_glyphs,
\t\t\t\t\t  NULL, NULL, NULL);
\trun->g += num_glyphs;
\trun->count += num_glyphs;
}"""
    new = """\t{
\t\tint byte_len = (int)strnlen((const char *)c->byte, 4);

\t\tcairo_move_to(run->cr, x, y);
\t\tif (byte_len > 0)
\t\t\tcairo_scaled_font_text_to_glyphs(font, x, y,
\t\t\t\t\t\t  (char *)c->byte, byte_len,
\t\t\t\t\t\t  &run->g, &num_glyphs,
\t\t\t\t\t\t  NULL, NULL, NULL);
#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
\t\tif (byte_len > 0 && num_glyphs == 0) {
\t\t\tchar scratch[5];

\t\t\tmemcpy(scratch, c->byte, (size_t)byte_len);
\t\t\tscratch[byte_len] = '\\0';
\t\t\tcairo_set_scaled_font(run->cr, font);
\t\t\tterminal_set_color(run->terminal, run->cr, run->attr.attr.fg);
\t\t\tcairo_show_text(run->cr, scratch);
\t\t} else
#endif
\t\t{
\t\t\trun->g += num_glyphs;
\t\t\trun->count += num_glyphs;
\t\t}
\t}
}"""
    if "cairo_show_text(run->cr, scratch)" in src:
        return src
    if old not in src:
        raise SystemExit("glyph_run_add patch anchor missing")
    return src.replace(old, new, 1)


def patch_ios_resize_redraw(src: str) -> str:
    idx = src.find("static void\nresize_handler")
    if idx != -1:
        chunk_end = src.find("\nstatic void\nstate_changed_handler", idx)
        if chunk_end != -1:
            chunk = src[idx:chunk_end]
            if "window_schedule_redraw(terminal->window)" in chunk:
                return src

    tail = """

static void
state_changed_handler"""
    old_plain = """\tterminal_resize_cells(terminal, columns, rows);
\tupdate_title(terminal);
}""" + tail
    new_plain = """\tterminal_resize_cells(terminal, columns, rows);
\tupdate_title(terminal);
#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
\tWWN_TERM_LOG("weston-terminal: resize_handler %dx%d cols=%d rows=%d (configure received)\\n",
\t\twidth, height, columns, rows);
\twindow_schedule_redraw(terminal->window);
#endif
}""" + tail
    if old_plain in src:
        return src.replace(old_plain, new_plain, 1)

    old_pace = """#endif
\tupdate_title(terminal);
}""" + tail
    new_pace = """#endif
\tupdate_title(terminal);
#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
\tWWN_TERM_LOG("weston-terminal: resize_handler %dx%d cols=%d rows=%d (configure received)\\n",
\t\twidth, height, columns, rows);
\twindow_schedule_redraw(terminal->window);
#endif
}""" + tail
    if old_pace in src:
        return src.replace(old_pace, new_pace, 1)

    raise SystemExit("resize_handler redraw patch anchor missing")


def patch_ios_skip_terminal_create_resize(src: str) -> str:
    old = """\tterminal_resize(terminal, 20, 5); /* Set minimum size first */
\tterminal_resize(terminal, 80, 25);"""
    new = """#if !defined(__APPLE__) || (!TARGET_OS_IPHONE && !TARGET_OS_TV && !TARGET_OS_WATCH)
\tterminal_resize(terminal, 20, 5); /* Set minimum size first */
\tterminal_resize(terminal, 80, 25);
#endif"""
    if "#if !defined(__APPLE__) || (!TARGET_OS_IPHONE && !TARGET_OS_TV && !TARGET_OS_WATCH)\n\tterminal_resize(terminal, 20, 5);" in src:
        return src
    if old not in src:
        raise SystemExit("terminal_create initial resize anchor missing")
    return src.replace(old, new, 1)


def patch_ios_winsize(src: str) -> str:
    old = "\tioctl(terminal->master, TIOCSWINSZ, &ws);"
    new = """#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
\twwn_pty_set_winsize(terminal->master, &ws);
#else
\tioctl(terminal->master, TIOCSWINSZ, &ws);
#endif"""
    if old not in src:
        raise SystemExit("TIOCSWINSZ patch target not found in terminal.c")
    return src.replace(old, new, 1)


def patch_ios_skip_terminal_run_resize(src: str) -> str:
    """Do not send a bogus 80x24 winsize after spawn; wait for configure."""
    if "#if !defined(__APPLE__) || (!TARGET_OS_IPHONE && !TARGET_OS_TV && !TARGET_OS_WATCH)\n\t\tterminal_resize(terminal, 80, 24);" in src:
        return src

    old_pace = """\telse
\t\tterminal_resize(terminal, 80, 24);

#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
\t/*
\t * fork() children wait for resize_handler() to close the pace pipe and
\t * allocate the cell grid. On iOS, unblocking early without a buffer races
\t * shell output against io_handler → handle_char (NULL terminal->data).
\t */
\tterminal_resize_cells(terminal, 80, 24);
\tif (terminal->pace_pipe >= 0) {
\t\tclose(terminal->pace_pipe);
\t\tterminal->pace_pipe = -1;
\t\tWWN_TERM_LOG("weston-terminal: unblocked shell pace pipe (iOS)\\n");
\t}
#endif

\treturn 0;
}"""
    if old_pace in src:
        src = src.replace(
            old_pace,
            """\telse {
#if !defined(__APPLE__) || (!TARGET_OS_IPHONE && !TARGET_OS_TV && !TARGET_OS_WATCH)
\t\tterminal_resize(terminal, 80, 24);
#endif
\t}

\treturn 0;
}""",
            1,
        )
        return src

    old = """\telse
\t\tterminal_resize(terminal, 80, 24);

\treturn 0;
}"""
    new = """\telse {
#if !defined(__APPLE__) || (!TARGET_OS_IPHONE && !TARGET_OS_TV && !TARGET_OS_WATCH)
\t\tterminal_resize(terminal, 80, 24);
#endif
\t}

\treturn 0;
}"""
    if old not in src:
        raise SystemExit("terminal_run resize skip anchor missing in terminal.c")
    return src.replace(old, new, 1)


def patch_ios_resize_pace_order(src: str) -> str:
    """Size grid before unblocking the shell (matches fork+pace intent).

    On iOS we defer shell unblock until the first non-zero configure so the
    cell grid (and winsize) exist before zsh writes its prompt; otherwise early
    output races io_handler against a NULL terminal->data.
    """
    if "terminal->ios_configure_count++" in src:
        old_else = """\t} else {
\t\tif (columns >= 1 && rows >= 1)
\t\t\tterminal_resize_cells(terminal, columns, rows);
\t\twwn_pty_ios_signal_shells();
\t\twindow_schedule_redraw(terminal->window);
\t\tterminal_ios_arm_pty_poll(terminal);
\t}"""
        new_else = """\t} else {
\t\tif (columns >= 1 && rows >= 1)
\t\t\tterminal_resize_cells(terminal, columns, rows);
\t\tterminal_ios_flush_pending_pty(terminal);
\t\tterminal_master_consume(terminal);
\t\twwn_pty_ios_signal_shells();
\t\twindow_schedule_redraw(terminal->window);
\t\tterminal_ios_arm_pty_poll(terminal);
\t}"""
        if old_else in src:
            return src.replace(old_else, new_else, 1)
        return src

    old = """\tif (terminal->pace_pipe >= 0) {
\t\tclose(terminal->pace_pipe);
\t\tterminal->pace_pipe = -1;
\t}
\tm = 2 * terminal->margin;
\tcolumns = (width - m) / (int32_t) terminal->average_width;
\trows = (height - m) / (int32_t) terminal->extents.height;

\tif (!window_is_fullscreen(terminal->window) &&
\t    !window_is_maximized(terminal->window)) {
\t\twidth = columns * terminal->average_width + m;
\t\theight = rows * terminal->extents.height + m;
\t\twidget_set_size(terminal->widget, width, height);
\t}

\tterminal_resize_cells(terminal, columns, rows);"""
    new = """\tm = 2 * terminal->margin;
\tcolumns = (width - m) / (int32_t) terminal->average_width;
\trows = (height - m) / (int32_t) terminal->extents.height;

\tif (!window_is_fullscreen(terminal->window) &&
\t    !window_is_maximized(terminal->window)) {
\t\twidth = columns * terminal->average_width + m;
\t\theight = rows * terminal->extents.height + m;
\t\twidget_set_size(terminal->widget, width, height);
\t}

#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
\tterminal->ios_configure_count++;
\tif (terminal->pace_pipe >= 0 && width > 0 && height > 0) {
\t\tint32_t c = columns, r = rows;

\t\tif (c < 1 && terminal->average_width >= 1.0)
\t\t\tc = (width - m) / (int32_t) terminal->average_width;
\t\tif (r < 1 && terminal->extents.height >= 1.0)
\t\t\tr = (height - m) / (int32_t) terminal->extents.height;
\t\tif (c < 1)
\t\t\tc = width / 8;
\t\tif (r < 1)
\t\t\tr = height / 16;
\t\tterminal_ios_unblock_shell(terminal, c, r);
\t} else {
\t\tif (columns >= 1 && rows >= 1)
\t\t\tterminal_resize_cells(terminal, columns, rows);
\t\tterminal_ios_flush_pending_pty(terminal);
\t\tterminal_master_consume(terminal);
\t\twwn_pty_ios_signal_shells();
\t\twindow_schedule_redraw(terminal->window);
\t\tterminal_ios_arm_pty_poll(terminal);
\t}
#else
\tif (terminal->pace_pipe >= 0) {
\t\tclose(terminal->pace_pipe);
\t\tterminal->pace_pipe = -1;
\t}
\tterminal_resize_cells(terminal, columns, rows);
#endif"""
    if old not in src:
        raise SystemExit("resize_handler pace order anchor missing in terminal.c")
    return src.replace(old, new, 1)


def patch_ios_resize_shell_refresh(src: str) -> str:
    """After shell is running, nudge redraw on subsequent resizes."""
    if "wwn_pty_ios_kick_shell_display();" in src:
        return src.replace("wwn_pty_ios_kick_shell_display();",
                             "wwn_pty_ios_signal_shells();", 1)
    if "terminal_ios_arm_pty_poll(terminal);\n\t} else {\n\t\twwn_pty_ios_signal_shells();" in src:
        return src
    old = """\t\tif (terminal->ios_pty_poll.fd >= 0)
\t\t\ttoytimer_arm_once_usec(&terminal->ios_pty_poll, 500);
\t}
#else
\tif (terminal->pace_pipe >= 0) {
\t\tclose(terminal->pace_pipe);
\t\tterminal->pace_pipe = -1;
\t}
\tterminal_resize_cells(terminal, columns, rows);
#endif"""
    new = """\t\tif (terminal->ios_pty_poll.fd >= 0)
\t\t\ttoytimer_arm_once_usec(&terminal->ios_pty_poll, 500);
\t} else {
\t\twwn_pty_ios_signal_shells();
\t\tif (terminal->ios_pty_poll.fd >= 0)
\t\t\ttoytimer_arm_once_usec(&terminal->ios_pty_poll, 1);
\t}
#else
\tif (terminal->pace_pipe >= 0) {
\t\tclose(terminal->pace_pipe);
\t\tterminal->pace_pipe = -1;
\t}
\tterminal_resize_cells(terminal, columns, rows);
#endif"""
    if old not in src:
        return src
    return src.replace(old, new, 1)


def patch_ios_pty_poll_field(src: str) -> str:
    old = "\tint pace_pipe;\n};"
    new = """\tint pace_pipe;
#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
\tstruct toytimer ios_pty_poll;
\tstruct toytimer ios_pace_fallback;
\tint ios_pty_poll_inited;
\tint ios_configure_count;
\tchar *ios_pty_pending;
\tsize_t ios_pty_pending_len;
\tsize_t ios_pty_pending_cap;
#endif
};"""
    if "ios_configure_count;" in src:
        return src
    if "ios_pty_poll;" in src and "struct toytimer ios_pty_poll" in src:
        if "ios_configure_count;" not in src:
            src = src.replace(
                "\tstruct toytimer ios_pty_poll;\n#endif",
                "\tstruct toytimer ios_pty_poll;\n\tint ios_configure_count;\n#endif",
                1,
            )
        return src
    if "ios_pty_poll_source" in src:
        src = src.replace(
            "\tstruct wl_event_source *ios_pty_poll_source;",
            "\tstruct toytimer ios_pty_poll;",
            1,
        )
        return src
    if old not in src:
        raise SystemExit("terminal struct ios_pty_poll field anchor missing")
    return src.replace(old, new, 1)


def patch_ios_pty_poll(src: str) -> str:
    """Poll PTY master on a timer; epoll on socketpair PTY is unreliable on iOS."""
    if "terminal_ios_pending_append" in src:
        return src

    forward_decls = """
#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
static void terminal_data(struct terminal *terminal, const char *data, size_t length);
static void terminal_ios_pending_append(struct terminal *terminal, const char *buf, size_t len);
static void terminal_ios_flush_pending_pty(struct terminal *terminal);
static void terminal_ios_arm_pty_poll(struct terminal *terminal);
static void terminal_ios_unblock_shell(struct terminal *terminal, int32_t columns, int32_t rows);
static void terminal_ios_pace_fallback_cb(struct toytimer *tt);
static void terminal_master_consume(struct terminal *terminal);
static void terminal_ios_pty_poll_cb(struct toytimer *tt);
#endif

"""
    implementations = """
#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
static int ios_pty_pending_log_budget = 8;

static void
terminal_ios_pending_append(struct terminal *terminal, const char *buf, size_t len)
{
\tsize_t need;
\tchar *next;

\tif (len == 0 || buf == NULL)
\t\treturn;
\tneed = terminal->ios_pty_pending_len + len;
\tif (need > terminal->ios_pty_pending_cap) {
\t\tsize_t cap = terminal->ios_pty_pending_cap ? terminal->ios_pty_pending_cap : 4096;

\t\twhile (cap < need)
\t\t\tcap *= 2;
\t\tnext = realloc(terminal->ios_pty_pending, cap);
\t\tif (!next)
\t\t\treturn;
\t\tterminal->ios_pty_pending = next;
\t\tterminal->ios_pty_pending_cap = cap;
\t}
\tmemcpy(terminal->ios_pty_pending + terminal->ios_pty_pending_len, buf, len);
\tterminal->ios_pty_pending_len += len;
}

static void
terminal_ios_flush_pending_pty(struct terminal *terminal)
{
\tif (!terminal->data || terminal->ios_pty_pending_len == 0)
\t\treturn;
\tterminal_data(terminal, terminal->ios_pty_pending, terminal->ios_pty_pending_len);
\tterminal->ios_pty_pending_len = 0;
\twindow_schedule_redraw(terminal->window);
}

static void
terminal_ios_arm_pty_poll(struct terminal *terminal)
{
\tif (!terminal->ios_pty_poll_inited)
\t\treturn;
\ttoytimer_arm_once_usec(&terminal->ios_pty_poll, 1);
}

static void
terminal_ios_unblock_shell(struct terminal *terminal, int32_t columns, int32_t rows)
{
\tif (terminal->pace_pipe < 0)
\t\treturn;
\tif (columns < 1)
\t\tcolumns = 80;
\tif (rows < 1)
\t\trows = 24;
\tterminal_resize_cells(terminal, columns, rows);
\tterminal_ios_flush_pending_pty(terminal);
\tclose(terminal->pace_pipe);
\tterminal->pace_pipe = -1;
\tWWN_TERM_INFO("weston-terminal: shell pace unblocked (grid %dx%d)\\n",
\t\t      columns, rows);
\twindow_schedule_redraw(terminal->window);
\tterminal_ios_arm_pty_poll(terminal);
}

static void
terminal_ios_pace_fallback_cb(struct toytimer *tt)
{
\tstruct terminal *terminal =
\t\tcontainer_of(tt, struct terminal, ios_pace_fallback);

\tif (terminal->pace_pipe >= 0) {
\t\tif (terminal->ios_configure_count == 0 || !terminal->data) {
\t\t\tWWN_TERM_INFO("weston-terminal: pace fallback (forcing 80x24 grid)\\n");
\t\t\tterminal_ios_unblock_shell(terminal, 80, 24);
\t\t}
\t}
}

static void
terminal_master_consume(struct terminal *terminal)
{
\tchar buffer[4096];
\tssize_t len;

\tfor (;;) {
\t\tlen = read(terminal->master, buffer, sizeof buffer);
\t\tif (len < 0) {
\t\t\tif (errno == EAGAIN || errno == EWOULDBLOCK)
\t\t\t\treturn;
\t\t\treturn;
\t\t}
\t\tif (len == 0)
\t\t\treturn;
\t\tif (!terminal->data) {
\t\t\tterminal_ios_pending_append(terminal, buffer, (size_t)len);
\t\t\tif (ios_pty_pending_log_budget > 0) {
\t\t\t\tios_pty_pending_log_budget--;
\t\t\t\tWWN_TERM_INFO("weston-terminal: buffered %zd PTY bytes (no grid yet)\\n",
\t\t\t\t\t      len);
\t\t\t}
\t\t\tcontinue;
\t\t}
\t\tif (terminal->ios_pty_pending_len > 0)
\t\t\tterminal_ios_flush_pending_pty(terminal);
\t\tif (ios_pty_pending_log_budget > 0) {
\t\t\tios_pty_pending_log_budget--;
\t\t\tWWN_TERM_INFO("weston-terminal: PTY consume %zd bytes\\n", len);
\t\t}
\t\tterminal_data(terminal, buffer, (size_t)len);
\t\twindow_schedule_redraw(terminal->window);
\t}
}

static void
terminal_ios_pty_poll_cb(struct toytimer *tt)
{
\tstruct terminal *terminal = container_of(tt, struct terminal, ios_pty_poll);

\tterminal_master_consume(terminal);
\ttoytimer_arm_once_usec(tt, 2000);
}
#endif

"""
    resize_anchor = "static void\nresize_handler(struct widget *widget,"
    if resize_anchor not in src:
        raise SystemExit("resize_handler anchor missing for ios pty helpers")
    src = src.replace(resize_anchor, forward_decls + resize_anchor, 1)

    io_anchor = "static void\nio_handler(struct task *task, uint32_t events)"
    if io_anchor not in src:
        raise SystemExit("io_handler anchor missing for ios pty poll")
    src = src.replace(io_anchor, implementations + io_anchor, 1)

    old_watch = """\tfcntl(master, F_SETFL, O_NONBLOCK);
\tterminal->io_task.run = io_handler;
\tdisplay_watch_fd(terminal->display, terminal->master,
\t\t\t EPOLLIN | EPOLLHUP, &terminal->io_task);"""
    new_watch = """\tfcntl(master, F_SETFL, O_NONBLOCK);
\tterminal->io_task.run = io_handler;
#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
\tterminal->ios_pty_poll_inited = 1;
\ttoytimer_init(&terminal->ios_pty_poll, CLOCK_MONOTONIC, terminal->display,
\t\t      terminal_ios_pty_poll_cb);
\ttoytimer_arm_once_usec(&terminal->ios_pty_poll, 1);
\ttoytimer_init(&terminal->ios_pace_fallback, CLOCK_MONOTONIC, terminal->display,
\t\t      terminal_ios_pace_fallback_cb);
\ttoytimer_arm_once_usec(&terminal->ios_pace_fallback, 2000000);
#endif
\tdisplay_watch_fd(terminal->display, terminal->master,
\t\t\t EPOLLIN | EPOLLHUP, &terminal->io_task);"""
    if old_watch not in src:
        raise SystemExit("terminal_run display_watch_fd anchor missing")
    src = src.replace(old_watch, new_watch, 1)

    old_destroy_poll = """#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
\tif (terminal->ios_pty_poll_source) {
\t\twl_event_source_remove(terminal->ios_pty_poll_source);
\t\tterminal->ios_pty_poll_source = NULL;
\t}
#else
\tdisplay_unwatch_fd(terminal->display, terminal->master);
#endif
\tclose(terminal->master);"""
    old_destroy_plain = """\tdisplay_unwatch_fd(terminal->display, terminal->master);
\tclose(terminal->master);"""
    new_destroy = """#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
\tif (terminal->ios_pty_poll_inited) {
\t\ttoytimer_fini(&terminal->ios_pty_poll);
\t\ttoytimer_fini(&terminal->ios_pace_fallback);
\t}
\tfree(terminal->ios_pty_pending);
#endif
\tdisplay_unwatch_fd(terminal->display, terminal->master);
\tclose(terminal->master);"""
    if "toytimer_fini(&terminal->ios_pty_poll)" in src:
        return src
    if old_destroy_poll in src:
        return src.replace(old_destroy_poll, new_destroy, 1)
    if old_destroy_plain not in src:
        raise SystemExit("terminal_destroy unwatch anchor missing")
    return src.replace(old_destroy_plain, new_destroy, 1)


def patch_terminal_csd_geometry_helper(src: str) -> str:
    """Publish xdg window geometry for weston-terminal's painted CSD border."""
    if "terminal_publish_csd_geometry" in src:
        return src

    helper = """
static void
terminal_publish_csd_geometry(struct terminal *terminal, int32_t width, int32_t height)
{
	int inset = terminal->margin;

	if (width <= inset * 2 || height <= inset * 2)
		return;

	window_set_content_geometry(terminal->window, inset, inset,
				    width - inset * 2, height - inset * 2);
}

"""
    anchor = "static void\nresize_handler(struct widget *widget,"
    if anchor not in src:
        raise SystemExit("resize_handler anchor missing for CSD geometry helper")
    return src.replace(anchor, helper + anchor, 1)


def patch_terminal_csd_geometry_call(src: str) -> str:
    marker = "terminal_publish_csd_geometry(terminal, width, height);"
    if marker in src:
        return src

    old = """\tupdate_title(terminal);
#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
\twindow_schedule_redraw(terminal->window);
#endif
}

static void
state_changed_handler"""
    new = """\tterminal_publish_csd_geometry(terminal, width, height);
\tupdate_title(terminal);
#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
\twindow_schedule_redraw(terminal->window);
#endif
}

static void
state_changed_handler"""
    if old in src:
        return src.replace(old, new, 1)

    old_plain = """\tupdate_title(terminal);
}

static void
state_changed_handler"""
    new_plain = """\tterminal_publish_csd_geometry(terminal, width, height);
\tupdate_title(terminal);
}

static void
state_changed_handler"""
    if old_plain not in src:
        raise SystemExit("resize_handler CSD geometry call anchor missing")
    return src.replace(old_plain, new_plain, 1)


def patch_ios_terminal_create_fail(src: str) -> str:
    old = (
        "\tterminal = terminal_create(d);\n"
        "\tif (terminal_run(terminal, option_shell))"
    )
    new = (
        "\tterminal = terminal_create(d);\n"
        "\tif (!terminal) {\n"
        "\t\tdisplay_destroy(d);\n"
        "\t\treturn -1;\n"
        "\t}\n"
        "\tif (terminal_run(terminal, option_shell))"
    )
    if old not in src:
        raise SystemExit("terminal_create fail guard anchor missing")
    return src.replace(old, new, 1)


def main() -> None:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <terminal.c>", file=sys.stderr)
        sys.exit(2)
    path = Path(sys.argv[1])
    src = path.read_text()
    src = patch_howmany_and_title(src)
    src = patch_ios_spawn(src)
    src = patch_ios_pty_poll_field(src)
    src = patch_ios_pty_poll(src)
    src = patch_ios_io_handler(src)
    src = patch_ios_io_handler_consume(src)
    src = patch_ios_winsize(src)
    src = patch_ios_resize_redraw(src)
    src = patch_terminal_csd_geometry_helper(src)
    src = patch_ios_resize_pace_order(src)
    src = patch_terminal_csd_geometry_call(src)
    src = patch_ios_resize_shell_refresh(src)
    src = patch_ios_skip_terminal_run_resize(src)
    src = patch_ios_sigpipe(src)
    src = patch_ios_skip_terminal_create_resize(src)
    src = patch_ios_terminal_create_fail(src)
    src = patch_ios_fontconfig_init(src)
    src = patch_ios_font_helper_fn(src)
    src = patch_ios_main_fcinit(src)
    src = patch_ios_font_default(src)
    src = patch_ios_terminal_font_face(src)
    src = patch_ios_font_metrics_log(src)
    src = patch_ios_redraw_show_text(src)
    src = patch_ios_redraw_visible_fg(src)
    src = patch_ios_redraw_background(src)
    src = patch_ios_initial_redraw(src)
    src = patch_ios_glyph_fallback(src)
    src = patch_ios_terminal_master(src)
    src = patch_ios_terminal_destroy_master(src)
    src = patch_ios_terminal_write(src)
    src = patch_ios_max_escape(src)
    src = patch_osc7_and_prompt(src)
    path.write_text(src)
    print(f"Patched {path}")


if __name__ == "__main__":
    main()
