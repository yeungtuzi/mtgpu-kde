/*
 * Wayland EDR test pattern: commits a PQ/BT.2020 surface via wl_shm and tags
 * it with a wp_color_management_v1 parametric image description.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <math.h>
#include <sys/mman.h>
#include <sys/mman.h>
#ifndef MFD_CLOEXEC
#define MFD_CLOEXEC 0x0001U
#endif
#include <wayland-client.h>
#include "cm-client-protocol.h"
#include "xdg-shell-client-protocol.h"

#define W 1280
#define H 720

static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct xdg_wm_base *wm_base;
static struct wp_color_manager_v1 *cm;
static struct wp_color_management_surface_v1 *color_surface;
static struct wl_surface *surface;
static struct xdg_surface *xdg_surface;
static struct xdg_toplevel *toplevel;
static struct wl_buffer *buffer;
static int desc_ready, configured, pending_commit;

static void wm_ping(void *d, struct xdg_wm_base *w, uint32_t serial) { xdg_wm_base_pong(w, serial); }
static const struct xdg_wm_base_listener wm_listener = { wm_ping };

static void xdg_configure(void *d, struct xdg_surface *xs, uint32_t serial) {
    xdg_surface_ack_configure(xs, serial);
    configured = 1;
}
static const struct xdg_surface_listener xs_listener = { xdg_configure };

static void tl_configure(void *d, struct xdg_toplevel *t, int32_t w, int32_t h, struct wl_array *s) {}
static void tl_close(void *d, struct xdg_toplevel *t) { exit(0); }
static const struct xdg_toplevel_listener tl_listener = { tl_configure, tl_close };

static void d_failed(void *data, struct wp_image_description_v1 *d, uint32_t cause) {
    fprintf(stderr, "image description failed: %u\n", cause);
}
static void set_desc(struct wp_image_description_v1 *d) {
    wp_color_management_surface_v1_set_image_description(color_surface, d,
        WP_COLOR_MANAGER_V1_RENDER_INTENT_PERCEPTUAL);
    desc_ready = 1;
    pending_commit = 1;
    fprintf(stderr, "image description set\n");
}
static void d_ready(void *data, struct wp_image_description_v1 *d, uint32_t ident) { set_desc(d); }
static void d_ready2(void *data, struct wp_image_description_v1 *d, uint32_t hi, uint32_t lo) { set_desc(d); }
static const struct wp_image_description_v1_listener desc_listener = { d_failed, d_ready, d_ready2 };

static void reg_global(void *data, struct wl_registry *reg, uint32_t name, const char *iface, uint32_t ver) {
    if (!strcmp(iface, "wl_compositor")) {
        compositor = wl_registry_bind(reg, name, &wl_compositor_interface, ver > 4 ? 4 : ver);
    } else if (!strcmp(iface, "wl_shm")) {
        shm = wl_registry_bind(reg, name, &wl_shm_interface, 1);
    } else if (!strcmp(iface, "xdg_wm_base")) {
        wm_base = wl_registry_bind(reg, name, &xdg_wm_base_interface, 1);
        xdg_wm_base_add_listener(wm_base, &wm_listener, NULL);
    } else if (!strcmp(iface, "wp_color_manager_v1")) {
        uint32_t v = ver > 3 ? 3 : ver;
        cm = wl_registry_bind(reg, name, &wp_color_manager_v1_interface, v);
        fprintf(stderr, "color manager v%u\n", v);
    }
}
static void reg_remove(void *data, struct wl_registry *reg, uint32_t name) {}
static const struct wl_registry_listener reg_listener = { reg_global, reg_remove };

static int pq_code(double nits) {
    double Y = nits / 10000.0;
    double m1 = 2610.0/16384.0, m2 = 2523.0/4096.0*128.0,
           c1 = 3424.0/4096.0, c2 = 2413.0/4096.0*32.0, c3 = 2392.0/4096.0*32.0;
    double p = pow(Y, m1);
    double N = pow((c1 + c2*p) / (1.0 + c3*p), m2);
    return (int)lround(N * 1023.0);
}

static struct wl_buffer *make_buffer(void) {
    int stride = W * 4, size = stride * H;
    int fd = memfd_create("edr-pattern", MFD_CLOEXEC);
    if (fd < 0 || ftruncate(fd, size) < 0) { perror("memfd"); exit(1); }
    uint32_t *px = mmap(NULL, size, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0);
    if (px == MAP_FAILED) { perror("mmap"); exit(1); }
    const double nits[4] = {100, 203, 500, 1000};
    for (int x = 0; x < W; x++) {
        int band = x * 4 / W;
        int code = pq_code(nits[band]);
        int v8 = (code * 255 + 511) / 1023;
        uint32_t c = 0x00000000u | (v8 << 16) | (v8 << 8) | v8;
        for (int y = 0; y < H; y++) px[y*W + x] = c;
    }
    munmap(px, size);
    struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, size);
    struct wl_buffer *b = wl_shm_pool_create_buffer(pool, 0, W, H, stride, WL_SHM_FORMAT_XRGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);
    return b;
}

int main(void) {
    struct wl_display *dpy = wl_display_connect(NULL);
    if (!dpy) { fprintf(stderr, "no wayland display\n"); return 1; }
    struct wl_registry *reg = wl_display_get_registry(dpy);
    wl_registry_add_listener(reg, &reg_listener, NULL);
    wl_display_roundtrip(dpy);
    if (!compositor || !shm || !wm_base || !cm) {
        fprintf(stderr, "missing globals (compositor=%p shm=%p xdg=%p cm=%p)\n",
                (void*)compositor, (void*)shm, (void*)wm_base, (void*)cm);
        return 1;
    }

    surface = wl_compositor_create_surface(compositor);
    xdg_surface = xdg_wm_base_get_xdg_surface(wm_base, surface);
    xdg_surface_add_listener(xdg_surface, &xs_listener, NULL);
    toplevel = xdg_surface_get_toplevel(xdg_surface);
    xdg_toplevel_add_listener(toplevel, &tl_listener, NULL);
    xdg_toplevel_set_title(toplevel, "EDR test pattern (100/203/500/1000 nit)");

    buffer = make_buffer();
    color_surface = wp_color_manager_v1_get_surface(cm, surface);

    struct wp_image_description_creator_params_v1 *creator =
        wp_color_manager_v1_create_parametric_creator(cm);
    wp_image_description_creator_params_v1_set_tf_named(creator,
        WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_ST2084_PQ);
    wp_image_description_creator_params_v1_set_primaries_named(creator,
        WP_COLOR_MANAGER_V1_PRIMARIES_BT2020);
    wp_image_description_creator_params_v1_set_luminances(creator, 100, 1000, 203);
    wp_image_description_creator_params_v1_set_max_cll(creator, 1000);
    wp_image_description_creator_params_v1_set_max_fall(creator, 400);
    struct wp_image_description_v1 *desc =
        wp_image_description_creator_params_v1_create(creator);
    wp_image_description_v1_add_listener(desc, &desc_listener, NULL);

    wl_surface_commit(surface);
    while (!configured) wl_display_dispatch(dpy);

    wl_surface_attach(surface, buffer, 0, 0);
    wl_surface_damage_buffer(surface, 0, 0, W, H);
    wl_surface_commit(surface);

    for (;;) {
        wl_display_dispatch(dpy);
        if (pending_commit) {
            pending_commit = 0;
            wl_surface_attach(surface, buffer, 0, 0);
            wl_surface_damage_buffer(surface, 0, 0, W, H);
            wl_surface_commit(surface);
        }
    }
    return 0;
}
