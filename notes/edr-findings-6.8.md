# KWin 6.8 的 EDR 实现（2026-11-05 修正）

> 旧文档 `notes/edr-alternative.md` 的结论"EDR 要打补丁解除 KWin 对 HDR 元数据的依赖"，
> 在 **KWin 6.8** 上已经过时。KWin 6.8 直接内置了 EDR（Apple 式 headroom），
> 不需要 `HDR_OUTPUT_METADATA`，也不需要改驱动。
> 本文记录源码证据与验证方法。

## 1. 源码证据（kwin-6.8.2）

### 1.1 何时启用 EDR

`src/backends/drm/drm_output.cpp` (`DrmOutput::computeCapabilities`)：

```cpp
if (m_state.brightnessDevice && isInternal() && !(capabilities & Capability::HighDynamicRange)) {
    capabilities |= Capability::Edr;
}
```

三个条件：

1. 输出有 brightness device（本机：`/sys/class/backlight/m1000_backlight`，max=400）；
2. 是内屏（eDP-1）；
3. **不支持标准 HDR**（本机 connector 没有 `HDR_OUTPUT_METADATA` → 正好满足）。

⇒ 我们的硬件恰好命中 EDR 路径，而不是 HDR 路径。

### 1.2 headroom 怎么算

`DrmOutput::calculateMaxArtificialHdrHeadroom()`：

```cpp
if (!next.brightnessDevice || !isInternal() ||
    next.edrPolicy == EdrPolicy::Never || !(capabilities() & Capability::Edr))
    return 1.0;

constexpr double relativeLuminanceAtZeroBrightness = 0.04;
constexpr double maxHdrHeadroom = 3.0;
const double maxPossibleHeadroom = (1 + relativeLuminanceAtZeroBrightness)
    / (relativeLuminanceAtZeroBrightness + next.currentBrightness.value_or(next.brightnessSetting));
return std::min(maxPossibleHeadroom, maxHdrHeadroom);
```

即：

```
max_headroom = min(3.0, 1.04 / (0.04 + b))
```

`b` 是用户设置的亮度（0..1）。亮度越低，可用的 EDR headroom 越大；最高 3×。

### 1.3 什么时候真正抬 headroom

`src/compositor.cpp`：

```cpp
const auto desiredHdrHeadroom = output->edrPolicy() == EdrPolicy::Always
    ? primaryView->desiredHdrHeadroom() : 1.0;
desiredArtificalHdrHeadroom = std::clamp(desiredHdrHeadroom, 1.0,
                                         output->maxPossibleArtificialHdrHeadroom());
```

`WorkspaceScene::desiredHdrHeadroom()` 扫描屏幕上每个 item 的
`ColorDescription::maxHdrLuminance()/referenceLuminance()`，取最大值。
也就是**只有屏幕上出现 HDR 内容时**才会抬背光；SDR 桌面保持用户设定的亮度。
headroom 以每秒 0.5 的速率平滑变化，避免闪烁。

### 1.4 每输出的策略

* `BackendOutput::EdrPolicy { Never, Always }`，默认 `Always`；
* 配置写入 `~/.config/kwinoutputconfig.json` 的每个 output 里，键为 `edrPolicy`（`"always"`/`"never"`）；
* KScreen 6.8 的 `kscreenctl` 已支持 `set-edr-policy`，`kscreenctl output ...` 会显示 "Allow EDR"。

## 2. 与"标准 HDR"的差别

| | 标准 HDR | KWin 6.8 EDR |
|---|---|---|
| 需要 connector `HDR_OUTPUT_METADATA` | 是 | **否** |
| 需要 `Colorspace` 切换到 BT2020/PQ | 是 | 否（面板留在 SDR 模式） |
| 显示器进 PQ 模式 | 是 | 否 |
| 高光相对 SDR 白更亮 | 是 | **是**（通过抬背光/浮点合成） |
| 本机可用 | 否（驱动缺属性） | **可以验证** |

## 3. 本机数字（先算一遍，避免期望错）

面板 EDID：峰值 507.5 nits，最小 10 nits；背光设备 max=400（单位未必等于 nits，需实测）。

按 KWin 公式，若 SDR 白设在背光 400 的不同比例：

| 用户亮度 b | SDR 白（按 400 线性估） | max headroom | 峰值（估） |
|---|---|---|---|
| 0.75（300/400） | 300 nit | 1.32× | 396 nit |
| 0.50（200/400） | 200 nit | 1.93× | 386 nit |
| 0.40（160/400） | 160 nit | 2.36× | 378 nit |
| 0.30（120/400） | 120 nit | 3.00×（封顶） | 360 nit |

⇒ **SDR 白定在 300 nit 时只剩 ~1.3× 余量**，EDR 观感不会强；
想要 2× 以上，SDR 白应压到 ~200 nit 或更低。这与"面板 500 nit、SDR 白 300"的直觉不同，
因为 KWin 的 headroom 是按背光比例算的，而背光最大只有 400。

> 注意：没有色度计，以上"nits"只是按背光比例估算；EDID 的 507.5 与 backlight 400
> 的关系需要实测（或查厂商曲线）才能确认。验证阶段以观感和背光读数为准。

## 4. 验证方法（待执行）

1. 起 Plasma 6.8 Wayland 会话（tty3）。
2. `kscreenctl`/`kscreen-doctor -o` 确认 eDP-1 有 EDR/Allow EDR。
3. 记录 `/sys/class/backlight/m1000_backlight/brightness` 基线。
4. 播放一段明确带 HDR 元数据的视频（mpv 的 HDR 片源，或 kwin 自带 HDR 测试图），
   同时观察背光值是否上升、`artificialHdrHeadroom` 是否 >1（可临时加日志或用 debug console）。
5. 对照：把 `edrPolicy` 设为 `never` 再测，背光应不再变化。

## 5. 仍需确认

* mtgpu 的 `m1000_backlight` 是否真的控制面板亮度（还是仅软件模拟）；
* 背光 400 与 EDID 507.5 nits 的换算；
* EDR 抬背光在 OLED 上的功耗/ABL 行为；
* HDR 内容在 KWin 6.8 中是否会以 `maxHdrLuminance > referenceLuminance` 的
  `ColorDescription` 呈现（取决于播放器/协议；本地视频走 `wp-color-management` 或
  KWin 的 HDR 检测）。
