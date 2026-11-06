# mtgpu 驱动 HDR 能力实测记录

> 2026-11-05，aibook（AIOS / Ubuntu 24.04 ARM64，内核 7.0.14）
> 工具：`libdrm-tools` 的 `modetest`、`edid-decode`

## 结论先说

| 层面 | 状态 |
|---|---|
| 面板硬件 | ✅ 支持 HDR10（PQ/EOTF、12bpc、507 nits） |
| 驱动 HDR 管线 | ✅ **存在**，但是**私有 DRM 属性**（`HDR`/`EOTF`/`GAMUT_MAP`/`TONE_MAP`） |
| 标准 DRM HDR API | ❌ **没有**（connector 无 `HDR_OUTPUT_METADATA` / `Colorspace`） |
| KWin 能否驱动 | ❌ 不能——KWin 只认标准 `HDR_OUTPUT_METADATA` |
| 硬件色彩管理 | ✅ 标准 `GAMMA_LUT`（size 256），另有私有 `CCM_LNR`/`CCM_NON_LNR`/`DEGAMMA` |

**所以不是"硬件做不了 HDR"，是"驱动用了私有接口，上游合成器不会用"。**
要做 HDR，路径是：搞清私有 blob 格式 → 打补丁的 KWin（或自写合成器）去设这些属性。

## 驱动标识

```
opened device `Moorethreads DRM/KMS Driver` on driver `mtgpu` (version 2.1.0 at 0)
```

模块：`mtgpu`、`mtdisp`（显示）、`mt_ion`、`mdev`

## 连接器（eDP-1）

全部属性只有 5 个：

```
EDID / DPMS / link-status / non-desktop / TILE
```

**没有 `HDR_OUTPUT_METADATA`、没有 `Colorspace`、没有 `max bpc`。**

模式：2880x1800@119.93（preferred）、2880x1800@59.96、2560x1600@60、… 共 13 个。

## CRTC 属性

标准：

```
GAMMA_LUT (blob)   GAMMA_LUT_SIZE = 256
VRR_ENABLED
```

私有（各 pipe 不完全一致）：

```
BLD_EOTF (blob)        ← 输出电光转换函数
BLD_OETF (blob)        ← 输出光电转换函数
BLD_GAMUT_MAP (blob)   ← 色域映射
BLD_DITHER (blob)
DATA_EXTEND / DATA_TRUNC / PANEL_DITHER / DOWN_SAMPLE
DEGAMMA (blob)
CCM_LNR / CCM_NON_LNR  ← 色彩校正矩阵（线性/非线性）
HIST_GET / HIST_ROI / HIST_BLOCK / HIST_PROT / HIST_INFO  ← 直方图
RCD_ENABLE / RCD_BG / RCD_ROI
CC_ROI_PRIMARY / GAMMA_DITHER / BG_COLOR / VDCM
```

**没有 `CTM`**（标准颜色变换矩阵）。

## 平面属性（关键）

```
COLOR_ENCODING: enum  BT.601 YCbCr / BT.709 YCbCr / BT.2020 YCbCr
COLOR_RANGE:    enum  limited / full
HDR:            range 0..1        ← HDR 开关
EOTF:           blob              ← 传输函数
GAMUT_MAP:      blob              ← 色域映射
TONE_MAP:       blob              ← 色调映射
OETF:           blob
DE_MULTIPLY / BLEND_MODE / BLEND_ALPHA / SCALER / UP_SAMPLE / DOWN_SAMPLE
PVRIC_*（帧缓冲压缩）
```

支持的格式：

```
XR12 XB12 RX12 BX12 AR12 AB12 RA12 BA12   ← 疑似 10/12-bit RGB 系列
XR15 XB15 RX15 BX15 AR15 AB15 RA15 BA15
RG16 BG16  XR24 XB24 RX24 BX24 AR24 AB24 RA24 BA24 AR4H AB4H
YV12 YU12 NV12 NV21 NV16 NV61 P010 P210   ← 10-bit YUV
```

## 面板 EDID

```
Manufacturer: EDO   Model: 5160
Native Color Depth: 12 bpc
Native Maximum Luminance (Full Coverage): 507.5 cd/m^2
Native Minimum Luminance: 10.0 cd/m^2
Monitor ranges: 120-120 Hz V, 230-230 kHz H, max dotclock 750 MHz
Supported color space and EOTF combination 1: DCI-P3, BT.2020/SMPTE ST 2084
HDR Static Metadata Data Block:
    Traditional gamma - SDR luminance range
    Supported static metadata descriptors: Static metadata type 1
```

⇒ 面板确实支持 HDR10（PQ），且有静态元数据描述符。

## 如果将来要做 HDR，需要什么

1. **搞清楚私有 blob 的格式**：`EOTF`/`OETF`/`GAMUT_MAP`/`TONE_MAP`/`BLD_*` 这些 blob
   的二进制布局。驱动源码或厂商文档，否则只能反推。
2. **让合成器去设这些属性**：KWin 6 的 HDR 路径写死了标准 `HDR_OUTPUT_METADATA`，
   需要打补丁改走 `mtgpu` 私有属性；或者写一个最小合成器验证链路（ Weston 改一版更现实）。
3. **验证链路**：`HDR=1` + `EOTF` 设为 PQ + 10-bit 扫描输出（`XR12`/`P010`），
   看面板是否真的进 PQ 模式（外部 HDR 信号分析仪或用已知 HDR10 测试图对比电平）。

## 与项目范围的关系

用户 2026-11-05 明确：**HDR 是可选，不是验收项，且不指望厂商支持**。
所以本项目只做色彩管理（`GAMMA_LUT` + colord + ICC），HDR 留作独立课题。
