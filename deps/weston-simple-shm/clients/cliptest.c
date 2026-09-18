/*
 * Copyright © 2012 Collabora, Ltd.
 * Copyright © 2012 Rob Clark
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice (including the next
 * paragraph) shall be included in all copies or substantial portions of the
 * Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

/* cliptest:
 *	For debugging the rect_to_quad() and clip_quad() functions. An arbitrary
 *	quad (red) is transformed from global coordinate space to surface
 *	coordinate space and clipped to an axis-aligned rect (blue).
 *
 * controls:
 *	surface rect position:  mouse left drag,  keys: w a s d
 *	surface rect size:      mouse right drag, keys: i j k l
 *	quad orientation:       mouse wheel,      keys: n m
 *	quad transform disable:                   key:  r
 */

#include "config.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <libgen.h>
#include <unistd.h>
#include <math.h>
#include <time.h>
#include <pixman.h>
#include <cairo.h>
#include <float.h>
#include <assert.h>
#include <errno.h>

#include <linux/input.h>
#include <wayland-client.h>

#include "libweston/matrix.h"
#include "libweston/vertex-clipping.h"
#include "shared/helpers.h"
#include "shared/xalloc.h"
#include "window.h"

typedef float GLfloat;

struct geometry {
	pixman_box32_t surf;

	pixman_box32_t quad;
	float s; /* sin phi */
	float c; /* cos phi */
	float phi;
};

struct weston_surface {
};

struct weston_view {
	struct weston_surface *surface;
	struct {
		int enabled;
		struct weston_matrix matrix;
	} transform;

	struct geometry *geometry;
};

static void
weston_view_from_global_float(struct weston_view *view,
			      float x, float y, float *sx, float *sy)
{
	struct geometry *g = view->geometry;

	/* pure rotation around origin by sine and cosine */
	*sx = g->c * x + g->s * y;
	*sy = -g->s * x + g->c * y;
}

static struct weston_coord_surface
weston_coord_global_to_surface(struct weston_view *view, struct weston_coord_global g_pos)
{
	float sx, sy;
	struct weston_coord_surface pos;

	weston_view_from_global_float(view, g_pos.c.x, g_pos.c.y, &sx, &sy);
	pos.c = weston_coord(sx, sy);

	return pos;
}

/* ---------------------- copied begins -----------------------*/
/* Keep this in sync with what is in gl-renderer.c! */

static void
rect_to_quad(pixman_box32_t *rect, struct weston_view *ev,
	     struct gl_quad *quad)
{
	struct weston_coord_global rect_g[4] = {
		{ .c = weston_coord(rect->x1, rect->y1) },
		{ .c = weston_coord(rect->x2, rect->y1) },
		{ .c = weston_coord(rect->x2, rect->y2) },
		{ .c = weston_coord(rect->x1, rect->y2) },
	};
	struct weston_coord rect_s;
	int i;

	/* Transform rect to surface space. */
	quad->vertices.n = 4;
	for (i = 0; i < quad->vertices.n; i++) {
		rect_s = weston_coord_global_to_surface(ev, rect_g[i]).c;
		quad->vertices.pos[i].x = (float)rect_s.x;
		quad->vertices.pos[i].y = (float)rect_s.y;
	}

	quad->axis_aligned = !ev->transform.enabled ||
		(ev->transform.matrix.type < WESTON_MATRIX_TRANSFORM_ROTATE);

	/* Find axis-aligned bounding box. */
	if (!quad->axis_aligned) {
		quad->bbox.x1 = quad->bbox.x2 = quad->vertices.pos[0].x;
		quad->bbox.y1 = quad->bbox.y2 = quad->vertices.pos[0].y;
		for (i = 1; i < quad->vertices.n; i++) {
			quad->bbox.x1 = MIN(quad->bbox.x1,
					    quad->vertices.pos[i].x);
			quad->bbox.x2 = MAX(quad->bbox.x2,
					    quad->vertices.pos[i].x);
			quad->bbox.y1 = MIN(quad->bbox.y1,
					    quad->vertices.pos[i].y);
			quad->bbox.y2 = MAX(quad->bbox.y2,
					    quad->vertices.pos[i].y);
		}
	}
}

