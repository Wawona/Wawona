#include <drm_ioctl.h>
#include <drm_linux.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

static int npass, nfail;

#define TEST(name)   do { printf("  " name " ... "); } while(0)
#define PASS()       do { printf("PASS\n"); npass++; } while(0)
#define FAIL(fmt, ...) do { printf("FAIL  " fmt "\n", ##__VA_ARGS__); nfail++; } while(0)
#define CHECK(cond)  do { if (!(cond)) { FAIL("line %d", __LINE__); return; } } while(0)
#define CHECK_ERRNO(e) do { if (errno != (e)) { FAIL("expected errno=%d got %d", (e), errno); return; } } while(0)

/* ── helpers ──────────────────────────────────────────────────────────── */

static int do_ioctl(int fd, unsigned long req, void *arg)
{
    return ioctl(fd, req, arg);
}

/* ── tests ────────────────────────────────────────────────────────────── */

static void t_open_virtual(void)
{
    TEST("open /dev/dri/card0 yields fd=42");
    int fd = open("/dev/dri/card0", O_RDWR);
    CHECK(fd == 42);
    PASS();
}

static void t_open_virtual_multi(void)
{
    TEST("open /dev/dri/card[0-9] all yield fd=42");
    for (int i = 0; i <= 9; i++) {
        char path[32];
        snprintf(path, sizeof(path), "/dev/dri/card%d", i);
        int fd = open(path, O_RDWR);
        if (fd != 42) {
            FAIL("card%d returned %d", i, fd);
            return;
        }
        close(fd);
    }
    PASS();
}

static void t_open_non_drm_bypass(void)
{
    TEST("open /dev/null bypasses hook");
    int fd = open("/dev/null", O_RDONLY);
    CHECK(fd >= 0);
    if (fd >= 0) close(fd);
    PASS();
}

static void t_close_virtual(void)
{
    TEST("close(42) returns 0");
    int fd = open("/dev/dri/card0", O_RDWR);
    int ret = close(fd);
    CHECK(ret == 0);
    PASS();
}

static void t_version(void)
{
    TEST("DRM_IOCTL_VERSION");
    int fd = open("/dev/dri/card0", O_RDWR);
    struct drm_version v = {0};
    char name[64], date[64], desc[128];
    v.name = name; v.name_len = sizeof(name);
    v.date = date; v.date_len = sizeof(date);
    v.desc = desc; v.desc_len = sizeof(desc);
    int ret = do_ioctl(fd, DRM_IOCTL_VERSION, &v);
    CHECK(ret == 0);
    CHECK(v.version_major == 2);
    CHECK(v.version_patchlevel == 0);
    printf("got %d.%d.%d name=\"%s\"", v.version_major, v.version_minor,
           v.version_patchlevel, name);
    close(fd);
    PASS();
}

static void t_get_magic(void)
{
    TEST("DRM_IOCTL_GET_MAGIC");
    int fd = open("/dev/dri/card0", O_RDWR);
    struct drm_auth a = {0};
    int ret = do_ioctl(fd, DRM_IOCTL_GET_MAGIC, &a);
    CHECK(ret == 0);
    CHECK(a.magic == 1);
    close(fd);
    PASS();
}

static void t_auth_magic(void)
{
    TEST("DRM_IOCTL_AUTH_MAGIC");
    int fd = open("/dev/dri/card0", O_RDWR);
    struct drm_auth a = {.magic = 1};
    int ret = do_ioctl(fd, DRM_IOCTL_AUTH_MAGIC, &a);
    CHECK(ret == 0);
    close(fd);
    PASS();
}

static void t_set_master(void)
{
    TEST("DRM_IOCTL_SET_MASTER");
    int fd = open("/dev/dri/card0", O_RDWR);
    int ret = do_ioctl(fd, DRM_IOCTL_SET_MASTER, NULL);
    CHECK(ret == 0);
    close(fd);
    PASS();
}

static void t_drop_master(void)
{
    TEST("DRM_IOCTL_DROP_MASTER");
    int fd = open("/dev/dri/card0", O_RDWR);
    int ret = do_ioctl(fd, DRM_IOCTL_DROP_MASTER, NULL);
    CHECK(ret == 0);
    close(fd);
    PASS();
}

