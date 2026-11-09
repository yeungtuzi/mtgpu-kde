#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <wayland-client.h>
#include "cm-client-protocol.h"

static struct wp_color_manager_v1 *cm;
static struct wl_output *out;
static int got;

static void inf_icc(void *d, struct wp_image_description_info_v1 *i, int32_t fd, uint32_t sz) {}
static void inf_prim(void *d, struct wp_image_description_info_v1 *i, int32_t a,int32_t b,int32_t c,int32_t e,int32_t f,int32_t g,int32_t h,int32_t j) {}
static void inf_prim_named(void *d, struct wp_image_description_info_v1 *i, uint32_t p) {}
static void inf_tf_power(void *d, struct wp_image_description_info_v1 *i, uint32_t e) {}
static void inf_tf_named(void *d, struct wp_image_description_info_v1 *i, uint32_t tf) { printf("tf_named=%u\n", tf); }
static void inf_lum(void *d, struct wp_image_description_info_v1 *i, uint32_t mn, uint32_t mx, uint32_t ref) {
    printf("LUMINANCES min=%.2f max=%u reference=%u\n", mn/10000.0, mx, ref);
}
static void inf_tprim(void *d, struct wp_image_description_info_v1 *i, uint32_t p) {}
static void inf_tlum(void *d, struct wp_image_description_info_v1 *i, uint32_t mn, uint32_t mx) { printf("TARGET_LUM min=%.2f max=%u\n", mn/10000.0, mx); }
static void inf_cll(void *d, struct wp_image_description_info_v1 *i, uint32_t v) { printf("max_cll=%u\n", v); }
static void inf_fall(void *d, struct wp_image_description_info_v1 *i, uint32_t v) {}
static void inf_done(void *d, struct wp_image_description_info_v1 *i) { got = 1; }

static const struct wp_image_description_info_v1_listener info_l = {
    .icc_file = inf_icc, .primaries = inf_prim, .primaries_named = inf_prim_named,
    .tf_power = inf_tf_power, .tf_named = inf_tf_named, .luminances = inf_lum,
    .target_primaries = inf_tprim, .target_luminance = inf_tlum,
    .target_max_cll = inf_cll, .target_max_fall = inf_fall, .done = inf_done,
};
static void d_failed(void *d, struct wp_image_description_v1 *x, uint32_t c) {}
static void d_ready(void *d, struct wp_image_description_v1 *x, uint32_t id) {}
static void d_ready2(void *d, struct wp_image_description_v1 *x, uint32_t id) {}
static const struct wp_image_description_v1_listener desc_l = { d_failed, d_ready, d_ready2 };

static void reg_glob(void *d, struct wl_registry *r, uint32_t name, const char *iface, uint32_t ver) {
    if (!strcmp(iface, "wl_output") && !out) out = wl_registry_bind(r, name, &wl_output_interface, ver > 2 ? 2 : ver);
    else if (!strcmp(iface, "wp_color_manager_v1")) cm = wl_registry_bind(r, name, &wp_color_manager_v1_interface, ver > 2 ? 2 : ver);
}
static void reg_rm(void *d, struct wl_registry *r, uint32_t n) {}
static const struct wl_registry_listener reg_l = { reg_glob, reg_rm };

int main(void) {
    struct wl_display *dpy = wl_display_connect(NULL);
    if (!dpy) { puts("no display"); return 1; }
    struct wl_registry *reg = wl_display_get_registry(dpy);
    wl_registry_add_listener(reg, &reg_l, NULL);
    wl_display_roundtrip(dpy);
    if (!cm || !out) { puts("missing globals"); return 1; }
    struct wp_color_management_output_v1 *co = wp_color_manager_v1_get_output(cm, out);
    struct wp_image_description_v1 *desc = wp_color_management_output_v1_get_image_description(co);
    wp_image_description_v1_add_listener(desc, &desc_l, NULL);
    struct wp_image_description_info_v1 *info = wp_image_description_v1_get_information(desc);
    wp_image_description_info_v1_add_listener(info, &info_l, NULL);
    for (int i = 0; i < 30 && !got; i++) { wl_display_roundtrip(dpy); usleep(100000); }
    return got ? 0 : 2;
}
