# SDDM：KDE6 原生登录器（替换 GDM）

2026-11-14 起，aibook 的显示管理器从 GDM 换成**源码编译的 SDDM 0.21.0（Qt6）**，
安装在 `/opt/sddm`，不依赖 Ubuntu 的 `sddm` 包（该包会拉 KDE5 主题依赖，已被 apt pin 封禁）。

## 为什么换

- GDM/greeter 是 GNOME 的 mutter，KDE 会话退出后它会在 mtgpu 上渲染黑屏且无看门狗；
- SDDM 是 KDE 官方 DM，登录界面、autologin、会话选择都按 KDE 习惯设计；
- 可以完全自定义主题，复用 Plymouth 的兔头帧。

## 构建

```bash
# 源码：https://github.com/sddm/sddm/releases/tag/v0.21.0
cmake -S sddm-0.21.0 -B build/sddm-0.21.0 -G Ninja \
  -DCMAKE_INSTALL_PREFIX=/opt/sddm \
  -DCMAKE_PREFIX_PATH=/opt/kde6 \
  -DBUILD_WITH_QT6=ON \
  -DCMAKE_INSTALL_SYSCONFDIR=/etc \
  -DBUILD_MAN_PAGES=OFF
cmake --build build/sddm-0.21.0 -j
sudo cmake --install build/sddm-0.21.0
```

补丁：`patches/sddm-0.21.0-wayland-autologin-fastpath.patch`

- autologin 时跳过 greeter 的 display server（Weston），直接启动会话，
  让 KWin 尽早拿到 DRM，缩短登录黑屏；
- 非 autologin 时仍走正常的 Wayland greeter（Weston kiosk）。

**必须的符号链接**（Qt6 构建只装 `sddm-greeter-qt6`，SDDM 找的是 `sddm-greeter`）：

```bash
sudo ln -sf sddm-greeter-qt6 /opt/sddm/bin/sddm-greeter
```

## 配置

`/etc/sddm.conf.d/10-mtgpu.conf`（模板见 `tools/sddm/10-mtgpu.conf`）：

```ini
[General]
DisplayServer=wayland
EnableHiDPI=true
GreeterEnvironment=QT_SCALE_FACTOR=2

[Wayland]
SessionDir=/usr/share/mtgpu-kde/wayland-sessions
CompositorCommand=weston --shell=kiosk

[Theme]
Current=mtgpu-kde
ThemeDir=/opt/sddm/share/sddm/themes

[Autologin]
Session=plasma6-kde6.desktop
Relogin=false

[X11]
SessionDir=
```

要点：

- `SessionDir` 只指向我们自己的 session 文件，避免列出 GNOME/Ubuntu 残留会话；
- `[X11] SessionDir=` 置空，隐藏 X11 会话列表；
- 主题目录里 **目录必须有 `x` 权限**、文件 `a+r`，否则 greeter（用户 `sddm`）
  会报 `Main.qml: No such file or directory` 并回退到内置主题；
- SDDM 会读取 `/etc/sddm.conf.d/` 下**所有**文件（包括 `.bak`），
  备份配置必须移出该目录，否则会被当成有效配置。

## 主题（mtgpu-kde）

`tools/sddm/theme-mtgpu-kde/`：

- 黑底 + 4 帧兔头循环（700 ms/帧，与 Plymouth 同素材、同节奏）；
- 紧凑登录卡：用户名、密码、会话下拉、登录按钮，无主机名、无描边；
- 右上角时钟，右下角关机/重启/休眠；
- 按 2× 设计，1440×900 逻辑分辨率。

几何对齐（实测像素，2880×1800 屏）：

| 元素 | 尺寸 | 位置 |
|---|---|---|
| Plymouth 兔头（实测 kmsgrab） | 360×360 | 中心 (1440, 900) |
| ksplash 兔头（`min(W/4,H/2)`，720 逻辑） | 720×720 | 中心 |
| SDDM 兔头（`root.width*0.125`，2×） | 360×360 | 中心 |
| 登录卡 | 680×328 物理 | 中心 (1440, 1423.5)，上下间隙 180/213 |

> Plymouth 的 DRM 渲染器在 2880×1800 面板上以 `device_scale=2` 工作，
> 所以 180 px 的帧图实际扫描成 360 px；`tools/plymouth-aibook/gen-frames.py`
> 因此生成 180 px 帧（早期 360 px 帧会被放大成 720 px，偏大）。

## 启动链与黑屏

当前链路：

```
Plymouth（KMS，兔头 4 帧）
  → 事件驱动交接：plymouth-handoff 等 kwin_wayland 进程出现后 quit --retain-splash
  → SDDM（Wayland autologin 快路径）→ KWin → 桌面（ksplash 已 mask）
```

- `plymouth-quit.service` 被 mask，改由 `tools/sddm/plymouth-handoff` 触发；
- `tools/sddm/plymouth-quit-retain-splash.conf` 是保留 drop-in（供回退时使用）；
- 仍有约 **1 秒黑屏**：mtgpu 的 fbdev（`mtgpudrmfb`）在 DRM master 释放时恢复控制台内容，
  KWin 需要 GL 初始化完成后才提交首帧。彻底消除需要 KWin 早期 KMS splash 补丁，
  当前接受该 1 秒；
- 文本控制台保留（`disable_fbdev` 未启用），Ctrl+Alt+F2 可用。

## 回退到 GDM

```bash
sudo ln -sf /usr/lib/systemd/system/gdm3.service /etc/systemd/system/display-manager.service
sudo systemctl enable gdm3
sudo systemctl disable sddm.service plymouth-handoff.service
sudo systemctl restart display-manager
```
