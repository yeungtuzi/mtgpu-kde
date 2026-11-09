# EDR 峰值亮度：KWin 6.8.2 硬编码 200 nit（2026-11-09）

## 1. 现象

KDE 里 EDR 已经打开（`edrPolicy=always`，内屏 OLED，EDID 声明 ST2084 + 507 nit），
但 HDR 视频的高光**没有比 SDR 白更亮**，超出白点的部分直接裁掉。

## 2. 根因（源码 + 实测）

`drm_output.cpp::createColorDescription()` 里：

```cpp
double maxAverageLuminance = 200;
double maxLuminance = 200;          // ← 硬编码
...
case ColorProfileSource::EDID:
    if (effectiveHdr) {             // 只有 HDR 分支才读 override/EDID
        maxLuminance = next.maxPeakBrightnessOverride.value_or(edid->desiredMaxLuminance().value_or(800));
    } else {
        // EDR 走这里，maxLuminance 仍是 200
        transferFunction = TransferFunction(gamma22, min*artificialHdrHeadroom, max*artificialHdrHeadroom);
    }
...
ColorDescription{ ..., maxLuminance * next.maxPossibleArtificialHdrHeadroom, ... }
```

EDR 与 HDR 互斥（`Capability::Edr` 只在**没有** `HighDynamicRange` 时授予），
所以 EDR 永远落在 `else` 分支，`maxLuminance` 永远是 200。
`kscreenctl set-max-peak-brightness-override` 因此只对 HDR 模式有效。

用 `tools/edr-probe` 读合成器通告（补丁前，滑条任意位置）：

```
LUMINANCES min=0.01 max=200 reference=200     ← 客户端只看到 200nit 的屏幕
```

客户端（Chrome）按 `max` 做 tone mapping，于是超过 200 的内容全部裁掉。

## 3. 补丁（`patches/kwin-6.8.2-edr-peak-luminance.patch`）

三处改动，都在 `src/backends/drm/drm_output.cpp`：

1. **SDR/EDR 分支也读峰值 override**：`maxLuminance = next.maxPeakBrightnessOverride.value_or(maxLuminance);`
2. **滑条改为软件白点**：`brightnessFactor` 恒取 `currentBrightness/brightnessSetting`，
   不再要求"没有硬件背光设备"。
3. **硬件背光恒定满**：`brightnessDevice->setBrightness(1.0)`，滑条不再动硬件。

应用方式：`./tools/apply-kwin-edr.sh $HOME/kde6/src/kwin-6.8.2`（幂等），再按 `build-core-final.sh` 编译。

## 4. 补丁后实测（eDP-1，maxPeakBrightnessOverride=500）

| 滑条 | LUMINANCES.max | LUMINANCES.reference | 硬件背光 |
|---|---|---|---|
| 100% | 500 | 200 | 400/400 |
| 40% | 500 | 83 | 400/400 |
| 20% | 500 | 44 | 400/400 |

Chrome 播放 4 段 PQ 测试图（100/203/500/1000 nit）的观感：
1 暗、2 略亮、3 明显亮、4 与 3 同色（面板峰值 500 裁切）——符合预期。

测试图生成（10bit HEVC，PQ/BT.2020）：

```sh
ffmpeg -f lavfi -i "color=c=black:s=1920x1080:r=30:d=10,format=yuv420p10le" \
  -vf "geq=lum='if(lt(X,W/4),509,if(lt(X,W/2),573,if(lt(X,3*W/4),657,722)))':cb=512:cr=512" \
  -c:v libx265 -preset ultrafast -pix_fmt yuv420p10le \
  -x265-params "hdr10=1:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:master-display=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1)" \
  -color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc -tag:v hvc1 hdr-bars.mp4
```

（509/573/657/722 是 100/203/500/1000 nit 在 10bit limited-range 下的 PQ 码值。）

## 5. 客户端现状

* **Chrome 157**：可用。`--ozone-platform=wayland`，走 ANGLE（MTT Mesa GLES 3.2），
  通过 `wp_color_management_v1` 拿到 headroom，实测观感正确。
* **mpv 0.42（libplacebo 7.387）**：协议层可用（注册 `wp_color_manager_v1`，
  "Compositor supports setting primary color luminances"），但本机无法出画：
  * Vulkan 路径：MT 驱动的 Wayland WSI 坏——
    `GetPhysicalDeviceSurfaceCapabilities2KHR: VK_ERROR_UNKNOWN`；
  * OpenGL 路径：mpv 的 Wayland 上下文请求 `EGL_PLATFORM_WAYLAND`，而 MTT 的 EGL
    只在 **surfaceless / GBM** 平台可用，Wayland 平台直接 `no EGL display`；
    掉到 Mesa(llvmpipe) 后又因软件栅格化被 libplacebo 拒绝。
    实测（`tools/egl-probe` 思路，`__EGL_VENDOR_LIBRARY_FILENAMES=00_mtgpu.json`）：

    ```
    surfaceless : vendor=MTT Mesa Client | apis=OpenGL OpenGL_ES
    gbm         : vendor=MTT Mesa Client | apis=OpenGL OpenGL_ES
    wayland     : no EGL display
    ```

    Chrome 之所以没事：它走 ANGLE（`gl=egl-angle, angle=opengl`），
    用 GBM/surfaceless 初始化 MTT GLES，再由 Ozone Wayland 用 dmabuf/shm 呈现，
    不需要 `EGL_PLATFORM_WAYLAND`。
  ```sh
  # 强制 MTT EGL 后至少能看到协议注册成功
  __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/00_mtgpu.json \
    mpv --vo=gpu-next --gpu-context=wayland --target-colorspace-hint=yes clip.mp4
  ```

## 6. 对驱动/厂商的需求

1. `VK_KHR_wayland_surface` 可用（surface capabilities/swapchain 不能返回 `VK_ERROR_UNKNOWN`）；
2. EGL 暴露标准 Wayland 平台配置，供 mpv/libplacebo 之类客户端初始化硬件 GL；
3. 原生 HDR 仍需连接器提供 `max bpc`、10bit 扫描格式与 `HDR_OUTPUT_METADATA`。
