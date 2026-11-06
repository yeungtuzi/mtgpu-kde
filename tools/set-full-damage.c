// set-full-damage: continuously set FB_DAMAGE_CLIPS on the active primary
// plane to a blob covering the whole CRTC, to test whether mtgpu/mtdisp
// mishandles the "0 = full damage" convention.
//
// Build:
//   gcc -O2 -o set-full-damage set-full-damage.c $(pkg-config --cflags --libs libdrm)
// Run (as root, while KWin is running):
//   sudo ./set-full-damage [card] [width] [height]
// Default card=/dev/dri/card0; width/height are read from CRTC_W/CRTC_H.

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <xf86drm.h>
#include <xf86drmMode.h>
#include <drm/drm_mode.h>

static uint64_t prop_value(drmModeObjectProperties *props, uint32_t id)
{
    for (uint32_t i = 0; i < props->count_props; i++) {
        if (props->props[i] == id)
            return props->prop_values[i];
    }
    return 0;
}

static drmModePropertyPtr find_prop(int fd, uint32_t obj, uint32_t obj_type,
                                    drmModeObjectProperties *props, const char *name)
{
    for (uint32_t i = 0; i < props->count_props; i++) {
        drmModePropertyPtr p = drmModeGetProperty(fd, props->props[i]);
        if (!p)
            continue;
        if (strcmp(p->name, name) == 0)
            return p;
        drmModeFreeProperty(p);
    }
    return NULL;
}

int main(int argc, char **argv)
{
    const char *card = argc > 1 ? argv[1] : "/dev/dri/card0";
    int fd = open(card, O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        perror("open card");
        return 1;
    }
    drmSetClientCap(fd, DRM_CLIENT_CAP_UNIVERSAL_PLANES, 1);
    drmSetClientCap(fd, DRM_CLIENT_CAP_ATOMIC, 1);

    drmModePlaneRes *pres = drmModeGetPlaneResources(fd);
    if (!pres) {
        perror("drmModeGetPlaneResources");
        return 1;
    }

    uint32_t plane_id = 0, crtc_w = 0, crtc_h = 0, damage_id = 0, fb_id_prop = 0;
    for (uint32_t i = 0; i < pres->count_planes; i++) {
        drmModePlane *pl = drmModeGetPlane(fd, pres->planes[i]);
        if (!pl)
            continue;
        drmModeObjectProperties *props =
            drmModeObjectGetProperties(fd, pl->plane_id, DRM_MODE_OBJECT_PLANE);
        if (!props) {
            drmModeFreePlane(pl);
            continue;
        }
        drmModePropertyPtr fbprop = find_prop(fd, pl->plane_id, DRM_MODE_OBJECT_PLANE, props, "FB_ID");
        drmModePropertyPtr dmgprop = find_prop(fd, pl->plane_id, DRM_MODE_OBJECT_PLANE, props, "FB_DAMAGE_CLIPS");
        drmModePropertyPtr wprop = find_prop(fd, pl->plane_id, DRM_MODE_OBJECT_PLANE, props, "CRTC_W");
        drmModePropertyPtr hprop = find_prop(fd, pl->plane_id, DRM_MODE_OBJECT_PLANE, props, "CRTC_H");
        if (fbprop) {
            fprintf(stderr, "plane %u: FB_ID=%llu damage=%s CRTC_W=%llu CRTC_H=%llu\n",
                    pl->plane_id, (unsigned long long)prop_value(props, fbprop->prop_id),
                    dmgprop ? "yes" : "no",
                    (unsigned long long)(wprop ? prop_value(props, wprop->prop_id) : 0),
                    (unsigned long long)(hprop ? prop_value(props, hprop->prop_id) : 0));
        }
        if (fbprop && dmgprop && wprop && hprop) {
            uint64_t fb = prop_value(props, fbprop->prop_id);
            uint64_t w = prop_value(props, wprop->prop_id);
            uint64_t h = prop_value(props, hprop->prop_id);
            if (fb != 0 && dmgprop->flags & DRM_MODE_PROP_BLOB) {
                plane_id = pl->plane_id;
                crtc_w = w;
                crtc_h = h;
                damage_id = dmgprop->prop_id;
                fb_id_prop = fbprop->prop_id;
                fprintf(stderr, "plane %u: fb=%llu CRTC=%ux%u damage_prop=%u\n",
                        plane_id, (unsigned long long)fb, crtc_w, crtc_h, damage_id);
            }
        }
        if (fbprop) drmModeFreeProperty(fbprop);
        if (dmgprop) drmModeFreeProperty(dmgprop);
        if (wprop) drmModeFreeProperty(wprop);
        if (hprop) drmModeFreeProperty(hprop);
        drmModeFreeObjectProperties(props);
        drmModeFreePlane(pl);
        if (plane_id)
            break;
    }
    drmModeFreePlaneResources(pres);

    if (!plane_id) {
        fprintf(stderr, "no active plane with FB_DAMAGE_CLIPS found\n");
        return 1;
    }
    if (argc > 3) {
        crtc_w = strtoul(argv[2], NULL, 0);
        crtc_h = strtoul(argv[3], NULL, 0);
    }

    struct drm_mode_rect rect = { .x1 = 0, .y1 = 0,
                           .x2 = (int32_t)crtc_w, .y2 = (int32_t)crtc_h };
    uint32_t blob = 0;
    int ret = drmModeCreatePropertyBlob(fd, &rect, sizeof(rect), &blob);
    if (ret != 0) {
        fprintf(stderr, "create blob failed: %s\n", strerror(errno));
        return 1;
    }
    fprintf(stderr, "blob %u: rect 0,0..%u,%u\n", blob, crtc_w, crtc_h);

    for (;;) {
        drmModeObjectSetProperty(fd, plane_id, DRM_MODE_OBJECT_PLANE, damage_id, blob);
        usleep(5000);
    }
    return 0;
}
