#ifndef MODEB_DEMO_SUPPORT_H
#define MODEB_DEMO_SUPPORT_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

int modeb_demo_ptrace_trace_me(void);
void modeb_demo_try_self_enable_jit(const char *argv0);
bool modeb_demo_cs_debugged(void);
void modeb_demo_probe_jit_and_fb(void);
void modeb_demo_fb_start(void);
void modeb_demo_fb_tick(void);
const char *modeb_demo_hud_text(void);

#ifdef __cplusplus
}
#endif

#endif
