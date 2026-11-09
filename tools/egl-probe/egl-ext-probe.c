#include <stdio.h>
#include <fcntl.h>
#include <string.h>
#include <unistd.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <gbm.h>

int main(void) {
    int fd = open("/dev/dri/renderD128", O_RDWR);
    struct gbm_device *gbm = gbm_create_device(fd);
    PFNEGLGETPLATFORMDISPLAYEXTPROC getpd =
        (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");
    EGLDisplay d = getpd(EGL_PLATFORM_GBM_KHR, gbm, NULL);
    EGLint maj, min;
    if (!eglInitialize(d, &maj, &min)) { printf("init failed\n"); return 1; }
    const char *ext = eglQueryString(d, EGL_EXTENSIONS);
    const char *want[] = {"EGL_MESA_image_dma_buf_export","EGL_EXT_image_dma_buf_import",
                          "EGL_KHR_surfaceless_context","EGL_KHR_create_context","EGL_ANDROID_image_native_buffer", NULL};
    for (int i = 0; want[i]; i++) printf("%-34s %s\n", want[i], strstr(ext, want[i]) ? "yes" : "no");
    printf("GBM: %s | formats: ", gbm_device_get_backend_name(gbm));
    for (int i = 0; i < 40; i++) { uint32_t f = gbm_device_get_format_modifier_plane_count(gbm, 0, 0); (void)f; break; }
    puts("");
    return 0;
}
