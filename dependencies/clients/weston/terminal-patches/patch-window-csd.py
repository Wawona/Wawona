#!/usr/bin/env python3
"""Patch weston clients/window.c so CSD clients can publish content geometry."""

from __future__ import annotations

import sys
from pathlib import Path


def patch_window_get_geometry(text: str) -> str:
    old = """static void
window_get_geometry(struct window *window, struct rectangle *geometry)
{
	if (window->frame && !window->fullscreen)
		frame_input_rect(window->frame->frame,
				 &geometry->x,
				 &geometry->y,
				 &geometry->width,
				 &geometry->height);
	else
		window_get_allocation(window, geometry);
}"""
    new = """static void
window_get_geometry(struct window *window, struct rectangle *geometry)
{
	if (window->frame && !window->fullscreen)
		frame_input_rect(window->frame->frame,
				 &geometry->x,
				 &geometry->y,
				 &geometry->width,
				 &geometry->height);
	else if (window->fullscreen &&
		 window->last_geometry.width > 0 &&
		 window->last_geometry.height > 0 &&
		 (window->last_geometry.x > 0 ||
		  window->last_geometry.y > 0))
		*geometry = window->last_geometry;
	else
		window_get_allocation(window, geometry);
}"""
    if old not in text:
        raise SystemExit("window_get_geometry anchor missing in window.c")
    return text.replace(old, new, 1)


def patch_window_set_content_geometry(text: str) -> str:
    marker = "window_set_content_geometry(struct window *window"
    if marker in text:
        return text

    anchor = """static void
window_sync_geometry(struct window *window)
{"""
    insert = """void
window_set_content_geometry(struct window *window, int32_t x, int32_t y,
			    int32_t width, int32_t height)
{
	struct rectangle geometry;

	if (!window->xdg_surface || width <= 0 || height <= 0)
		return;

	geometry.x = x;
	geometry.y = y;
	geometry.width = width;
	geometry.height = height;

	if (geometry.x == window->last_geometry.x &&
	    geometry.y == window->last_geometry.y &&
	    geometry.width == window->last_geometry.width &&
	    geometry.height == window->last_geometry.height)
		return;

	xdg_surface_set_window_geometry(window->xdg_surface,
					geometry.x, geometry.y,
					geometry.width, geometry.height);
	window->last_geometry = geometry;
}

"""
    if anchor not in text:
        raise SystemExit("window_sync_geometry anchor missing in window.c")
    return text.replace(anchor, insert + anchor, 1)


def patch_window_h(text: str) -> str:
    marker = "window_set_content_geometry"
    if marker in text:
        return text

    anchor = "void window_frame_set_child_size(struct widget *widget, int child_width,\n\t\t\t    int child_height);"
    if anchor not in text:
        anchor = "void\nwindow_frame_set_child_size(struct widget *widget, int child_width,\n\t\t\t    int child_height);"
    if anchor not in text:
        raise SystemExit("window_frame_set_child_size anchor missing in window.h")

    decl = (
        "\nvoid\n"
        "window_set_content_geometry(struct window *window, int32_t x, int32_t y,\n"
        "\t\t\t    int32_t width, int32_t height);\n"
    )
    return text.replace(anchor, anchor + decl, 1)


def main() -> None:
    if len(sys.argv) not in (2, 3):
        print(f"usage: {sys.argv[0]} <window.c> [window.h]", file=sys.stderr)
        sys.exit(2)

    window_c = Path(sys.argv[1])
    text = window_c.read_text()
    text = patch_window_set_content_geometry(text)
    text = patch_window_get_geometry(text)
    window_c.write_text(text)
    print(f"Patched {window_c}")

    if len(sys.argv) == 3:
        window_h = Path(sys.argv[2])
        window_h.write_text(patch_window_h(window_h.read_text()))
        print(f"Patched {window_h}")


if __name__ == "__main__":
    main()