static void t_get_cap(void)
{
    TEST("DRM_IOCTL_GET_CAP");
    int fd = open("/dev/dri/card0", O_RDWR);
    struct drm_get_cap c = {.capability = DRM_CAP_DUMB_BUFFER};
    int ret = do_ioctl(fd, DRM_IOCTL_GET_CAP, &c);
    CHECK(ret == 0);
    CHECK(c.value == 1);
    c.capability = DRM_CAP_PRIME;
    ret = do_ioctl(fd, DRM_IOCTL_GET_CAP, &c);
    CHECK(ret == 0);
    CHECK(c.value == 3);
    c.capability = DRM_CAP_TIMESTAMP_MONOTONIC;
    ret = do_ioctl(fd, DRM_IOCTL_GET_CAP, &c);
    CHECK(ret == 0);
    CHECK(c.value == 1);
    close(fd);
    PASS();
}

static void t_set_client_cap(void)
{
    TEST("DRM_IOCTL_SET_CLIENT_CAP");
    int fd = open("/dev/dri/card0", O_RDWR);
    struct drm_set_client_cap c = {
        .capability = DRM_CLIENT_CAP_UNIVERSAL_PLANES,
        .value = 1
    };
    int ret = do_ioctl(fd, DRM_IOCTL_SET_CLIENT_CAP, &c);
    CHECK(ret == 0);
    close(fd);
    PASS();
}

static void t_get_resources(void)
{
    TEST("DRM_IOCTL_MODE_GETRESOURCES (0-count)");
    int fd = open("/dev/dri/card0", O_RDWR);
    struct drm_mode_card_res res = {0};
    int ret = do_ioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, &res);
    CHECK(ret == 0);
    CHECK(res.count_crtcs == 1);
    CHECK(res.count_connectors == 1);
    CHECK(res.count_encoders == 1);
    printf("fbs=%d crtcs=%d conns=%d encs=%d",
           res.count_fbs, res.count_crtcs,
           res.count_connectors, res.count_encoders);
    PASS();

    TEST("DRM_IOCTL_MODE_GETRESOURCES (with buffers)");
    uint32_t crtcs[4], conns[4], encs[4];
    memset(&res, 0, sizeof(res));
    res.crtc_id_ptr      = (uint64_t)(uintptr_t)crtcs;
    res.connector_id_ptr = (uint64_t)(uintptr_t)conns;
    res.encoder_id_ptr   = (uint64_t)(uintptr_t)encs;
    res.count_crtcs      = 4;
    res.count_connectors = 4;
    res.count_encoders   = 4;
    ret = do_ioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, &res);
    CHECK(ret == 0);
    CHECK(crtcs[0] == 1);
    CHECK(conns[0] == 1);
    CHECK(encs[0] == 1);
    CHECK(res.min_width > 0);
    CHECK(res.max_height > 0);
    PASS();

    close(fd);
}

static void t_get_crtc(void)
{
    TEST("DRM_IOCTL_MODE_GETCRTC");
    int fd = open("/dev/dri/card0", O_RDWR);
    struct drm_mode_crtc c = {.crtc_id = 1};
    int ret = do_ioctl(fd, DRM_IOCTL_MODE_GETCRTC, &c);
    CHECK(ret == 0);
    CHECK(c.crtc_id == 1);
    CHECK(c.gamma_size == 256);
    close(fd);
    PASS();
}

static void t_get_encoder(void)
{
    TEST("DRM_IOCTL_MODE_GETENCODER");
    int fd = open("/dev/dri/card0", O_RDWR);
    struct drm_mode_get_encoder e = {.encoder_id = 1};
    int ret = do_ioctl(fd, DRM_IOCTL_MODE_GETENCODER, &e);
    CHECK(ret == 0);
    CHECK(e.encoder_id == 1);
    CHECK(e.crtc_id == 1);
    CHECK(e.possible_crtcs == 1);
    close(fd);
    PASS();
}

static void t_get_connector(void)
{
    TEST("DRM_IOCTL_MODE_GETCONNECTOR (phase 1: get counts)");
    int fd = open("/dev/dri/card0", O_RDWR);
    struct drm_mode_get_connector kc = {.connector_id = 1};
    int ret = do_ioctl(fd, DRM_IOCTL_MODE_GETCONNECTOR, &kc);
    CHECK(ret == 0);
    CHECK(kc.connector_type == DRM_MODE_CONNECTOR_DisplayPort);
    CHECK(kc.connection == DRM_MODE_CONNECTED);
    CHECK(kc.count_modes > 0);
    int nm = kc.count_modes;
    PASS();

    TEST("DRM_IOCTL_MODE_GETCONNECTOR (phase 2: get modes)");
    struct drm_mode_modeinfo *modes = calloc(nm, sizeof(*modes));
    CHECK(modes != NULL);
    memset(&kc, 0, sizeof(kc));
    kc.connector_id = 1;
    kc.modes_ptr    = (uint64_t)(uintptr_t)modes;
    kc.count_modes  = nm;
    ret = do_ioctl(fd, DRM_IOCTL_MODE_GETCONNECTOR, &kc);
    CHECK(ret == 0);
    CHECK(kc.count_modes == nm);
    CHECK(modes[0].hdisplay > 0);
    printf("mode[0] = %s", modes[0].name);
    free(modes);
    PASS();
    close(fd);
}

