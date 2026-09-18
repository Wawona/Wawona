/*
 * Copyright © 2023 Sergio Gómez for Collabora Ltd
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

#include "config.h"

#include <stdio.h>
#include <stdbool.h>
#include <getopt.h>
#include <sys/mman.h>
#include <linux/input.h>
#include <wayland-cursor.h>

#include "shared/helpers.h"
#include "shared/xalloc.h"
#include "shared/os-compatibility.h"
#include "shared/cairo-util.h"

#include "xdg-shell-client-protocol.h"
#include "pointer-constraints-unstable-v1-client-protocol.h"
#include "relative-pointer-unstable-v1-client-protocol.h"

#define NUM_BUFFERS 3

#define SURFACE_WIDTH 500
#define SURFACE_HEIGHT 400
#define SUBSURFACE_WIDTH (SURFACE_WIDTH / 4)
#define SUBSURFACE_HEIGHT (SURFACE_HEIGHT / 4)
#define SUBSURFACE_X_POS ((SURFACE_WIDTH-SUBSURFACE_WIDTH) / 2)
#define SUBSURFACE_Y_POS ((SURFACE_HEIGHT-SUBSURFACE_HEIGHT) / 2)

static float rgb_surface[3] = { 1, 1, 1 };
static float rgb_subsurface[3] = { 0.5, 0.5, 0.5 };

struct buffer {
	struct wl_buffer *wl_buffer;
	bool used;
	void *data;
	cairo_surface_t *cairo_surface;
};

struct shm_pool {
	struct wl_shm_pool *wl_shm_pool;
	size_t size;
	void *data;
	struct buffer buffers[NUM_BUFFERS];
};

struct surface {
	struct constraints *constraints;

	struct wl_surface *wl_surface;
	struct wl_callback *cb;
	struct wl_subsurface *wl_subsurface;

	struct wl_surface *wl_surface_cursor;
	uint32_t serial;

	int width, height, stride;
	float rgb[3];

	struct {
		int32_t x1, y1;
		int32_t x2, y2;
	} line;

	struct shm_pool pool;
	struct buffer *current_buffer;

	bool needs_reset;
	bool needs_redraw;
};

struct window {
	struct wl_display *wl_display;
	struct wl_registry *wl_registry;
	struct wl_compositor *wl_compositor;
	struct wl_subcompositor *wl_subcompositor;
	struct wl_seat *wl_seat;
	struct wl_pointer *wl_pointer;
	struct wl_keyboard *wl_keyboard;
	struct wl_shm *wl_shm;
	struct wl_cursor_theme *wl_cursor_theme;
	struct wl_cursor *wl_cursor;

	struct xdg_wm_base *xdg_wm_base;
	struct xdg_surface *xdg_surface;
	struct xdg_toplevel *xdg_toplevel;

	struct surface surface;
	struct surface subsurface;
	struct surface *surface_constrained;

};

enum constraints_state {
	STATE_UNCONSTRAINED,
	STATE_CONFINED,
	STATE_LOCKED
};

struct constraints {
	struct window window;

	struct zwp_relative_pointer_manager_v1 *zwp_relative_pointer_manager;
	struct zwp_pointer_constraints_v1 *zwp_pointer_constraints;
	struct zwp_confined_pointer_v1 *zwp_confined_pointer;
	struct zwp_relative_pointer_v1 *zwp_relative_pointer;
	struct zwp_locked_pointer_v1 *zwp_locked_pointer;

	bool running;

	bool argb8888_supported;

	enum constraints_state state;
};

/*
 * Forward declarations for functions used by Wayland event handlers (since
 * these events are defined first).
 */
static void surface_redraw(struct surface *surface);
static void surface_set_cursor(const struct surface *surface, bool hide);
static void constraints_reset_state(struct constraints *constraints);
void (*constraints_transition_state[])(struct constraints *constraints);


