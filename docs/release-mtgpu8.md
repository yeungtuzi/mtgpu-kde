# 6.8.2-mtgpu8 发布验证记录（2026-11-13）

## 产物

11 个 deb：`kde6-mtgpu{,-bin,-include,-lib,-metatypes,-misc,-plugins,-qml,-session,-share,-translations}` + `SHA256SUMS`。
`kde6-mtgpu-session` 为本版新增：wayland session 入口 + postinst 建立
systemd user / polkit / dbus 软链（prerm 清理）。

## chroot 全套安装验证

干净 `debootstrap noble arm64` chroot，**purge 后从零安装**（不是升级路径）：

| 检查 | 结果 |
|---|---|
| `dpkg -l` 状态 | 11 个包全部 `ii` |
| deb 载荷 vs 安装后文件 md5 | 121,781 个文件，**0 差异** |
| `ldd` 全量（`LD_LIBRARY_PATH=/opt/kde6/lib`） | 1,570 个 ELF，**0 not found** |
| `kwin_wayland --version` | `kwin 6.8.2` |
| `plasmashell --version` | `plasmashell 6.8.2` |
| 集成软链 | session / systemd / polkit / dbus 全部 OK |
| 托盘 applet | networkmanagement / volume / bluetooth + `org.kde.bluezqt` QML 全部存在 |
| `plasma6-session` 私有路径 | 0 处 `/home/lf`，日志写入 `$XDG_STATE_HOME/kde6/plasma-session.log` |

## 验证中修复的发布级缺陷

1. `kde6-integration-symlinks.sh` 依赖 `sudo` → postinst 在干净系统（无 sudo）失败；
   改为 root 时直接执行。
2. session 入口 `plasma6-kde6.desktop` 原本只存在于构建机 `/usr/share`，没打进任何包；
   改为 session 包直接生成安装。
3. session 包把 `bluez/pipewire-pulse/libcanberra0` 写成硬 `Depends` → 改为 `Recommends`。
4. `plasma6-session` 日志重定向到 `/home/lf/...` → 改为用户状态目录。

## 运行依赖（重要）

* 目标机需 **AIOS/Ubuntu 24.04 arm64 + MTT 用户态驱动**；
* `/opt/kde6` 的 Qt6 链接 **`libicu70`**（AIOS 基础镜像自带；vanilla noble 只有 libicu74）。
  在没有 libicu70 的系统上会报 `libicuuc.so.70: not found`，需先安装 AIOS 基础包；
* `recommends`：bluez、pipewire-pulse、libcanberra0、fcitx5、xdg-desktop-portal。

## 安装

```sh
./install-kde6-mtgpu.sh --check          # 环境/依赖/Plasma5 污染检查
./install-kde6-mtgpu.sh --debs .         # 安装并建立软链
./purge-plasma5.sh                       # 如检测到 Plasma 5/KF5，先 dry-run 再 --yes
```

回退：注销后在 GDM 选 GNOME；`sudo dpkg -r kde6-mtgpu`。