/* ---------------------- copied ends -----------------------*/

static void
geometry_set_phi(struct geometry *g, float phi)
{
	g->phi = phi;
	g->s = sin(phi);
	g->c = cos(phi);
}

static void
geometry_init(struct geometry *g)
{
	g->surf.x1 = -50;
	g->surf.y1 = -50;
	g->surf.x2 = -10;
	g->surf.y2 = -10;

	g->quad.x1 = -20;
	g->quad.y1 = -20;
	g->quad.x2 = 20;
	g->quad.y2 = 20;

	geometry_set_phi(g, 0.0);
}

struct ui_state {
	uint32_t button;
	int down;

	int down_pos[2];
	struct geometry geometry;
};

struct cliptest {
	struct window *window;
	struct widget *widget;
	struct display *display;
	int fullscreen;

	struct ui_state ui;

	struct geometry geometry;
	struct weston_surface surface;
	struct weston_view view;
};

static void
draw_polygon_closed(cairo_t *cr, struct clip_vertex *pos, int n)
{
	int i;

	cairo_move_to(cr, pos[0].x, pos[0].y);
	for (i = 1; i < n; i++)
		cairo_line_to(cr, pos[i].x, pos[i].y);
	cairo_line_to(cr, pos[0].x, pos[0].y);
}

static void
draw_polygon_labels(cairo_t *cr, struct clip_vertex *pos, int n)
{
	char str[16];
	int i;

	for (i = 0; i < n; i++) {
		snprintf(str, 16, "%d", i);
		cairo_move_to(cr, pos[i].x, pos[i].y);
		cairo_show_text(cr, str);
	}
}

static void
draw_coordinates(cairo_t *cr, double ox, double oy, struct clip_vertex *pos, int n)
{
	char str[64];
	int i;
	cairo_font_extents_t ext;

	cairo_font_extents(cr, &ext);
	for (i = 0; i < n; i++) {
		snprintf(str, 64, "%d: %14.9f, %14.9f", i, pos[i].x, pos[i].y);
		cairo_move_to(cr, ox, oy + ext.height * (i + 1));
		cairo_show_text(cr, str);
	}
}

static void
draw_box(cairo_t *cr, pixman_box32_t *box, struct weston_view *view)
{
	struct clip_vertex pos[4];

	if (view) {
		weston_view_from_global_float(view, box->x1, box->y1, &pos[0].x, &pos[0].y);
		weston_view_from_global_float(view, box->x2, box->y1, &pos[1].x, &pos[1].y);
		weston_view_from_global_float(view, box->x2, box->y2, &pos[2].x, &pos[2].y);
		weston_view_from_global_float(view, box->x1, box->y2, &pos[3].x, &pos[3].y);
	} else {
		pos[0].x = box->x1; pos[0].y = box->y1;
		pos[1].x = box->x2; pos[1].y = box->y1;
		pos[2].x = box->x2; pos[2].y = box->y2;
		pos[3].x = box->x1; pos[3].y = box->y2;
	}

	draw_polygon_closed(cr, pos, 4);
}

static void
draw_geometry(cairo_t *cr, struct weston_view *view,
	      struct clip_vertex *v, int n)
{
	struct geometry *g = view->geometry;
	float cx, cy;

	draw_box(cr, &g->quad, view);
	cairo_set_source_rgba(cr, 1.0, 0.0, 0.0, 0.4);
	cairo_fill(cr);
	weston_view_from_global_float(view, g->quad.x1 - 4, g->quad.y1 - 4, &cx, &cy);
	cairo_arc(cr, cx, cy, 1.5, 0.0, 2.0 * M_PI);
	if (view->transform.enabled == 0)
		cairo_set_source_rgba(cr, 1.0, 0.0, 0.0, 0.8);
	cairo_fill(cr);