static void t_dumb_create_map_destroy(void)
{
    TEST("DRM_IOCTL_MODE_CREATE_DUMB");
    int fd = open("/dev/dri/card0", O_RDWR);
    struct drm_mode_create_dumb d = {
        .width = 64, .height = 64, .bpp = 32
    };
    int ret = do_ioctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &d);
    CHECK(ret == 0);
    CHECK(d.handle > 0);
    CHECK(d.pitch >= 64 * 4);
    CHECK(d.size >= 64 * 64 * 4);
    uint32_t h = d.handle;
    PASS();

    TEST("DRM_IOCTL_MODE_MAP_DUMB");
    struct drm_mode_map_dumb md = {.handle = h};
    ret = do_ioctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &md);
    CHECK(ret == 0);
    CHECK(md.offset != 0);
    PASS();

    TEST("DRM_IOCTL_MODE_DESTROY_DUMB");
    struct drm_mode_destroy_dumb dd = {.handle = h};
    ret = do_ioctl(fd, DRM_IOCTL_MODE_DESTROY_DUMB, &dd);
    CHECK(ret == 0);
    PASS();
    close(fd);
}

static void t_framebuffer_add_rm(void)
{
    TEST("DRM_IOCTL_MODE_ADDFB + RMFB");
    int fd = open("/dev/dri/card0", O_RDWR);
    struct drm_mode_create_dumb d = {
        .width = 64, .height = 64, .bpp = 32
    };
    do_ioctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &d);

    struct drm_mode_fb_cmd f = {
        .width = 64, .height = 64,
        .depth = 24, .bpp = 32,
        .pitch = d.pitch, .handle = d.handle
    };
    int ret = do_ioctl(fd, DRM_IOCTL_MODE_ADDFB, &f);
    CHECK(ret == 0);
    CHECK(f.fb_id > 0);

    ret = do_ioctl(fd, DRM_IOCTL_MODE_RMFB, &f.fb_id);
    CHECK(ret == 0);

    struct drm_mode_destroy_dumb dd = {.handle = d.handle};
    do_ioctl(fd, DRM_IOCTL_MODE_DESTROY_DUMB, &dd);
    close(fd);
    PASS();
}

static void t_page_flip(void)
{
    TEST("DRM_IOCTL_MODE_PAGE_FLIP");
    int fd = open("/dev/dri/card0", O_RDWR);
    struct drm_mode_crtc_page_flip pf = {
        .crtc_id = 1, .fb_id = 0,
        .flags = DRM_MODE_PAGE_FLIP_EVENT
    };
    int ret = do_ioctl(fd, DRM_IOCTL_MODE_PAGE_FLIP, &pf);
    if (ret == 0)
        PASS();
    else
        printf("SKIP (fb=0 — framebufferd may not be running) … SKIP\n");
    close(fd);
}

static void t_cursor(void)
{
    TEST("DRM_IOCTL_MODE_CURSOR (set + move)");
    int fd = open("/dev/dri/card0", O_RDWR);
    struct drm_mode_cursor c = {
        .flags = DRM_MODE_CURSOR_BO,
        .crtc_id = 1, .handle = 0,
        .width = 64, .height = 64
    };
    int ret = do_ioctl(fd, DRM_IOCTL_MODE_CURSOR, &c);
    CHECK(ret == 0);

    c.flags = DRM_MODE_CURSOR_MOVE;
    c.x = 100; c.y = 200;
    ret = do_ioctl(fd, DRM_IOCTL_MODE_CURSOR, &c);
    CHECK(ret == 0);
    close(fd);
    PASS();
}

