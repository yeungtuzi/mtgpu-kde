# EGL 平台能力探针

厂商反馈"EGL 是支持 Wayland 的"。我们在这里记录**实测结果与复现方法**，便于一起定位。

## 结论（M1000 / MTT 驱动，2026-11-09）

| EGL 平台 | 结果 |
|---|---|
| `EGL_PLATFORM_WAYLAND_KHR` | **`no EGL display`**（`eglGetPlatformDisplayEXT` 返回 `EGL_NO_DISPLAY`） |
| `EGL_PLATFORM_SURFACELESS_MESA` | OK，vendor=`MTT Mesa Client`，apis=`OpenGL OpenGL_ES` |
| `EGL_PLATFORM_GBM_KHR` | OK，vendor=`MTT Mesa Client`，apis=`OpenGL OpenGL_ES` |
| `EGL_PLATFORM_DEVICE_EXT` | `no display`（0x300c） |
| Mesa(llvmpipe) `EGL_PLATFORM_WAYLAND_KHR` | OK（软件渲染），`GBM` 反而 init 失败 |

扩展支持（GBM 平台）：

```
EGL_MESA_image_dma_buf_export   yes
EGL_EXT_image_dma_buf_import    yes
EGL_KHR_surfaceless_context     yes
EGL_KHR_create_context          yes
```

## 复现

```sh
# 1) Wayland 平台是否可用
gcc -O1 -o egl-wayland-probe egl-wayland-probe.c $(pkg-config --cflags --libs wayland-client egl) -lEGL
XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 \
  __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/00_mtgpu.json ./egl-wayland-probe

# 2) 各平台对比
gcc -O1 -o egl-platform-probe egl-platform-probe.c -lEGL -lgbm
__EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/00_mtgpu.json ./egl-platform-probe

# 3) 扩展能力
gcc -O1 -o egl-ext-probe egl-ext-probe.c -lEGL -lgbm
__EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/00_mtgpu.json ./egl-ext-probe
```

`00_mtgpu.json` 指向 `libEGL_mtgpu.so.0`；`50_mesa.json` 是系统 Mesa。

## 影响

* Chromium 走 ANGLE（GBM/surfaceless 初始化 GLES，Ozone Wayland 用 dmabuf 呈现），所以**不受影响**，HDR/EDR 正常；
* mpv 的 `--gpu-context=wayland` 必须用 `EGL_PLATFORM_WAYLAND`，因此拿不到 MTT 的 EGL，退回 Mesa 软件渲染后被 libplacebo 拒绝；
* 修复 `EGL_PLATFORM_WAYLAND_KHR` 后，mpv 不需要改代码即可使用 MTT 的 GLES 出画（HDR 走 `wp_color_management_v1` 直通 KWin）。

如果你们的实现路径不是 `eglGetPlatformDisplayEXT`（例如只支持 EGL 1.5 的 `eglGetPlatformDisplay`），请告知，我们改探针再测。