	draw_box(cr, &g->surf, NULL);
	cairo_set_source_rgba(cr, 0.0, 0.0, 1.0, 0.4);
	cairo_fill(cr);

	if (n) {
		draw_polygon_closed(cr, v, n);
		cairo_set_source_rgb(cr, 0.0, 1.0, 0.0);
		cairo_stroke(cr);

		cairo_set_source_rgba(cr, 0.0, 1.0, 0.0, 0.5);
		draw_polygon_labels(cr, v, n);
	}
}

static void
redraw_handler(struct widget *widget, void *data)
{
	struct cliptest *cliptest = data;
	struct geometry *g = cliptest->view.geometry;
	struct rectangle allocation;
	cairo_t *cr;
	cairo_surface_t *surface;
	struct gl_quad quad;
	struct clip_vertex v[8];
	int n;

	rect_to_quad(&g->quad, &cliptest->view, &quad);
	n = clip_quad(&quad, &g->surf, v);

	widget_get_allocation(cliptest->widget, &allocation);

	surface = window_get_surface(cliptest->window);
	cr = cairo_create(surface);
	widget_get_allocation(cliptest->widget, &allocation);
	cairo_rectangle(cr, allocation.x, allocation.y,
			allocation.width, allocation.height);
	cairo_clip(cr);

	cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
	cairo_set_source_rgba(cr, 0, 0, 0, 1);
	cairo_paint(cr);

	cairo_translate(cr, allocation.x, allocation.y);
	cairo_set_line_width(cr, 1.0);
	cairo_move_to(cr, allocation.width / 2.0, 0.0);
	cairo_line_to(cr, allocation.width / 2.0, allocation.height);
	cairo_move_to(cr, 0.0, allocation.height / 2.0);
	cairo_line_to(cr, allocation.width, allocation.height / 2.0);
	cairo_set_source_rgba(cr, 0.5, 0.5, 0.5, 1.0);
	cairo_stroke(cr);

	cairo_set_operator(cr, CAIRO_OPERATOR_OVER);
	cairo_push_group(cr);
		cairo_translate(cr, allocation.width / 2.0,
				allocation.height / 2.0);
		cairo_scale(cr, 4.0, 4.0);
		cairo_set_line_width(cr, 0.5);
		cairo_set_line_join(cr, CAIRO_LINE_JOIN_BEVEL);
		cairo_select_font_face(cr, "sans-serif", CAIRO_FONT_SLANT_NORMAL,
				       CAIRO_FONT_WEIGHT_BOLD);
		cairo_set_font_size(cr, 5.0);
		draw_geometry(cr, &cliptest->view, v, n);
	cairo_pop_group_to_source(cr);
	cairo_paint(cr);

	cairo_set_source_rgba(cr, 0.0, 1.0, 0.0, 1.0);
	cairo_select_font_face(cr, "monospace", CAIRO_FONT_SLANT_NORMAL,
			       CAIRO_FONT_WEIGHT_NORMAL);
	cairo_set_font_size(cr, 12.0);
	draw_coordinates(cr, 10.0, 10.0, v, n);

	cairo_destroy(cr);

	cairo_surface_destroy(surface);
}

static int
motion_handler(struct widget *widget, struct input *input,
	       uint32_t time, float x, float y, void *data)
{
	struct cliptest *cliptest = data;
	struct ui_state *ui = &cliptest->ui;
	struct geometry *ref = &ui->geometry;
	struct geometry *geom = &cliptest->geometry;
	float dx, dy;

	if (!ui->down)
		return CURSOR_LEFT_PTR;

	dx = (x - ui->down_pos[0]) * 0.25;
	dy = (y - ui->down_pos[1]) * 0.25;

	switch (ui->button) {
	case BTN_LEFT:
		geom->surf.x1 = ref->surf.x1 + dx;
		geom->surf.y1 = ref->surf.y1 + dy;
		/* fall through */
	case BTN_RIGHT:
		geom->surf.x2 = ref->surf.x2 + dx;
		geom->surf.y2 = ref->surf.y2 + dy;
		break;
	default:
		return CURSOR_LEFT_PTR;
	}

	widget_schedule_redraw(cliptest->widget);
	return CURSOR_BLANK;
}

