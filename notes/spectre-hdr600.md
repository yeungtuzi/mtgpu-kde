# Spectre 原生 HDR600 的 KWin 滚降（2026-11-21）

适用机器：HP Spectre x360 13-aw0xxx，eDP-1（SDC 4K OLED，EDID 峰值 604 nit，
HDR600 认证），CachyOS + Plasma 6.8.3 + KWin 6.8.3，i7-1065G7 / Iris Plus G7。

与 aibook 的区别：aibook 的驱动没有 `HDR_OUTPUT_METADATA`，KWin 判 `Capability::Edr`，
走 EDR 分支（输出本质是 SDR + artificial headroom，KWin 必须 tonemap）；
Spectre 走标准 HDR 分支（output 是 PQ/BT.2020），KWin 默认认为无需压缩、直接透传，
面板收到超过 604 nit 的信号就硬裁。

## 现象

- `hdr-bars.mp4`（100/203/500/1000 nit 四段）在 Chromium 里只有第 1 段偏灰，2/3/4 全白；
- 同一文件在 mpv（`--vo=gpu-next --target-colorspace-hint=yes`）下四段递增，说明链路本身正常；
- 把 KDE 的 `maxPeakBrightnessOverride` 从 600 改到 1000 对 Chromium 完全无效（两次渲染
  结果逐像素相同），因为 Chromium 不读这个通告值；
- `KWIN_DRM_NO_DIRECT_SCANOUT=1` 也无效，说明问题不在 scanout 绕过。

## 诊断（关键）

在 `glshader.cpp::setColorspaceUniforms()` 里临时打印一次每组 `(src_tf,dst_tf)`：

```
src_tf=2 dst_tf=3 maxWhiteLum=200 maxOutputLum=600
srcMaxHdr=200 dstMaxHdr=600 srcRef=200 dstRef=200 intent=0
```

- `src_tf=2` 是 PQ：Chromium 交的确实是 HDR surface（不是 SDR）；
- `intent=0` 是 Perceptual，tonemap 的 intent 条件本来就满足；
- **根因是 `srcMaxHdr=200`**：Chromium 只把 referenceLuminance 当成 HDR 峰值声明，
  KWin 算出 `maxWhiteLum=200 < maxOutputLum=600`，判定"内容没超输出能力"，
  走 clip 分支（clamp 到 200），BT.2390 根本没有机会执行。

## 补丁（`patches/kwin-6.8.3-spectre-hdr600.patch`）

1. `glshader.cpp`：PQ 内容的声明峰值若不高于 reference 的 1.1 倍，按 HDR10 的 1000 nit 处理；
2. `glshader.cpp` + `colormanagement.glsl` + `glshader.h`：把 modified Reinhard 换成
   129 点 BT.2390 EETF LUT（PQ 域，`uniform float tonemapLut[129]`），
   `destinationReferenceLuminance` 继续取 `dst->referenceLuminance()`，即 KDE 的 SDR 白 200；
3. `pointer_input.cpp`：`input()` 判空，修 `syncTabletWithMouse` 在
   `InputRedirection` 构造期间的空指针（openSUSE #1290961，本机每次开机崩 4 次的元凶）。

构建：`tools/build-kwin-spectre-hdr600.sh`。

## 验证结果

| 项 | 结果 |
|---|---|
| 诊断日志 | `maxWhiteLum=999.98 maxOutputLum=600`，走 BT.2390 LUT |
| 肉眼 | 100/203/500/1000 四段全部可分辨（用户确认） |
| 计算映射 | 100→100、203→203、500→≈275、1000→600 nit |
| 中性白 | `dstRef=200`，SDR 灰阶与桌面一致 |
| 开机崩溃 | 本次登录无 KWin coredump（输入补丁生效） |

⚠️ **截图不能用来判断 3/4 段**：`spectacle` 把 HDR 输出 tonemap 到 SDR 200 nit，
任何 >200 nit 的内容都饱和成 255。用截图采样会得到「3、4 段一样白」的错误结论，
必须肉眼看，或者对面板做物理测量。

## 维护

- 已锁 `/etc/pacman.conf` → `IgnorePkg = kwin`；
- 升级整套 Plasma 时必须先解除忽略，升级后用同一补丁重编（增量几分钟），
  否则新 plasma-workspace 可能链到旧 `libkwin.so.6` 的 ABI 不匹配；
- 回滚：`sudo pacman -U /var/cache/pacman/pkg/kwin-6.8.3-1.1-x86_64_v4.pkg.tar.zst`
