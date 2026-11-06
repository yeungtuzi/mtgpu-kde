# KWin 6.8 在 mtgpu 上只扫描左半屏（2026-11-05 未解决）

## 现象

* 物理面板：**EDO EE00QBA62.A**，14" AM-OLED，2880×1800@120Hz，10-bit，EDID 报告
  `Bits per primary color channel: 10`、`Display is continuous frequency`、DSC 4 slices。
* GNOME 46.2（mutter，Wayland + atomic）在同一台机器、同一个 2880×1800@120 模式下**完整显示**。
* KDE Plasma 6.8.2（KWin Wayland）下，物理屏幕**只显示左半边**内容，右半边黑；
  鼠标/光标有时可见、有时撕裂；换成 2560×1600、1920×1200、60Hz 仍然只显示一半。
* 缩放 100% / 160% 都一样；与 HDR/EDR 无关（关闭 `edrPolicy`、清空 ICC 后仍半屏）。

## 关键证据：KWin 的 scanout framebuffer 是完整的

用 kmsgrab 直接抓 DRM primary plane 的 framebuffer：

```sh
sudo ffmpeg -hide_banner -f kmsgrab -i - \
  -vf "hwdownload,format=rgb0" -frames:v 1 /tmp/scan-rgb0.png
```

得到 **2880×1800 的完整桌面**（壁纸、面板、Dock、时钟、鼠标全在）。  
而物理屏幕只显示左半，说明：

1. KWin 的合成/渲染是完整的；
2. 送进 KMS 的 framebuffer 也是完整的；
3. **问题在 KMS → mtdisp → 面板的扫描输出路径**，而不是 KWin 少画了一半。

`/sys/kernel/debug/dri/0/state` 中 primary plane 也是完整的：

```
plane[170]: Layer4
    format=XR24/XB24/AR24 ...（换过多种）
    modifier=0x0
    size=2880x1800
    pitch[0]=11520
    crtc-pos=2880x1800+0+0
    src-pos=2880.000000x1800.000000+0.000000+0.000000
```

## 已试过的变量（均无效）

| 变量 | 结果 |
|---|---|
| 默认（AR24 / AB24） | 半屏 |
| `KWIN_DRM_PREFER_COLOR_DEPTH=24`（强制 8bpc） | 半屏 |
| `KWIN_DRM_PREFER_COLOR_DEPTH=10`（10bpc） | 半屏 |
| 改 KWin 排序：优先无 alpha（XR24/XB24） | 半屏 |
| 改 KWin 排序：优先 8bpc 无 alpha（XR24） | 半屏 |
| `KWIN_DRM_USE_MODIFIERS=0` | 半屏 |
| `KWIN_DRM_NO_DIRECT_SCANOUT=1` | 半屏 |
| `KWIN_DRM_DISABLE_TRIPLE_BUFFERING=1` | 半屏 |
| `KWIN_USE_BUFFER_AGE=0` | 半屏 |
| `KWIN_FORCE_SW_CURSOR=1` | 光标正常一点，画面仍半屏 |
| 2880@120 / 2880@60 / 2560×1600 / 1920×1200 | 都半屏 |
| 关闭 EDR / 清空 ICC | 仍半屏 |

## 对照：GNOME 的 KMS 状态

GNOME 46.2（mutter）运行时的 active plane：

```
format=XR24 (0x34325258), modifier=0x0, size=2880x1800, pitch 11520
crtc mode "2880x1800": 120 749721 2880 ...
dmesg: DSC slices_per_line 4, dsc pclk 252518
```

KWin 运行时的 dmesg 模式设置与 GNOME **完全相同**（同样的 DSC 4 slices、同样 pclk），
但 KWin 的半屏依旧。

## 网上相似问题

* KWin 6.8.2 的格式协商回归（AMD 上 `Unsupported screen format RA24` + 冻结，
  6.8.2-1.1 正常、6.8.2-2.1 异常）：
  <https://discuss.cachyos.org/t/kwin-6-8-2-2-1-causes-amdgpu-unsupported-screen-format-ra24-and-desktop-freezes-6-8-2-1-1-works/38714>
* 同类讨论（KWin 选到驱动“声称支持”但实际不能 scanout 的格式）：
  <https://discuss.kde.org/t/multi-monitor-on-internal-gpu/51191/6>
* KWin direct scanout 规避：`KWIN_DRM_NO_DIRECT_SCANOUT=1`
  <https://wiki.gentoo.org/wiki/Translations:KDE/Troubleshooting/143/en>
* 黑屏 + 光标：<https://bugs.kde.org/show_bug.cgi?id=489149>
* 摩尔线程显示参数（`display=mt` 等）：
  <https://docs.mthreads.com/vgpu/version-2.9.2/vgpu-doc-online/install_guide/>

## 待验证的方向

1. **vanilla KWin 6.8.1**（排除 6.8.2 回归；已下载/开始构建，机器失联中断）。
2. **KWin 6.7.5** 作为可用性兜底（Plasma 6.8 workspace 与旧 KWin 的协议兼容性需实测）。
3. 用 `drm.debug=0x04` / KWin `kwin_drm.debug` 对比 GNOME 与 KWin 的 atomic commit
   （plane 属性、FB_DAMAGE_CLIPS、OUT_FENCE、DSC PPS 等）。
4. 若确认是 mtdisp 对 KWin 的某个 plane/格式组合的 bug，向 KWin + MTT 提最小复现
   （GNOME 正常 / KWin 半屏 / kmsgrab 全幅）。

## 当前状态

* 机器在反复切换 KWin/KMS 模式后失联（ping 不通），需要物理重启后继续。
* 回退路径：把 `/var/lib/AccountsService/users/lf` 的 `Session=` 改回 `ubuntu`，
  `sudo systemctl restart gdm` 即回 GNOME；GNOME 完全未改动。

## 2026-11-05 21:00 新线索：FB_DAMAGE_CLIPS

KWin 在每次 commit 时会给 primary plane 设置 `FB_DAMAGE_CLIPS`（值为 0，即“全帧”）：

```cpp
// src/backends/drm/drm_pipeline.cpp
if (plane->fbDamage.isValid()) {
    commit->addProperty(plane->fbDamage, 0);
}
```

* **保留该属性（0）**：物理屏幕显示左半边桌面，右半边黑。
* **完全移除该属性**（patch 后重编译 KWin 6.8.1）：物理屏幕变成**全屏黑 + 硬件光标**，
  连左半边桌面也没有了。

这说明 `FB_DAMAGE_CLIPS` 是 mtgpu 更新 primary plane 的必要条件；值为 0 时驱动可能把
“全帧 damage”错误地解释成**半宽**，于是只扫描左半边。

**下一实验**：不再用 0，而是用 `drmModeCreatePropertyBlob()` 创建一个覆盖整帧的
`drm_mode_rect{0, 0, width, height}`，把这个 blob 设给 `FB_DAMAGE_CLIPS`。
若驱动按矩形更新，就能同时做到“全宽 + 有内容”。需要在 `DrmPipeline` 里拿到
plane 尺寸和 drm fd，并在 commit 后销毁/缓存 blob。