static void
relative_pointer_handle_motion(void *data, struct zwp_relative_pointer_v1 *pointer,
			       uint32_t utime_hi, uint32_t utime_lo,
			       wl_fixed_t dx, wl_fixed_t dy,
			       wl_fixed_t dx_unaccel, wl_fixed_t dy_unaccel)
{
	struct constraints *c = data;
	struct surface *sc = c->window.surface_constrained;

	sc->line.x2 = sc->line.x1 + wl_fixed_to_double(dx);
	sc->line.y2 = sc->line.y1 + wl_fixed_to_double(dy);

	c->window.surface_constrained->needs_reset = true;
	c->window.surface_constrained->needs_redraw = true;
}

static const struct zwp_relative_pointer_v1_listener relative_pointer_listener = {
	relative_pointer_handle_motion,
};

static void
pointer_locked(void *data, struct zwp_locked_pointer_v1 *locked_pointer)
{
	struct constraints *c = data;
	struct surface *sc = c->window.surface_constrained;

	c->state = STATE_LOCKED;
	c->zwp_locked_pointer = locked_pointer;

	sc->line.x1 = sc->line.x2;
	sc->line.y1 = sc->line.y2;
	sc->needs_reset = true;
	sc->needs_redraw = true;

	surface_set_cursor(sc, true);

	c->zwp_relative_pointer =
		zwp_relative_pointer_manager_v1_get_relative_pointer(
				c->zwp_relative_pointer_manager,
				c->window.wl_pointer);
	zwp_relative_pointer_v1_add_listener(c->zwp_relative_pointer,
					     &relative_pointer_listener, c);
}

static void
pointer_unlocked(void *data, struct zwp_locked_pointer_v1 *locked_pointer)
{
	struct constraints *c = data;

	constraints_reset_state(c);
}

static const struct zwp_locked_pointer_v1_listener locked_pointer_listener = {
	pointer_locked,
	pointer_unlocked,
};

static void
pointer_confined(void *data, struct zwp_confined_pointer_v1 *confined_pointer)
{
	struct constraints *c = data;

	c->state = STATE_CONFINED;
	c->zwp_confined_pointer = confined_pointer;
}

static void
pointer_unconfined(void *data, struct zwp_confined_pointer_v1 *confined_pointer)
{
	struct constraints *c = data;

	constraints_reset_state(c);
}

static const struct zwp_confined_pointer_v1_listener confined_pointer_listener = {
	pointer_confined,
	pointer_unconfined,
};

static void
pointer_handle_enter(void *data, struct wl_pointer *pointer, uint32_t serial,
		     struct wl_surface *surface, wl_fixed_t sx_w, wl_fixed_t sy_w)
{
	struct constraints *c = data;
	struct surface *surface_constrained =
		(surface == c->window.surface.wl_surface) ?
		&c->window.surface :
		&c->window.subsurface;

	surface_constrained->serial = serial;

	surface_set_cursor(surface_constrained, false);

	c->window.surface_constrained = surface_constrained;
}

static void
pointer_handle_leave(void *data, struct wl_pointer *pointer, uint32_t serial,
		     struct wl_surface *wl_surface)
{
	struct constraints *c = data;
	struct surface *sc = c->window.surface_constrained;

	sc->line.x1 = -1;
	sc->line.y1 = -1;
	sc->line.x2 = -1;
	sc->line.y2 = -1;
	sc->needs_reset = true;
	sc->needs_redraw = true;

	if (c->state != STATE_UNCONSTRAINED)
		constraints_reset_state(c);
}

static void
pointer_handle_motion(void *data, struct wl_pointer *pointer, uint32_t time,
		      wl_fixed_t sx_w, wl_fixed_t sy_w)
{
	struct surface *sc = ((struct constraints *)data)->window.surface_constrained;

	sc->line.x2 = wl_fixed_to_double(sx_w);
	sc->line.y2 = wl_fixed_to_double(sy_w);

	sc->needs_redraw = true;
}

static void
pointer_handle_button(void *data, struct wl_pointer *pointer, uint32_t serial,
		      uint32_t time, uint32_t btn, uint32_t button_state)
{
	struct constraints *c = data;

	if (button_state == WL_POINTER_BUTTON_STATE_RELEASED || btn != BTN_LEFT)
		return;

	constraints_transition_state[c->state](c);
}

