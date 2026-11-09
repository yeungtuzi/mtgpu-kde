#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <gbm.h>

static void try_platform(const char *name, EGLenum plat, void *native) {
    PFNEGLGETPLATFORMDISPLAYEXTPROC getpd =
        (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");
    EGLDisplay d = getpd(plat, native, NULL);
    if (d == EGL_NO_DISPLAY) { printf("%-12s: no display (0x%x)\n", name, eglGetError()); return; }
    EGLint maj, min;
    if (!eglInitialize(d, &maj, &min)) { printf("%-12s: init failed (0x%x)\n", name, eglGetError()); return; }
    printf("%-12s: vendor=%s | apis=%s\n", name, eglQueryString(d, EGL_VENDOR), eglQueryString(d, EGL_CLIENT_APIS));
}

int main(void) {
    int fd = open("/dev/dri/renderD128", O_RDWR);
    struct gbm_device *gbm = fd >= 0 ? gbm_create_device(fd) : NULL;
    try_platform("surfaceless", EGL_PLATFORM_SURFACELESS_MESA, NULL);
    try_platform("device", EGL_PLATFORM_DEVICE_EXT, fd >= 0 ? &fd : NULL);
    if (gbm) try_platform("gbm", EGL_PLATFORM_GBM_KHR, gbm);
    return 0;
}
