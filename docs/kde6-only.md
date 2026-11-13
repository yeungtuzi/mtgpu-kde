# 系统里只保留 KF6/KDE6（全部在 /opt/kde6）

2026-11-13 定：机器预装 GNOME；KDE 是后来源码编译的 KDE6（`/opt/kde6`）。
早期为验证 EDR/亮度曾 `apt install plasma-desktop plasma-workspace ...`，
留下整套 Plasma 5.27 + KF5。这些包会把 `/usr/share/plasma/plasmoids/*`（5.27 版）
塞进 XDG 搜索路径，KDE6 的 plasmashell 扫描到后因版本不兼容，**托盘网络/音频项直接消失**。

## 处置

1. **purge Plasma 5 + 全部 KF5**（`libkf5*`、`kf5*`、`plasma-*`、`kwin-*`、`breeze*`、
   `kde-*`、`kscreen*`、`powerdevil` 等共 ~170 包；purge 前需临时 `apt-mark unhold powerdevil`）。
2. 清理残留：`kio-extras-data` / `ktexteditor-data` / `khotkeys-data`（带 `/usr/share/kservices5`），
   以及空的 `/usr/share/kservices5`、`/usr/share/kservicetypes5`、`/usr/share/plasma`。
3. `/etc/apt/preferences.d/block-plasma5` 锁死这些包（`Pin-Priority: -1`），防止误装回来。
4. EDR 相关：`/usr/share/dbus-1/system-services/org.kde.powerdevil.backlighthelper.service`
   仍指向 `/opt/kde6/lib/libexec/kf6/kauth/backlighthelper`（dpkg-divert 保护 `.pkg` 原名）。

## 系统里只允许"链接/启动脚本"

* `/usr/lib/systemd/user/plasma-*.service` → 软链到 `/opt/kde6/lib/systemd/user/...`
* `/usr/share/wayland-sessions/plasma6-kde6.desktop` → `Exec=/opt/kde6/bin/plasma6-session`
* `/usr/bin` 下不放真二进制（KDE6 相关一律软链到 `/opt/kde6/bin`）

## 用 KDE6 补回被 purge 的功能

| 原 KDE5 包 | KDE6 处理 |
|---|---|
| plasma-nm / plasma-pa | 源码重编进 `/opt/kde6`（applet QML 已编进 `.so`） |
| bluedevil | 源码重编 6.8.2（`org.kde.plasma.bluetooth.so`） |
| kinfocenter | 源码重编 6.8.2；KDE6 里 `kinfocenter` 是 `systemsettings` 的软链 |
| kscreen | KDE6 自带 `kscreen-doctor` |
| fcitx5-config-qt（KF5） | 重编 **fcitx5-qt 5.1.7 (Qt6)** + **fcitx5-configtool 5.1.8 (KF6)** 到 `/opt/kde6`；KCM 安装于 `plugins/plasma/kcms/systemsettings/kcm_fcitx5.so` |
| plasma-desktop/workspace | 不需要（KDE6 本体在 /opt） |

> fcitx5-qt 编译时的两处取舍：`platforminputcontext` 需要 Qt6 private 头、`immodule-probing`
> 需要 `private/qguiapplication_p.h`，本机 Qt 安装未带 private 头，故跳过这两个子目录
> （输入法前端平时用系统 `fcitx5-frontend-*`，不受影响）。

## 可重复脚本

* `tools/kde6-integration-symlinks.sh` —— 把 polkit/dbus/systemd-user/wayland-session 软链接进系统（幂等）；
* `tools/build-kde6-extras.sh` —— 源码重编 bluez-qt(QML)、plasma-nm、plasma-pa、bluedevil、kinfocenter、fcitx5-qt/configtool 到 `/opt/kde6`。

## 备份

`/home/lf/backup/dpkg-before-kde5-purge.txt`、`/home/lf/backup/kde5-purge-list.txt`、
`/home/lf/backup/block-plasma5.pin`。

## 隐藏坑：polkit / D-Bus 策略也必须软链进系统

purge KDE5 时，`/usr/share/polkit-1/actions/` 与 `/usr/share/dbus-1/system.d/` 里
属于 Plasma 5 的 `.policy` / `.conf` 被一并删除。KDE6 的这些文件装在
`/opt/kde6/share/...`，但 **polkitd 和 dbus-daemon 只读系统路径**，结果：

* 托盘亮度滑块消失；
* 亮度 / EDR 失效，日志为
  `Error registering helper DBus service "org.kde.powerdevil.backlighthelper" ... is not allowed to own the service`
  以及 `backlighthelper.brightness failed 8`。

处置（全部软链，符合"系统里只放链接"的原则）：

```bash
for f in /opt/kde6/share/polkit-1/actions/*.policy; do
  b=$(basename "$f"); [ -e "/usr/share/polkit-1/actions/$b" ] || sudo ln -s "$f" "/usr/share/polkit-1/actions/$b"
done
for f in /opt/kde6/share/dbus-1/system.d/*.conf; do
  b=$(basename "$f"); [ -e "/usr/share/dbus-1/system.d/$b" ] || sudo ln -s "$f" "/usr/share/dbus-1/system.d/$b"
done
sudo systemctl reload dbus
systemctl --user restart plasma-powerdevil.service
```

验证：`/sys/class/backlight/m1000_backlight/brightness` 可读写、托盘出现亮度滑块。