static void
pointer_handle_axis(void *data, struct wl_pointer *pointer, uint32_t time,
		    uint32_t axis, wl_fixed_t value)
{
}

static void
pointer_handle_frame(void *data, struct wl_pointer *pointer)
{
}

static void
pointer_handle_axis_source(void *data, struct wl_pointer *pointer,
			   uint32_t source)
{
}

static void
pointer_handle_axis_stop(void *data, struct wl_pointer *pointer, uint32_t time,
			 uint32_t axis)
{
}

static void
pointer_handle_axis_discrete(void *data, struct wl_pointer *pointer,
			     uint32_t axis, int32_t discrete)
{
}

static const struct wl_pointer_listener pointer_listener = {
	pointer_handle_enter,
	pointer_handle_leave,
	pointer_handle_motion,
	pointer_handle_button,
	pointer_handle_axis,
	pointer_handle_frame,
	pointer_handle_axis_source,
	pointer_handle_axis_stop,
	pointer_handle_axis_discrete,
};

static void
keyboard_handle_keymap(void *data, struct wl_keyboard *keyboard, uint32_t format,
		       int fd, uint32_t size)
{
	close(fd);
}

static void
keyboard_handle_enter(void *data, struct wl_keyboard *keyboard, uint32_t serial,
		      struct wl_surface *surface, struct wl_array *keys)
{
}

static void
keyboard_handle_leave(void *data, struct wl_keyboard *keyboard, uint32_t serial,
		      struct wl_surface *surface)
{
}

static void
keyboard_handle_key(void *data, struct wl_keyboard *keyboard, uint32_t serial,
		    uint32_t time, uint32_t key, uint32_t state)
{
	struct constraints *c = data;

	if (key == KEY_ESC && state)
		c->running = false;
}

static void
keyboard_handle_modifiers(void *data, struct wl_keyboard *keyboard,
			  uint32_t serial, uint32_t mods_depressed,
			  uint32_t mods_latched, uint32_t mods_locked,
			  uint32_t group)
{
}

static const struct wl_keyboard_listener keyboard_listener = {
	keyboard_handle_keymap,
	keyboard_handle_enter,
	keyboard_handle_leave,
	keyboard_handle_key,
	keyboard_handle_modifiers,
};

static void
seat_handle_capabilities(void *data, struct wl_seat *wl_seat,
			 enum wl_seat_capability caps)
{
	struct constraints *c = data;

	if ((caps & WL_SEAT_CAPABILITY_POINTER) && !c->window.wl_pointer) {
		c->window.wl_pointer = wl_seat_get_pointer(wl_seat);
		wl_pointer_add_listener(c->window.wl_pointer, &pointer_listener, c);
	}
	if ((caps & WL_SEAT_CAPABILITY_KEYBOARD) && !c->window.wl_keyboard) {
		c->window.wl_keyboard = wl_seat_get_keyboard(wl_seat);
		wl_keyboard_add_listener(c->window.wl_keyboard, &keyboard_listener, c);
	}
}

static const struct wl_seat_listener seat_listener = {
	seat_handle_capabilities,
};

static void
handle_xdg_surface_configure(void *data, struct xdg_surface *surface,
			     uint32_t serial)
{
	struct constraints *c = data;

	xdg_surface_ack_configure(surface, serial);

	surface_redraw(&c->window.surface);
	surface_redraw(&c->window.subsurface);

}

static const struct xdg_surface_listener xdg_surface_listener = {
	handle_xdg_surface_configure,
};

static void
xdg_wm_base_ping(void *data, struct xdg_wm_base *shell, uint32_t serial)
{
	xdg_wm_base_pong(shell, serial);
}

static const struct xdg_wm_base_listener wm_base_listener = {
	xdg_wm_base_ping,
};

static void
shm_format(void *data, struct wl_shm *wl_shm, uint32_t format)
{
	struct constraints *c = data;

	if (format == WL_SHM_FORMAT_ARGB8888)
		c->argb8888_supported = true;
}

