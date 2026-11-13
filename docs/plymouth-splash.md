# Plymouth 启动画面（aibook 主题）

目标：固件 logo 之后立刻显示与 KDE ksplash 一致的兔头动画，中间不出现文本控制台。

主题文件在 [tools/plymouth-aibook](../tools/plymouth-aibook)：

| 文件 | 作用 |
|---|---|
| `aibook.plymouth` | `ModuleName=script`，指向 `aibook.script` |
| `aibook.script` | 灰色兔头 + 四个彩色象限按相位正弦淡入淡出（2.8s 一循环） |
| `gen-assets.sh` | 从 ksplash 的 `org.aibook.splash` 素材生成 360/720 两套 PNG |
| `hook-plymouth-aibook` | initramfs hook：把主题与 `script.so` 打进 initramfs |

安装：[tools/install-plymouth-aibook.sh](../tools/install-plymouth-aibook.sh)（幂等，最后自动 `update-initramfs -u`）。

## 必须的内核参数

```
splash plymouth.ignore-serial-consoles
```

- `splash`：让 initramfs 的 `init-premount/plymouth` 启动 plymouthd；
- `plymouth.ignore-serial-consoles`：本机固件通过 ACPI **SPCR** 声明了串口控制台
  （`ACPI: SPCR: console: uart,mmio32,0x47000,115200`，内核因此启用 `ttyS0`）。
  不加这个参数时，Plymouth 会判定"存在串口控制台"，**强制使用 `details` 文本插件**，
  于是启动画面变成 systemd 日志（日志原文：`serial consoles detected, managing them with details forced`）。

可选（彻底不显示内核/initramfs 阶段的文本）：

```
console=tty3 loglevel=0 systemd.show_status=false rd.systemd.show_status=false vt.global_cursor_default=0
```

## ⛔ 不要打开 `plymouth.debug`

排查时可以临时加 `plymouth.debug`（日志写到 `/var/log/plymouth-debug.log`），但**正式启动必须去掉**：
开启调试后 plymouthd 会接管并转发控制台消息，表现就是启动时先闪一段文本控制台再进主题。

## 为什么素材用 360px 而不是 720px

Plymouth 会按 `ply_guess_device_scale()` 自动开启 HiDPI：分辨率达到阈值时
`device_scale = 2`（源码 `src/libply/ply-utils.c`）。本机面板 2880×1800 命中该逻辑，
因此脚本里的 `Window.GetWidth()` 返回**逻辑宽度 1440**，不是物理 2880。

ksplash 的尺寸是 `min(W/4, H/2)`：逻辑 1440×900 下为 **360 逻辑像素 = 720 物理像素**。
若 Plymouth 主题直接用 720px 素材，就会按逻辑单位绘制成 720 → 物理 1440，也就是"两倍大"。
所以 `aibook.script` 使用 `*-360.png`；`gen-assets.sh` 同时生成 720 版本，供 `device_scale=1` 的场景使用。

## 动画为什么需要 `SetRefreshRate`

Plymouth 的 `script` 插件默认不会周期性重绘，`Plymouth.SetRefreshFunction` 只在启动进度变化时被调用，
表现为"主题是静态的"。必须显式设置：

```
Plymouth.SetRefreshRate(30);
Plymouth.SetRefreshFunction(refresh_callback);
```

随后在回调里按 30Hz 推进相位（`2π / (2.8s × 30)` ≈ 0.0748）并更新四个象限的 `SetOpacity`，
动画才真正连续。

## 已知限制

- Plymouth 的 DRM renderer 在本机 `mtgpu` 驱动上会先报一次
  `query_device: Could not get card resources`，但仍能建出 2880×1800 的 head 并上屏
  （日志中随后可见 `Creating 2880x1800 renderer head` / `Setting scan out buffer`）。
  若某次启动真的退回 `frame-buffer` 渲染器，splash 会推迟到 `/dev/fb0` 就绪（约 10s），
  期间会看到文本控制台。把 `mtgpu` 加进 `/etc/initramfs-tools/modules` 可让它更早稳定。
- 主题只有静态兔头 + 四角彩色循环，没有 ksplash 的进度反馈；Plymouth 退出后由 ksplash 接上同一动画。