static void t_planes(void)
{
    TEST("DRM_IOCTL_MODE_GETPLANERESOURCES");
    int fd = open("/dev/dri/card0", O_RDWR);
    /* Need CLIENT_CAP_UNIVERSAL_PLANES first */
    struct drm_set_client_cap scc = {
        .capability = DRM_CLIENT_CAP_UNIVERSAL_PLANES, .value = 1
    };
    do_ioctl(fd, DRM_IOCTL_SET_CLIENT_CAP, &scc);

    struct drm_mode_get_plane_res pr = {0};
    int ret = do_ioctl(fd, DRM_IOCTL_MODE_GETPLANERESOURCES, &pr);
    CHECK(ret == 0);
    CHECK(pr.count_planes == 3);
    PASS();

    TEST("DRM_IOCTL_MODE_GETPLANE");
    uint32_t pids[16];
    memset(&pr, 0, sizeof(pr));
    pr.plane_id_ptr = (uint64_t)(uintptr_t)pids;
    pr.count_planes = 16;
    do_ioctl(fd, DRM_IOCTL_MODE_GETPLANERESOURCES, &pr);

    for (uint32_t i = 0; i < pr.count_planes; i++) {
        uint32_t fmt_buf[8];
        struct drm_mode_get_plane gp = {
            .plane_id = pids[i],
            .format_type_ptr = (uint64_t)(uintptr_t)fmt_buf,
            .count_format_types = 8
        };
        ret = do_ioctl(fd, DRM_IOCTL_MODE_GETPLANE, &gp);
        CHECK(ret == 0);
        CHECK(gp.crtc_id == 1);
    }
    PASS();
    close(fd);
}

static void t_object_properties(void)
{
    TEST("DRM_IOCTL_MODE_OBJ_GETPROPERTIES + GETPROPERTY");
    int fd = open("/dev/dri/card0", O_RDWR);

    /* CRTC properties */
    uint32_t pids[16];
    uint64_t pvals[16];
    struct drm_mode_obj_get_properties op = {
        .obj_id = 1,
        .obj_type = DRM_MODE_OBJECT_CRTC,
        .props_ptr = (uint64_t)(uintptr_t)pids,
        .prop_values_ptr = (uint64_t)(uintptr_t)pvals,
        .count_props = 16
    };
    int ret = do_ioctl(fd, DRM_IOCTL_MODE_OBJ_GETPROPERTIES, &op);
    CHECK(ret == 0);
    CHECK(op.count_props > 0);

    /* Get first property */
    struct drm_mode_get_property gp = {
        .prop_id = pids[0],
        .values_ptr = 0,
        .count_values = 0
    };
    ret = do_ioctl(fd, DRM_IOCTL_MODE_GETPROPERTY, &gp);
    CHECK(ret == 0);
    CHECK(gp.name[0] != 0);

    /* Connector properties */
    memset(&op, 0, sizeof(op));
    op.obj_id = 1;
    op.obj_type = DRM_MODE_OBJECT_CONNECTOR;
    op.props_ptr = (uint64_t)(uintptr_t)pids;
    op.prop_values_ptr = (uint64_t)(uintptr_t)pvals;
    op.count_props = 16;
    ret = do_ioctl(fd, DRM_IOCTL_MODE_OBJ_GETPROPERTIES, &op);
    CHECK(ret == 0);
    CHECK(op.count_props > 0);

    close(fd);
    PASS();
}

static void t_blobs(void)
{
    TEST("DRM_IOCTL_MODE_CREATEPROPBLOB + GETPROPBLOB + DESTROYPROPBLOB");
    int fd = open("/dev/dri/card0", O_RDWR);
    uint32_t blob_data[] = {0x12345678, 0x87654321};

    struct drm_mode_create_blob cb = {
        .data = (uint64_t)(uintptr_t)blob_data,
        .length = sizeof(blob_data)
    };
    int ret = do_ioctl(fd, DRM_IOCTL_MODE_CREATEPROPBLOB, &cb);
    CHECK(ret == 0);
    CHECK(cb.blob_id > 0);
    uint32_t bid = cb.blob_id;

    struct drm_mode_get_property_blob gb = {
        .blob_id = bid,
        .data = (uint64_t)(uintptr_t)blob_data,
        .length = sizeof(blob_data)
    };
    ret = do_ioctl(fd, DRM_IOCTL_MODE_GETPROPBLOB, &gb);
    CHECK(ret == 0);
    CHECK(gb.length == sizeof(blob_data));

    struct drm_mode_destroy_blob db = {.blob_id = bid};
    ret = do_ioctl(fd, DRM_IOCTL_MODE_DESTROYPROPBLOB, &db);
    CHECK(ret == 0);
    close(fd);
    PASS();
}

static void t_atomic(void)
{
    TEST("DRM_IOCTL_MODE_ATOMIC");
    int fd = open("/dev/dri/card0", O_RDWR);

    /* Need atomic cap */
    struct drm_set_client_cap scc = {
        .capability = DRM_CLIENT_CAP_ATOMIC, .value = 1
    };
    do_ioctl(fd, DRM_IOCTL_SET_CLIENT_CAP, &scc);

    /* Test-only atomic commit (no real changes) */
    struct drm_mode_atomic a = {
        .flags = DRM_MODE_ATOMIC_TEST_ONLY | DRM_MODE_ATOMIC_ALLOW_MODESET,
        .count_objs = 0
    };
    int ret = do_ioctl(fd, DRM_IOCTL_MODE_ATOMIC, &a);
    CHECK(ret == 0);

    close(fd);
    PASS();
}