struct wl_shm_listener shm_listener = {
	shm_format
};

static void
handle_global(void *data, struct wl_registry *registry, uint32_t name,
	      const char *interface, uint32_t version)
{
	struct constraints *c = data;

	if (strcmp(interface, "wl_compositor") == 0) {
		c->window.wl_compositor =
			wl_registry_bind(registry, name,
					 &wl_compositor_interface, 1);
	} else if (strcmp(interface, "xdg_wm_base") == 0) {
		c->window.xdg_wm_base =
			wl_registry_bind(registry, name,
					 &xdg_wm_base_interface, 1);
		xdg_wm_base_add_listener(c->window.xdg_wm_base,
					 &wm_base_listener, c);
	} else if (strcmp(interface, "wl_shm") == 0) {
		c->window.wl_shm = wl_registry_bind(registry, name,
					      &wl_shm_interface, 1);
		wl_shm_add_listener(c->window.wl_shm, &shm_listener, c);
		c->window.wl_cursor_theme = wl_cursor_theme_load(NULL, 32, c->window.wl_shm);
		c->window.wl_cursor =
			wl_cursor_theme_get_cursor(c->window.wl_cursor_theme, "left_ptr");
	} else if (strcmp(interface, "wl_seat") == 0) {
		c->window.wl_seat = wl_registry_bind(c->window.wl_registry, name,
						       &wl_seat_interface, 1);
		wl_seat_add_listener(c->window.wl_seat, &seat_listener,
				     c);
	} else if (strcmp(interface, "zwp_relative_pointer_manager_v1") == 0) {
		c->zwp_relative_pointer_manager =
			wl_registry_bind(registry, name,
					 &zwp_relative_pointer_manager_v1_interface,
					 1);
	} else if (strcmp(interface, "zwp_pointer_constraints_v1") == 0)  {
		c->zwp_pointer_constraints =
			wl_registry_bind(registry, name,
					 &zwp_pointer_constraints_v1_interface,
					 1);
	} else if (strcmp(interface, wl_subcompositor_interface.name) == 0) {
		c->window.wl_subcompositor =
			wl_registry_bind(registry, name,
					 &wl_subcompositor_interface, 1);
	}
}

static void
handle_global_remove(void *data, struct wl_registry *registry, uint32_t name)
{
}

static const struct wl_registry_listener registry_listener = {
	handle_global,
	handle_global_remove
};

static void
handle_toplevel_configure(void *data, struct xdg_toplevel *xdg_toplevel,
			      int32_t width, int32_t height,
			      struct wl_array *state)
{
}

static void
handle_toplevel_close(void *data, struct xdg_toplevel *xdg_toplevel)
{
	struct constraints *c = data;
	c->running = false;
}

static const struct xdg_toplevel_listener xdg_toplevel_listener = {
	handle_toplevel_configure,
	handle_toplevel_close,
};

static void
buffer_release(void *data, struct wl_buffer *wl_buffer)
{
	struct buffer *buffer = data;

	buffer->used = false;
}

static const struct wl_buffer_listener buffer_listener = {
	buffer_release
};

static void
frame_done(void *data, struct wl_callback *cb, uint32_t time)
{
	struct surface *surface = data;

	wl_callback_destroy(cb);

	surface_redraw(surface);
}

static const struct wl_callback_listener frame_listener = {
	.done = frame_done,
};