static void
button_handler(struct widget *widget, struct input *input,
	       uint32_t time, uint32_t button,
	       enum wl_pointer_button_state state, void *data)
{
	struct cliptest *cliptest = data;
	struct ui_state *ui = &cliptest->ui;

	ui->button = button;

	if (state == WL_POINTER_BUTTON_STATE_PRESSED) {
		ui->down = 1;
		input_get_position(input, &ui->down_pos[0], &ui->down_pos[1]);
	} else {
		ui->down = 0;
		ui->geometry = cliptest->geometry;
	}
}

static void
axis_handler(struct widget *widget, struct input *input, uint32_t time,
	     uint32_t axis, wl_fixed_t value, void *data)
{
	struct cliptest *cliptest = data;
	struct geometry *geom = &cliptest->geometry;

	if (axis != WL_POINTER_AXIS_VERTICAL_SCROLL)
		return;

	geometry_set_phi(geom, geom->phi +
				(M_PI / 12.0) * wl_fixed_to_double(value));
	cliptest->view.transform.enabled = 1;
	cliptest->view.transform.matrix.type = WESTON_MATRIX_TRANSFORM_ROTATE;

	widget_schedule_redraw(cliptest->widget);
}

static void
key_handler(struct window *window, struct input *input, uint32_t time,
	    uint32_t key, uint32_t sym,
	    enum wl_keyboard_key_state state, void *data)
{
	struct cliptest *cliptest = data;
	struct geometry *g = &cliptest->geometry;

	if (state == WL_KEYBOARD_KEY_STATE_RELEASED)
		return;

	switch (sym) {
	case XKB_KEY_Escape:
		display_exit(cliptest->display);
		return;
	case XKB_KEY_w:
		g->surf.y1 -= 1;
		g->surf.y2 -= 1;
		break;
	case XKB_KEY_a:
		g->surf.x1 -= 1;
		g->surf.x2 -= 1;
		break;
	case XKB_KEY_s:
		g->surf.y1 += 1;
		g->surf.y2 += 1;
		break;
	case XKB_KEY_d:
		g->surf.x1 += 1;
		g->surf.x2 += 1;
		break;
	case XKB_KEY_i:
		g->surf.y2 -= 1;
		break;
	case XKB_KEY_j:
		g->surf.x2 -= 1;
		break;
	case XKB_KEY_k:
		g->surf.y2 += 1;
		break;
	case XKB_KEY_l:
		g->surf.x2 += 1;
		break;
	case XKB_KEY_n:
		geometry_set_phi(g, g->phi + (M_PI / 24.0));
		cliptest->view.transform.enabled = 1;
		cliptest->view.transform.matrix.type =
			WESTON_MATRIX_TRANSFORM_ROTATE;
		break;
	case XKB_KEY_m:
		geometry_set_phi(g, g->phi - (M_PI / 24.0));
		cliptest->view.transform.enabled = 1;
		cliptest->view.transform.matrix.type =
			WESTON_MATRIX_TRANSFORM_ROTATE;
		break;
	case XKB_KEY_r:
		geometry_set_phi(g, 0.0);
		cliptest->view.transform.enabled = 0;
		cliptest->view.transform.matrix.type = 0;
		break;
	default:
		return;
	}

	widget_schedule_redraw(cliptest->widget);
}

static void
keyboard_focus_handler(struct window *window,
		       struct input *device, void *data)
{
	struct cliptest *cliptest = data;

	window_schedule_redraw(cliptest->window);
}

static void
fullscreen_handler(struct window *window, void *data)
{
	struct cliptest *cliptest = data;

	cliptest->fullscreen ^= 1;
	window_set_fullscreen(window, cliptest->fullscreen);
}