static void t_prime(void)
{
    TEST("DRM_IOCTL_PRIME_HANDLE_TO_FD");
    int fd = open("/dev/dri/card0", O_RDWR);
    struct drm_prime_handle p = {.handle = 1, .flags = DRM_CLOEXEC};
    int ret = do_ioctl(fd, DRM_IOCTL_PRIME_HANDLE_TO_FD, &p);
    CHECK(ret == 0);
    CHECK(p.fd >= 0);
    if (p.fd >= 0) close(p.fd);

    TEST("DRM_IOCTL_PRIME_FD_TO_HANDLE");
    p.handle = 0;
    int pfd[2];
    pipe(pfd);
    p.fd = pfd[0];
    ret = do_ioctl(fd, DRM_IOCTL_PRIME_FD_TO_HANDLE, &p);
    CHECK(ret == 0);
    CHECK(p.handle > 0);
    close(pfd[1]);
    close(fd);
    PASS();
}

static void t_syncobj(void)
{
    TEST("DRM_IOCTL_SYNCOBJ_CREATE + DESTROY");
    int fd = open("/dev/dri/card0", O_RDWR);
    struct drm_syncobj_create sc = {.flags = 0};
    int ret = do_ioctl(fd, DRM_IOCTL_SYNCOBJ_CREATE, &sc);
    CHECK(ret == 0);
    CHECK(sc.handle > 0);

    struct drm_syncobj_destroy sd = {.handle = sc.handle};
    ret = do_ioctl(fd, DRM_IOCTL_SYNCOBJ_DESTROY, &sd);
    CHECK(ret == 0);
    close(fd);
    PASS();
}

static void t_invalid_ioctl(void)
{
    TEST("invalid ioctl returns ENOTTY");
    int fd = open("/dev/dri/card0", O_RDWR);
    unsigned long bad_req = LINUX_IOW(DRM_IOCTL_BASE, 0xFF, sizeof(int));
    errno = 0;
    int ret = do_ioctl(fd, bad_req, NULL);
    CHECK(ret == -1);
    CHECK_ERRNO(ENOTTY);
    close(fd);
    PASS();
}

static void t_non_drm_ioctl_bypass(void)
{
    TEST("ioctl on non-virtual fd reaches kernel");
    int real_fd = open("/dev/null", O_RDONLY);
    CHECK(real_fd >= 0);
    errno = 0;
    int ret = do_ioctl(real_fd, 0, NULL);
    CHECK(ret == -1);
    /* Real kernel rejects unknown ioctls — ENOTTY or ENODEV depending
     * on the device driver.  We just need to confirm it's a real error,
     * not a crash or our virtual-driver path. */
    close(real_fd);
    PASS();
}

static void t_wrong_type_ioctl(void)
{
    TEST("ioctl with wrong type (not 'd') returns ENOTTY");
    int fd = open("/dev/dri/card0", O_RDWR);
    unsigned long bad_req = LINUX_IOW('X', 0x00, sizeof(int));
    errno = 0;
    int ret = do_ioctl(fd, bad_req, NULL);
    CHECK(ret == -1);
    CHECK_ERRNO(ENOTTY);
    close(fd);
    PASS();
}

/* ── main ──────────────────────────────────────────────────────────────── */

int main(void)
{
    printf("[test_drm_system_ties] Testing DRM system call interception\n");
    printf("  NOTE: requires root (DYLD_INSERT_LIBRARIES or direct link)\n\n");

    t_open_virtual();
    t_open_virtual_multi();
    t_open_non_drm_bypass();
    t_close_virtual();
    t_version();
    t_get_magic();
    t_auth_magic();
    t_set_master();
    t_drop_master();
    t_get_cap();
    t_set_client_cap();
    t_get_resources();
    t_get_crtc();
    t_get_encoder();
    t_get_connector();
    t_dumb_create_map_destroy();
    t_framebuffer_add_rm();
    t_page_flip();
    t_cursor();
    t_planes();
    t_object_properties();
    t_blobs();
    t_atomic();
    t_prime();
    t_syncobj();
    t_invalid_ioctl();
    t_non_drm_ioctl_bypass();
    t_wrong_type_ioctl();

    printf("\n[test_drm_system_ties] %d passed, %d failed\n", npass, nfail);
    return nfail > 0 ? 1 : 0;
}
