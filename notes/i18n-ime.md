# 中文界面与中文输入法（2026-11-05）

> 要求：中文界面 + 中文输入法必须可用。
> 原则：**跟随系统现有输入法**——aibook 当前默认是 **IBus + Rime**，不引入 fcitx5。

## 1. 系统现状（实测）

| 项 | 值 |
|---|---|
| 输入法 | **IBus 1.6.0**（MTT 构建 `1.6.0-1+MTTAIOS260828.1`）+ **Rime**（`ibus-rime`） |
| IBus 组件 | `ibus-data`、`ibus-gtk3`、`ibus-gtk4`、`ibus-wayland`、`ibus-m17n`、`ibus-table*` |
| 用户配置 | `~/.config/environment.d/ibus.conf`：`GTK_IM_MODULE=ibus`、`QT_IM_MODULE=ibus`、`XMODIFIERS=@im=ibus` |
| GNOME 输入源 | `gsettings org.gnome.desktop.input-sources` = `[('ibus','rime')]` |
| Locale | `zh_CN.utf8` 已生成；`~/.pam_environment` 设 `LANG=zh_CN.UTF-8`、`LANGUAGE=zh_CN:en` |
| 中文字体 | **已安装**：Noto Serif/Sans CJK、AR PL UMing、MTT AIOS 字体（霞鹜文楷等） |
| IBus 启动方式 | systemd user units：`org.freedesktop.IBus.session.generic.service`（非 GNOME）、`.GNOME.service` |

## 2. KDE 6 会话里怎么接

### 2.1 环境变量（已写入 `/opt/kde6/session.env`）

```
LANG=zh_CN.UTF-8
LANGUAGE=zh_CN:en
GTK_IM_MODULE=ibus
QT_IM_MODULE=ibus
XMODIFIERS=@im=ibus
SDL_IM_MODULE=ibus   # 建议补上
```

### 2.2 Qt 侧

Qt 6.11.3 在构建时已经带上了 IBus 平台输入上下文插件：

```
/opt/kde6/plugins/platforminputcontexts/libibusplatforminputcontextplugin.so
/opt/kde6/plugins/platforminputcontexts/libcomposeplatforminputcontextplugin.so
```

因此 **不需要** 另建 fcitx5-qt，也不存在"系统 Qt 6.4 插件与 /opt Qt 6.11 ABI 不匹配"的问题。

### 2.3 中文界面（翻译）

KDE 的翻译随各自的源码 tarball 的 `po/` 目录一起发布，构建时由 `ki18n_install()`
用 `msgfmt` 装到：

```
/opt/kde6/share/locale/zh_CN/LC_MESSAGES/*.mo / *.qm
```

已确认 KF6 的部分模块已安装（`ki18n6.mo`、`karchive6_qt.qm` 等）；
Plasma/KWin 的 zh_CN 翻译会在各自构建完成后一并装入。
Qt 自身的 `qt_zh_CN.qm` 由 qttranslations 安装到 `/opt/kde6/translations`。

### 2.4 IBus 启动与隔离（注意）

GNOME 会话里已经有一个 `ibus-daemon --panel disable` 在跑（同一个用户）。
KDE 测试会话用独立的 `dbus-run-session`，如果直接再起一个 ibus-daemon，
两边会争用 `~/.config/ibus/bus` 的地址文件。

**方案**：给 KDE 测试会话一个独立的 IBus 地址，避免动 GNOME 的那个：

```sh
export IBUS_ADDRESS=unix:path=/run/user/1000/ibus-kde6
ibus-daemon -d -x --address="$IBUS_ADDRESS"
```

在 `plasma6-session` 包装脚本里、`startplasma-wayland` 之前执行。
客户端（Qt/GTK 的 ibus 插件）会读 `IBUS_ADDRESS`，因此只连这个 daemon。
离开 KDE 会话时，这个 socket 随会话结束即可，不影响 GNOME。

> 若 `ibus-daemon --address` 行为与预期不符，退路是：
> 用 `ibus-daemon -drx` 临时替换全局 daemon，回 GNOME 前重启 IBus；
> 或在 KDE 会话里 `systemctl --user start org.freedesktop.IBus.session.generic.service`
> （需确认它连到的是 KDE 的 session bus）。

## 3. 验证清单

1. `echo $LANG` → `zh_CN.UTF-8`；`locale` 无警告。
2. 打开 System Settings，界面为中文（或 `plasmashell`/`kwin` 的 `.mo` 存在）。
3. `ibus engine rime` 能切到 Rime；在 Konsole/KWrite 里输入拼音出汉字。
4. 重启会话后输入法仍自动可用（autostart 生效）。

## 4. 待办

- [ ] 在 `plasma6-session` 里加独立 IBus 地址与 `ibus-daemon` 启动
- [ ] 验证 `ibus-wayland` 与 KWin 的 input-method-v1 / text-input-v3 协作
- [ ] 确认 Plasma 的 "Input Method" 托盘/面板行为（可选）
- [ ] 中文界面抽查（KWin 标题、System Settings、Plasma 面板）