static struct buffer *
shm_pool_get_buffer(struct shm_pool *pool, const struct surface *surface)
{
	size_t i, offset;
	struct buffer *buffer = surface->current_buffer;
	cairo_surface_t *prev_surface = buffer ? buffer->cairo_surface : NULL;
	cairo_t *cr;

	/* reuse current buffer if possible */
	if (buffer && !buffer->used)
		return buffer;

	for (i = 0; i < ARRAY_LENGTH(pool->buffers); i++) {
		if (!pool->buffers[i].used) {
			buffer = &pool->buffers[i];
			buffer->used = true;
			/* ARRAY_LENGTH(pool->buffers) is a factor of pool->size */
			offset = pool->size / ARRAY_LENGTH(pool->buffers) * i;
			break;
		}
	}
	if (!buffer) {
		fprintf(stderr, "no buffers available\n");
		return NULL;
	}

	if (!buffer->wl_buffer) {
		buffer->wl_buffer = wl_shm_pool_create_buffer(pool->wl_shm_pool,
							      offset,
							      surface->width,
							      surface->height,
							      surface->stride,
							      WL_SHM_FORMAT_ARGB8888);
		wl_buffer_add_listener(buffer->wl_buffer,
				       &buffer_listener, buffer);

		buffer->data = (char *)pool->data + offset;
		buffer->cairo_surface =
			cairo_image_surface_create_for_data(buffer->data,
							    CAIRO_FORMAT_ARGB32,
							    surface->width,
							    surface->height,
							    surface->stride);

		if (cairo_surface_status(buffer->cairo_surface) !=
		    CAIRO_STATUS_SUCCESS) {
			fprintf(stderr, "cairo failed to create surface\n");
			wl_buffer_destroy(buffer->wl_buffer);
			buffer->used = false;
			buffer->data = NULL;
			return NULL;
		}
	}

	/* we need to preserve the contents of the old buffer, if any */
	if (prev_surface) {
		cr = cairo_create(buffer->cairo_surface);
		cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
		cairo_set_source_surface(cr, prev_surface, 0, 0);
		cairo_rectangle(cr, 0, 0, surface->width, surface->height);
		cairo_clip(cr);
		cairo_paint(cr);
		cairo_destroy(cr);
	}

	return buffer;
}

static void
shm_pool_deinit(const struct shm_pool *pool)
{
	size_t i;

	for (i = 0; i < ARRAY_LENGTH(pool->buffers); i++) {
		const struct buffer *b = &pool->buffers[i];

		if (b->used) {
			wl_buffer_destroy(b->wl_buffer);
			cairo_surface_destroy(b->cairo_surface);
		}
	}

	if (pool->data) {
		if (munmap(pool->data, pool->size) < 0) {
			fprintf(stderr, "failed to unmap: %s\n", strerror(errno));
		}
		wl_shm_pool_destroy(pool->wl_shm_pool);
	}
}

