# 配置指南（安装后必读）

> ## ⚠️ 警告：试验性支持，尚未进行长期稳定性验证
>
> 本项目的 KDE Plasma 6.8 构建与 EDR **均处于试验阶段**。
> 没有做过长时间连续运行、反复会话切换、休眠唤醒、多显示器插拔等稳定性验证。
> **不要用于生产环境，也不要作为唯一可用的桌面环境。**
> 使用前请确认已掌握 [CONFIG.md](CONFIG.md) 里的回退方法（随时可退回 GNOME）。

---

本文件是 `mtgpu-kde` 的落地配置清单。按顺序做，全部做完再进桌面。

- 目标环境：AIOS / Ubuntu 24.04 ARM64 + 摩尔线程 M1000 + 14" AM-OLED（2880×1800@120Hz, 10-bit）
- KDE 版本：**Plasma 6.8.2**（Qt 6.11.3 / KF6 6.31），隔离前缀 `/opt/kde6`

![工作状态：2880×1800、200% 缩放、119.93Hz、EDR 已启用](screenshots/plasma6-working-2880x1800-edr.jpg)

---

## 1. 安装

见 [README.md](README.md) 的安装章节。deb 包发布在 GitHub Releases：

<https://github.com/yeungtuzi/mtgpu-kde/releases>

```sh
sudo dpkg -i kde6-mtgpu-*.deb
```

装完不要立刻切换会话，先做完第 2 节，否则会以错误的输入法进入桌面。

---

## 2. 输入法：必须用 fcitx5（rime 方案已确认不行）

### 为什么换掉 ibus-rime

早期版本跟随系统默认的 **IBus 1.6.0 + ibus-rime**。在 KDE 会话里这条路很别扭：

- GNOME 会话本身已经有一个 `ibus-daemon --panel disable` 在跑（同一用户）；
- KDE 会话再起一个 `ibus-daemon` 会争用 `~/.config/ibus/bus` 的地址文件，表现为
  **输入法时好时坏、切不出中文、或直接把整个 IBus 弄挂**；
- 绕过办法是给 KDE 会话一个独立的 `IBUS_ADDRESS`（见下），但 `ibus-daemon --address`
  的行为在不同版本间不一致，属于"能跑但一直要伺候"的状态。

**结论（已确认）：KDE 会话必须用 fcitx5，rime 这条路走不通。**
这不是「配置得好不好」的问题——IBus/Rime 与 KDE 会话争用同一份
`~/.config/ibus/bus` 地址文件，是结构性的，调参只能让它多撑一会儿。
直接换 fcitx5。 fcitx5 有自己的 D-Bus 命名空间，
与 GNOME 的 IBus 完全隔离，两个会话可以共存，不需要任何 `IBUS_ADDRESS` 技巧。

### 安装

```sh
sudo apt install fcitx5 \
                 fcitx5-chinese-addons \
                 fcitx5-frontend-qt6 \
                 fcitx5-frontend-gtk3 \
                 fcitx5-frontend-gtk4
```

`fcitx5-chinese-addons` 带拼音；如果想要 Rime 的引擎，装 `fcitx5-rime` 即可
（注意：是 **fcitx5-rime**，不是 ibus-rime）。

### 设为默认

```sh
im-config -n fcitx5
```

### 环境变量

写入 `/opt/kde6/session.env`（会话启动脚本会 source 它）：

```sh
export LANG=zh_CN.UTF-8
export LANGUAGE=zh_CN:en

export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
export SDL_IM_MODULE=fcitx
```

> 如果之前按旧文档写过 `GTK_IM_MODULE=ibus` / `QT_IM_MODULE=ibus` / `XMODIFIERS=@im=ibus`，
> **必须全部改成 fcitx**，否则 Qt/GTK 会去找不存在的 IBus daemon，输入法直接失效。

### 自启

```sh
mkdir -p ~/.config/autostart
cp /usr/share/applications/org.fcitx.Fcitx5.desktop ~/.config/autostart/
```

### 验证

```sh
fcitx5-remote -o        # 打开输入法，应回显 2
fcitx5-diagnose | head -40
```

在 Konsole / KWrite 里按 `Ctrl+Space` 应能切出拼音候选框。

---

## 3. 显示与色彩（EDR）

工作状态参考图（见文首）使用的设置：

| 项 | 值 |
|---|---|
| 分辨率 | 2880×1800 (16:10) |
| 缩放 | 200% |
| 刷新率 | 119.93 Hz |
| 色彩特性文件 | 内建 |
| 色彩准确性 | 性能优先 |
| 扩展动态范围 | 启用 EDR |
| 旧式应用程序(X11) | 由应用程序进行缩放 |

KWin 6.8 内置 EDR，**不需要**给 KWin 打补丁。它会在「有 brightnessDevice + 内屏 +
不支持标准 HDR」时自动置 `Capability::Edr`，并按 HDR 内容的 `maxHdrLuminance`
动态提升 headroom（上限 3×）。

前置条件：powerdevil 能提供 brightness device。若 System Settings 里看不到
"启用 EDR"，检查 powerdevil 的 D-Bus system service 是否已注册到
`/usr/share/dbus-1/system-services`。

硬件 HDR 元数据路径目前被驱动卡住（connector 没有 `HDR_OUTPUT_METADATA` /
`Colorspace`），详见 [notes/hdr-driver-findings.md](notes/hdr-driver-findings.md)。

---

## 4. 已知限制

  根治要么改 KWin（换成 full-rect blob），要么等驱动侧修 `FB_DAMAGE_CLIPS` 的 0 值语义。
- 硬件 HDR 不可用，只有 EDR。
- 全部构建在 `/opt/kde6`，不覆盖系统 `/usr`；但**会话级**配置（`im-config`、
  `~/.config/autostart`）是全局的，切回 GNOME 后 fcitx5 仍会生效。
