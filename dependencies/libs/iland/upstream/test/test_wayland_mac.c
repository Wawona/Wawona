#include <wayland-mac.h>
#include <stdio.h>

int main(void) {
    printf("[test] wayland-mac loaded\n");
    wayland_mac_init();

    const char *msg = "{\"event\":\"test\",\"source\":\"test_wayland_mac\"}";
    printf("[test] sending: %s\n", msg);
    int ret = drm_send_json(msg);
    if (ret == 0)
        printf("[test] drm_send_json ok\n");
    else
        printf("[test] drm_send_json failed (framebufferd not running?)\n");

    return 0;
}
