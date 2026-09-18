/*
 * Copyright 2022 Collabora, Ltd.
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice (including the
 * next paragraph) shall be included in all copies or substantial
 * portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT.  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
 * BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
 * ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#pragma once

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>

struct weston_compositor;

__attribute__((noreturn, format(printf, 2, 3)))
static inline void
weston_assert_fail_(const struct weston_compositor *compositor, const char *fmt, ...)
{
	va_list ap;

	va_start(ap, fmt);
	vfprintf(stderr, fmt, ap);
	va_end(ap);

	abort();
}

#ifndef custom_assert_fail_
#define custom_assert_fail_ weston_assert_fail_
#endif

#define weston_assert_(compositor, a, b, val_type, val_fmt, cmp)		\
({										\
	struct weston_compositor *ec = compositor;				\
	val_type a_ = (a);							\
	val_type b_ = (b);							\
	bool cond = a_ cmp b_;							\
	if (!cond)								\
		custom_assert_fail_(ec, "%s:%u: Assertion %s %s %s (" val_fmt " %s " val_fmt ") failed!\n",	\
				    __FILE__, __LINE__, #a, #cmp, #b, a_, #cmp, b_);				\
	cond;									\
})

#define weston_assert_fn_(compositor, fn, a, b, val_type, val_fmt, cmp)		\
({										\
	struct weston_compositor *ec = compositor;				\
	val_type a_ = (a);							\
	val_type b_ = (b);							\
	bool cond = fn(a_, b_) cmp 0;						\
	if (!cond)								\
		custom_assert_fail_(ec, "%s:%u: Assertion %s %s %s (" val_fmt " %s " val_fmt ") failed!\n",	\
				    __FILE__, __LINE__, #a, #cmp, #b, a_, #cmp, b_);				\
	cond;									\
})

#define weston_assert_true(compositor, a) \
	weston_assert_(compositor, a, true, bool, "%d", ==)

#define weston_assert_ptr(compositor, a) \
	weston_assert_(compositor, a, NULL, const void *, "%p", !=)

#define weston_assert_ptr_is_null(compositor, a) \
	weston_assert_(compositor, a, NULL, const void *, "%p", ==)

#define weston_assert_ptr_eq(compositor, a, b) \
	weston_assert_(compositor, a, b, const void *, "%p", ==)

#define weston_assert_double_eq(compositor, a, b) \
	weston_assert_(compositor, a, b, double, "%.10g", ==)

#define weston_assert_str_eq(compositor, a, b) \
	weston_assert_fn_(compositor, strcmp, a, b, const char *, "%s", ==)