static int
shm_pool_init(struct shm_pool *pool, size_t size, struct wl_shm *wl_shm)
{
	size_t pool_size = size * ARRAY_LENGTH(pool->buffers);
	int fd = os_create_anonymous_file(pool_size);

	if (fd < 0) {
		fprintf(stderr, "creating a buffer file for %zu B failed: %s\n",
			pool_size, strerror(errno));
		return -1;
	}

	pool->data = mmap(NULL, pool_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (pool->data == MAP_FAILED) {
		fprintf(stderr, "mmap failed: %s\n", strerror(errno));
		close(fd);
		return -1;
	}

	pool->wl_shm_pool = wl_shm_create_pool(wl_shm, fd, pool_size);

	close(fd);

	pool->size = pool_size;

	return 0;
}

static void
surface_set_cursor(const struct surface *surface, bool hide)
{
	const struct constraints *c = surface->constraints;
	struct wl_cursor_image *image = c->window.wl_cursor->images[0];
	struct wl_buffer *buffer = wl_cursor_image_get_buffer(image);

	wl_pointer_set_cursor(c->window.wl_pointer, surface->serial,
			      hide ? NULL : surface->wl_surface_cursor,
			      image->hotspot_x, image->hotspot_y);

	if (!hide) {
		wl_surface_attach(surface->wl_surface_cursor, buffer, 0, 0);
		wl_surface_damage(surface->wl_surface_cursor, 0, 0,
				  image->width, image->height);
	}

	wl_surface_commit(surface->wl_surface_cursor);
}

static void
surface_draw_line(struct surface *surface, const enum constraints_state state)
{
	if (surface->line.x1 != -1 && surface->line.y1 != -1) {
		cairo_t *cr = cairo_create(surface->current_buffer->cairo_surface);

		cairo_set_line_width(cr, 2.0);
		cairo_set_source_rgb(cr, 0, 0, 0);
		cairo_move_to(cr, surface->line.x1, surface->line.y1);
		cairo_line_to(cr, surface->line.x2, surface->line.y2);
		cairo_stroke(cr);
		cairo_destroy(cr);
	}

	if (state != STATE_LOCKED) {
		surface->line.x1 = surface->line.x2;
		surface->line.y1 = surface->line.y2;
	}
}

static void
surface_reset(const struct surface *surface)
{
	cairo_t *cr = cairo_create(surface->current_buffer->cairo_surface);

	cairo_rectangle(cr, 0, 0, surface->width, surface->height);
	cairo_set_source_rgb(cr, surface->rgb[0], surface->rgb[1],
			     surface->rgb[2]);
	cairo_fill(cr);
	cairo_destroy(cr);
}

static void
surface_redraw(struct surface *surface)
{
	struct buffer *buffer;

	if (!(buffer = shm_pool_get_buffer(&surface->pool, surface)))
		return;

	surface->current_buffer = buffer;

	surface->cb = wl_surface_frame(surface->wl_surface);
	wl_callback_add_listener(surface->cb, &frame_listener, surface);

	if (surface->needs_redraw) {
		if (surface->needs_reset) {
			surface_reset(surface);
			surface->needs_reset = false;
		}
		surface_draw_line(surface, surface->constraints->state);
		surface->needs_redraw = false;

		wl_surface_attach(surface->wl_surface, buffer->wl_buffer, 0, 0);
		wl_surface_damage(surface->wl_surface, 0, 0, surface->width, surface->height);
	}

	wl_surface_commit(surface->wl_surface);
}

static void
surface_deinit(const struct surface *surface)
{
	shm_pool_deinit(&surface->pool);

	if (surface->wl_subsurface)
		wl_subsurface_destroy(surface->wl_subsurface);
	if (surface->wl_surface)
		wl_surface_destroy(surface->wl_surface);
	if (surface->wl_surface_cursor)
		wl_surface_destroy(surface->wl_surface_cursor);

	if (surface->cb)
		wl_callback_destroy(surface->cb);
}

static int
surface_init(struct surface *surface, struct constraints *constraints,
	     const float *rgb, int width, int height,
	     const struct surface *parent_surface, int pos_x, int pos_y)
{
	struct window *window = &constraints->window;

	surface->wl_surface = wl_compositor_create_surface(window->wl_compositor);

	surface->rgb[0] = rgb[0];
	surface->rgb[1] = rgb[1];
	surface->rgb[2] = rgb[2];

	surface->width = width;
	surface->height = height;
	surface->stride = cairo_format_stride_for_width(CAIRO_FORMAT_ARGB32,
							surface->width);
	surface->line.x1 = surface->line.y1 = -1;
	surface->line.x2 = surface->line.y2 = -1;

	surface->needs_reset = true;
	surface->needs_redraw = true;

	if (parent_surface) {
		surface->wl_subsurface =
			wl_subcompositor_get_subsurface(window->wl_subcompositor,
							surface->wl_surface,
							parent_surface->wl_surface);
		wl_subsurface_set_position(window->subsurface.wl_subsurface,
					   pos_x, pos_y);
	}

	surface->wl_surface_cursor = wl_compositor_create_surface(window->wl_compositor);

	surface->constraints = constraints;

	return shm_pool_init(&surface->pool, surface->stride * surface->height,
			     window->wl_shm);
}

static void
constraints_reset_state(struct constraints *constraints)
{
	if (constraints->zwp_confined_pointer) {
		zwp_confined_pointer_v1_destroy(constraints->zwp_confined_pointer);
		constraints->zwp_confined_pointer = NULL;
	}
	if (constraints->zwp_relative_pointer) {
		zwp_relative_pointer_v1_destroy(constraints->zwp_relative_pointer);
		constraints->zwp_relative_pointer = NULL;
	}
	if (constraints->zwp_locked_pointer) {
		zwp_locked_pointer_v1_destroy(constraints->zwp_locked_pointer);
		constraints->zwp_locked_pointer = NULL;
	}

	constraints->state = STATE_UNCONSTRAINED;
}

static void
constraints_transition_unconstrained(struct constraints *constraints)
{
	const struct surface *sc = constraints->window.surface_constrained;
	struct zwp_confined_pointer_v1 *confined_pointer;

	confined_pointer =
		zwp_pointer_constraints_v1_confine_pointer(constraints->zwp_pointer_constraints,
							   sc->wl_surface,
							   constraints->window.wl_pointer,
							   NULL,
							   ZWP_POINTER_CONSTRAINTS_V1_LIFETIME_ONESHOT);

	zwp_confined_pointer_v1_add_listener(confined_pointer,
					     &confined_pointer_listener,
					     constraints);
}

static void
constraints_transition_confined(struct constraints *constraints)
{
	const struct surface *sc = constraints->window.surface_constrained;
	struct zwp_locked_pointer_v1 *locked_pointer;

	zwp_confined_pointer_v1_destroy(constraints->zwp_confined_pointer);
	constraints->zwp_confined_pointer = NULL;

	locked_pointer =
		zwp_pointer_constraints_v1_lock_pointer(constraints->zwp_pointer_constraints,
							sc->wl_surface,
							constraints->window.wl_pointer,
							NULL,
							ZWP_POINTER_CONSTRAINTS_V1_LIFETIME_ONESHOT);

	zwp_locked_pointer_v1_add_listener(locked_pointer,
					   &locked_pointer_listener,
					   constraints);
}

static void
constraints_transition_locked(struct constraints *constraints)
{
	struct surface *sc = constraints->window.surface_constrained;

	constraints_reset_state(constraints);

	surface_set_cursor(sc, false);
}

void (*constraints_transition_state[])(struct constraints *constraints) =
{
	constraints_transition_unconstrained,
	constraints_transition_confined,
	constraints_transition_locked
};

static void
constraints_deinit(const struct constraints *constraints)
{
	surface_deinit(&constraints->window.subsurface);
	surface_deinit(&constraints->window.surface);

	if (constraints->zwp_locked_pointer)
		zwp_locked_pointer_v1_destroy(constraints->zwp_locked_pointer);
	if (constraints->zwp_confined_pointer)
		zwp_confined_pointer_v1_destroy(constraints->zwp_confined_pointer);
	if (constraints->zwp_relative_pointer)
		zwp_relative_pointer_v1_destroy(constraints->zwp_relative_pointer);
	if (constraints->zwp_relative_pointer_manager)
		zwp_relative_pointer_manager_v1_destroy(constraints->zwp_relative_pointer_manager);
	if (constraints->zwp_pointer_constraints)
		zwp_pointer_constraints_v1_destroy(constraints->zwp_pointer_constraints);

	if (constraints->window.xdg_toplevel)
		xdg_toplevel_destroy(constraints->window.xdg_toplevel);
	if (constraints->window.xdg_surface)
		xdg_surface_destroy(constraints->window.xdg_surface);
	if (constraints->window.xdg_wm_base)
		xdg_wm_base_destroy(constraints->window.xdg_wm_base);

	if (constraints->window.wl_cursor_theme)
		wl_cursor_theme_destroy(constraints->window.wl_cursor_theme);
	if (constraints->window.wl_shm)
		wl_shm_destroy(constraints->window.wl_shm);
	if (constraints->window.wl_keyboard)
		wl_keyboard_destroy(constraints->window.wl_keyboard);
	if (constraints->window.wl_pointer)
		wl_pointer_destroy(constraints->window.wl_pointer);
	if (constraints->window.wl_seat)
		wl_seat_destroy(constraints->window.wl_seat);
	if (constraints->window.wl_subcompositor)
		wl_subcompositor_destroy(constraints->window.wl_subcompositor);
	if (constraints->window.wl_compositor)
		wl_compositor_destroy(constraints->window.wl_compositor);
	if (constraints->window.wl_registry)
		wl_registry_destroy(constraints->window.wl_registry);
	if (constraints->window.wl_display)
		wl_display_disconnect(constraints->window.wl_display);
}

static int
constraints_check_globals(const struct constraints *c)
{
	if (!c->window.xdg_wm_base) {
		fprintf(stderr, "no xdg-shell found\n");
		return -1;
	}
	if (!c->zwp_pointer_constraints) {
		fprintf(stderr, "no pointer constraints found\n");
		return -1;
	}
	if (!c->zwp_relative_pointer_manager) {
		fprintf(stderr, "no relative pointer manager found\n");
		return -1;
	}
	if (!c->window.wl_seat || !c->window.wl_pointer || !c->window.wl_keyboard) {
		fprintf(stderr, "no valid seat found\n");
		return -1;
	}
	if (!c->argb8888_supported) {
		fprintf(stderr, "WL_SHM_FORMAT_ARGB8888 not supported\n");
		return -1;
	}

	return 0;
}

static int
constraints_init(struct constraints *constraints)
{
	struct window *window = &constraints->window;

	window->wl_display = wl_display_connect(NULL);
	if (!window->wl_display) {
		fprintf(stderr, "failed to connect to Wayland display: %s\n",
			strerror(errno));
		goto fail;
	}

	/* get globals */
	window->wl_registry = wl_display_get_registry(window->wl_display);
	wl_registry_add_listener(window->wl_registry, &registry_listener,
				 constraints);
	/* double roundtrip to get all initial events */
	if (wl_display_roundtrip(window->wl_display) == -1 ||
	    wl_display_roundtrip(window->wl_display) == -1) {
		fprintf(stderr, "wl_display_roundtrip() failed: %s\n",
			strerror(errno));
		goto fail;
	}
	if (constraints_check_globals(constraints) == -1) {
		goto fail;
	}

	/* surface setup */
	if (surface_init(&window->surface, constraints, rgb_surface, SURFACE_WIDTH,
			 SURFACE_HEIGHT, NULL, 0, 0) == -1) {
		fprintf(stderr, "failed to initialize surface\n");
		goto fail;
	}

	/* xdg surface setup */
	window->xdg_surface = xdg_wm_base_get_xdg_surface(window->xdg_wm_base,
							  window->surface.wl_surface);
	xdg_surface_add_listener(window->xdg_surface, &xdg_surface_listener,
				 constraints);
	window->xdg_toplevel = xdg_surface_get_toplevel(window->xdg_surface);
	xdg_toplevel_add_listener(window->xdg_toplevel, &xdg_toplevel_listener,
				  constraints);
	xdg_toplevel_set_title(window->xdg_toplevel, "simple-constraints");
	xdg_toplevel_set_app_id(window->xdg_toplevel, "org.freedesktop.weston.simple-contrains");

	/* sub-surface setup */
	if (surface_init(&window->subsurface, constraints, rgb_subsurface,
			 SUBSURFACE_WIDTH, SUBSURFACE_HEIGHT, &window->surface,
			 SUBSURFACE_X_POS, SUBSURFACE_Y_POS) == -1) {
		fprintf(stderr, "failed to initialize sub-surface\n");
		goto fail;
	}

	wl_surface_commit(window->surface.wl_surface);

	constraints->running = true;

	return 0;
fail:
	if (constraints)
		constraints_deinit(constraints);
	return -1;
}

static void
print_usage(void)
{
	printf("\nDemo client that showcases the Wayland Pointer Constraints"
	       " protocol:\n\n");
	printf("The gray rectangle represents a Wayland subsurface for the"
	       " surface in white.\n");
	printf("Click on any surface to cycle between unconstrained-confined"
	       "-locked states.\n\n");
}

int
main()
{
	static struct constraints constraints;
	int ret = 0;

	print_usage();

	if (constraints_init(&constraints) < 0)
		return -1;

	while (ret != -1 && constraints.running)
		ret = wl_display_dispatch(constraints.window.wl_display);

	constraints_deinit(&constraints);

	return ret;
}
