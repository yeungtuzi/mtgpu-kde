#include <stdio.h>
#include <wayland-client.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>

int main(void) {
    struct wl_display *wl = wl_display_connect(NULL);
    if (!wl) { puts("no wayland display"); return 1; }
    PFNEGLGETPLATFORMDISPLAYEXTPROC getpd =
        (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");
    EGLDisplay dpy = getpd ? getpd(EGL_PLATFORM_WAYLAND_KHR, wl, NULL)
                          : eglGetDisplay((EGLNativeDisplayType)wl);
    if (dpy == EGL_NO_DISPLAY) { puts("no EGL display"); return 1; }
    EGLint maj, min;
    if (!eglInitialize(dpy, &maj, &min)) { printf("eglInitialize failed 0x%x\n", eglGetError()); return 1; }
    printf("EGL vendor : %s\n", eglQueryString(dpy, EGL_VENDOR));
    printf("EGL version: %s\n", eglQueryString(dpy, EGL_VERSION));
    printf("client APIs: %s\n", eglQueryString(dpy, EGL_CLIENT_APIS));
    printf("extensions : %.200s\n", eglQueryString(dpy, EGL_EXTENSIONS));
    for (int api = 0; api < 2; api++) {
        EGLenum a = api ? EGL_OPENGL_ES_API : EGL_OPENGL_API;
        const char *n = api ? "GLES" : "desktop GL";
        printf("bind %-10s: %s\n", n, eglBindAPI(a) ? "ok" : "FAILED");
    }
    return 0;
}