static struct cliptest *
cliptest_create(struct display *display)
{
	struct cliptest *cliptest;

	cliptest = xzalloc(sizeof *cliptest);
	cliptest->view.surface = &cliptest->surface;
	cliptest->view.geometry = &cliptest->geometry;
	cliptest->view.transform.enabled = 0;
	cliptest->view.transform.matrix.type = 0;
	geometry_init(&cliptest->geometry);
	geometry_init(&cliptest->ui.geometry);

	cliptest->window = window_create(display);
	cliptest->widget = window_frame_create(cliptest->window, cliptest);
	window_set_title(cliptest->window, "cliptest");
	window_set_appid(cliptest->window, "org.freedesktop.weston.cliptest");
	cliptest->display = display;

	window_set_user_data(cliptest->window, cliptest);
	widget_set_redraw_handler(cliptest->widget, redraw_handler);
	widget_set_button_handler(cliptest->widget, button_handler);
	widget_set_motion_handler(cliptest->widget, motion_handler);
	widget_set_axis_handler(cliptest->widget, axis_handler);

	window_set_keyboard_focus_handler(cliptest->window,
					  keyboard_focus_handler);
	window_set_key_handler(cliptest->window, key_handler);
	window_set_fullscreen_handler(cliptest->window, fullscreen_handler);

	/* set minimum size */
	widget_schedule_resize(cliptest->widget, 200, 100);

	/* set current size */
	widget_schedule_resize(cliptest->widget, 500, 400);

	return cliptest;
}

static struct timespec begin_time;

static void
reset_timer(void)
{
	clock_gettime(CLOCK_MONOTONIC, &begin_time);
}

static double
read_timer(void)
{
	struct timespec t;

	clock_gettime(CLOCK_MONOTONIC, &t);
	return (double)(t.tv_sec - begin_time.tv_sec) +
	       1e-9 * (t.tv_nsec - begin_time.tv_nsec);
}

static int
benchmark(void)
{
	struct weston_surface surface;
	struct weston_view view;
	struct geometry geom;
	struct gl_quad quad;
	struct clip_vertex v[8];
	int i;
	double t;
	const int N = 1000000;

	geom.surf.x1 = -19;
	geom.surf.y1 = -19;
	geom.surf.x2 = 19;
	geom.surf.y2 = 19;

	geom.quad.x1 = -20;
	geom.quad.y1 = -20;
	geom.quad.x2 = 20;
	geom.quad.y2 = 20;

	geometry_set_phi(&geom, 0.0);

	view.surface = &surface;
	view.transform.enabled = 1;
	view.transform.matrix.type = WESTON_MATRIX_TRANSFORM_ROTATE;
	view.geometry = &geom;

	reset_timer();
	for (i = 0; i < N; i++) {
		geometry_set_phi(&geom, (float)i / 360.0f);
		rect_to_quad(&geom.quad, &view, &quad);
		clip_quad(&quad, &geom.surf, v);
	}
	t = read_timer();

	printf("%d calls took %g s, average %g us/call\n", N, t, t / N * 1e6);

	return 0;
}

static void
cliptest_destroy(struct cliptest *cliptest)
{
	widget_destroy(cliptest->widget);
	window_destroy(cliptest->window);
	free(cliptest);
}

int
main(int argc, char *argv[])
{
	struct display *d;
	struct cliptest *cliptest;

	if (argc > 1) {
		if (argc == 2 && !strcmp(argv[1], "-b"))
			return benchmark();
		printf("Usage: %s [OPTIONS]\n  -b  run benchmark\n", argv[0]);
		return 1;
	}

	d = display_create(&argc, argv);
	if (d == NULL) {
		fprintf(stderr, "failed to create display: %s\n",
			strerror(errno));
		return -1;
	}

	cliptest = cliptest_create(d);
	display_run(d);

	cliptest_destroy(cliptest);
	display_destroy(d);

	return 0;
}
