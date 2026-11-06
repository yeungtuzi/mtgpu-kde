# 从源码构建 Plasma 6.8.2（2026-11-05）

> 目标：aibook（Ubuntu 24.04 noble / ARM64 / M1000）上构建
> **Qt 6.11.3 + KDE Frameworks 6.31 + Plasma 6.8.2**，安装到隔离前缀 `/opt/kde6`。
> 不覆盖 `/usr` 的任何文件；系统 apt 只用于安装构建期依赖。

## 0. 版本选择

| 组件 | 版本 | 来源 |
|---|---|---|
| Qt | **6.11.3** | download.qt.io（6.11 系列最新 patch；6.12.0 刚发布不选） |
| KDE Frameworks | **6.31.0** | download.kde.org（最新稳定） |
| Plasma | **6.8.2** | download.kde.org（6.8 系列最新 patch） |
| CMake | **3.31.12** | 源码（ECM 6.31 要求 ≥3.30，系统只有 3.28） |
| 编译器 | **GCC 15.2.0**（`gcc-15`/`g++-15`） | 系统已有 |

构建 flags：`-O2 -march=native -mtune=native -pipe`，ccache 开启。

## 1. 路径约定

```
/opt/kde6/                 # 安装前缀（独立，不碰 /usr）
  bin/ lib/ libexec/ share/ include/
/opt/kde6/env.sh           # 构建/运行时环境
~/kde6/src/                # 源码
~/kde6/build/              # 构建目录（每模块一个，.built 标记完成）
~/kde6/logs/               # 构建日志
~/kde6/tarballs/           # 原始 tar.xz
```

`env.sh` 关键变量：

```sh
KDE_PREFIX=/opt/kde6
PATH=/opt/kde6/bin:$PATH
LD_LIBRARY_PATH=/opt/kde6/lib
PKG_CONFIG_PATH=/opt/kde6/lib/pkgconfig:/opt/kde6/share/pkgconfig
CMAKE_PREFIX_PATH=/opt/kde6
QT_PLUGIN_PATH=/opt/kde6/lib/plugins
QML2_IMPORT_PATH=/opt/kde6/lib/qml
XDG_DATA_DIRS=/opt/kde6/share:/usr/local/share:/usr/share
XDG_CONFIG_DIRS=/opt/kde6/etc/xdg:/etc/xdg
```

## 2. 系统侧改动（可回退）

* 仅通过 apt 安装 dev/构建依赖（161 个包，全部来自 Ubuntu/MTT 官方源）。
* **没有**升级/降级任何 MTT 厂商运行时二进制。为避免 MTT 源（priority 1001）把系统包回退，
  做了两类保护：

```
# /etc/apt/preferences.d/90-kde-build-pins
Package: libpolkit-agent-1-0 libpolkit-gobject-1-0 libpolkit-agent-1-dev libpolkit-gobject-1-dev polkitd pkexec policykit-1 gir1.2-polkit-1.0
Pin: version 124-2ubuntu1.24.04.4
Pin-Priority: 1002

Package: libinput10 libinput-bin libinput-dev
Pin: version 1.25.0-1ubuntu3.7
Pin-Priority: 1002
```

```
apt-mark hold libpipewire-0.3-dev libpipewire-0.3-0t64 libspa-0.2-dev \
  libspa-0.2-modules libpipewire-0.3-common libpipewire-0.3-modules \
  libpipewire-0.3-modules-filters libpipewire-0.3-modules-x11 \
  libspa-0.2-bluetooth gstreamer1.0-pipewire pipewire pipewire-bin \
  pipewire-pulse pipewire-alsa pipewire-jack
```

> 原因：MTT 的 `libpipewire-0.3-dev` 升级会连带升级 `meta-mttaios-os-aibook`/`mttagent`
> （1.3 GB，且升级 GNOME/pipewire 等运行时），属于破坏性操作，必须挡住。

回退方法：删除 `/etc/apt/preferences.d/90-kde-build-pins`、`apt-mark unhold ...`，
再按需 `apt purge` 构建依赖；`/opt/kde6` 整个目录删掉即可，不影响系统。

## 3. 构建顺序

1. **Qt 6.11.3**（prefix `/opt/kde6`）
   * qtbase：`configure -prefix /opt/kde6 -release -opensource -confirm-license
     -nomake examples -nomake tests -platform linux-g++ -xcb -xcb-xlib
     -no-feature-libinput`（libinput 系统是 1.25，Qt 6.11 的该特性要 1.29；我们不需要它）
   * 其余模块用 CMake：qtshadertools → qtlanguageserver → qtdeclarative → qtwayland
     → qtsvg → qt5compat → qttools → qttranslations → qtimageformats
2. **extra-cmake-modules 6.31**（ECM）
3. **plasma-wayland-protocols 1.23.0**
4. **polkit-qt-1 0.201.1**（`-DQT_MAJOR_VERSION=6`，否则会构建 Qt5 版本）
5. **KDE Frameworks 6.31**：74 个包，用迭代 configure 脚本自动处理依赖顺序
   （失败的留到下一轮，直到全部构建或不再前进）
6. **Plasma 6.8.2**：核心子集（kwin / plasma-workspace / plasma-desktop / kscreen /
   libkscreen / kscreenlocker / kdecoration / breeze / systemsettings / plasma-integration /
   layer-shell-qt / kglobalacceld / kpipewire / powerdevil / polkit-kde-agent 等）

## 4. 构建脚本

* `~/kde6/build-one.sh <源码目录> [cmake 参数...]`：单模块 CMake + Ninja + install。
* `~/kde6/build-kf6.sh`：KF6 迭代构建（多轮，直到无进展）。
* `~/kde6/build-qt-rest.sh`：Qt 非 qtbase 模块顺序构建。

## 5. 当前进度（2026-11-05 20:30）

| 阶段 | 状态 |
|---|---|
| 系统构建依赖 | ✅ 完成 |
| CMake 3.31.12 | ✅ `/opt/kde6/bin/cmake` |
| Qt 6.11.3（qtbase + qtdeclarative/qtwayland/qtsvg/qt5compat/qttools/qttranslations/qtimageformats/qtpositioning/qtlocation/qtmultimedia/qtspeech/qtshadertools/qtlanguageserver 等 11+ 模块） | ✅ |
| Vulkan-Headers 1.4.363（仅头文件，供 KWin） | ✅ `/opt/kde6/include/vulkan` |
| ECM 6.31 / plasma-wayland-protocols 1.23 / polkit-qt-1 0.201.1 | ✅ |
| KF6 6.31（74 个框架） | ✅ 全部构建 |
| Kirigami Addons 1.16.0 / Corrosion 0.5.2 / cxx-rust-cssparser 1.1.0 / Union 6.8.2 | ✅ |
| QCoro 0.13.0（shared, PIC） | ✅ |
| Plasma 6.8.2 核心（kwin / plasma-workspace / plasma-desktop / kscreen / libkscreen / kscreenlocker / kdecoration / breeze / systemsettings / plasma-integration / layer-shell-qt / kglobalacceld / kpipewire / powerdevil / polkit-kde-agent / kactivitymanagerd / libksysguard / ksystemstats） | ✅ |
| 会话 | ✅ GDM 自动登录 `Plasma 6.8 (kde6-mtgpu)`；`kwin_wayland`、`plasmashell`、`kded6`、`powerdevil` 均运行 |
| ICC | ✅ `kscreenctl` 挂载 ICC 成功并持久化 |
| EDR | ✅ `Allow EDR: always`；HDR 内容 headroom 实测待做 |
| 显示扫描输出 | ✅ 已解决 |

## 6. 会话/系统集成（都是增量、可回退）

* GDM session 文件：`/usr/share/wayland-sessions/plasma6-kde6.desktop`
  （`Exec=/opt/kde6/bin/plasma6-session`，`DesktopNames=KDE`）。
* 自动登录：`/etc/gdm3/custom.conf` 的 `AutomaticLoginEnable=true`、`AutomaticLogin=lf`；
  默认会话由 `/var/lib/AccountsService/users/lf` 的 `Session=plasma6-kde6` 决定。
  回退：`Session=ubuntu` + `sudo systemctl restart gdm`。
* `/opt/kde6/bin/plasma6-session`：source `env.sh`，设置 `XDG_SESSION_TYPE=wayland` 等，
  exec `startplasma-wayland`。
* KDE 的 D-Bus service 需要让会话/系统总线找得到（否则 `plasmashell` 会因
  `kactivitymanagerd` 无法激活而 abort）：
  * `/opt/kde6/share/dbus-1/services/*.service` → `/usr/share/dbus-1/services/`
  * `/opt/kde6/share/dbus-1/system-services/*.service` → `/usr/share/dbus-1/system-services/`
  * `/opt/kde6/share/dbus-1/system.d/*.conf` → `/usr/share/dbus-1/system.d/`
  * `/opt/kde6/share/polkit-1/actions/*.policy` → `/usr/share/polkit-1/actions/`
  * `/opt/kde6/lib/systemd/user/*` → `/usr/lib/systemd/user/`
* `powerdevil` 必须运行，KWin 才会通过 `kde_external_brightness_v1` 拿到 brightness device；
  有了它 `Capability::Edr` 才会出现（`kscreenctl` 显示 `Allow EDR: always`）。
* `env.sh` 里当前保留的实验变量：`KWIN_DRM_PREFER_COLOR_DEPTH=24`、
  `KWIN_FORCE_SW_CURSOR=1`（均为历史排查遗留，可按需移除）。

## 7. 已知坑

* **GCC 15 + Vulkan-Hpp `std::expected`**：KWin 6.8 用结构化绑定解构 `std::expected`
  （libstdc++ 的实现含 anonymous union，C++ 标准不允许），GCC 15 直接报错。
  解决：安装 **Vulkan-Headers 1.4.363**，它改成只有定义 `VULKAN_HPP_USE_STD_EXPECTED`
  时才用 `std::expected`，默认回退到可解构的 `ResultValue`。KWin 配置需加
  `-DVULKAN_INCLUDE_DIR=/opt/kde6/include -DVulkan_INCLUDE_DIR=/opt/kde6/include`。
* **Plasma 6.8 依赖 Union**：`plasma-workspace` 要求 `Union`（CSS 解析），
  而 Union 又依赖 `cxx-rust-cssparser` → Corrosion → Rust。
  * Ubuntu 24.04 的 rustc 1.75 太旧（Cargo.lock v4 / edition2024）→ 用 rustup 装 stable（1.99）。
  * 先构建 Corrosion 0.5.2 到 `/opt/kde6`，再 `cxx-rust-cssparser 1.1.0`，再 `union 6.8.2`。
* **powerdevil 的 D-Bus helper**：默认装在 `/opt/kde6/share/dbus-1/system-services`，
  系统总线不会扫描该目录 → `backlighthelper` 启动失败 → 没有 brightness device → 没有 EDR。
  需要上面的 symlink。
* **plasmashell abort**：`Aborting shell load: The activity manager daemon (kactivitymanagerd) is not running`，
  根因也是 `/opt/kde6/share/dbus-1/services` 不在会话总线搜索路径；symlink 后解决。
* **QCoro 静态库非 PIC**：powerdevil 链接时报 `dangerous relocation`，需
  `-DBUILD_SHARED_LIBS=ON -DCMAKE_POSITION_INDEPENDENT_CODE=ON` 重建 QCoro。
* `tastenbrett` 需要 `libxkbfile-dev`；`plasma-desktop` 需要 `libxkbregistry-dev`。
* `kpipewire` 需要 `libva-dev`；`kwin` 需要 `libxcb-dri3-dev libxcb-present-dev`。
* `prison` 在缺 ZXing 时 configure 失败 → `-DWITH_ZXING=OFF -DWITH_MULTIMEDIA=OFF`。
* `plasma-workspace` 的 `UBUNTU_PACKAGEKIT` 默认 ON，缺 PackageKitQt6 会 fatal →
  `-DUBUNTU_PACKAGEKIT=OFF`。
* KWin 的 KF6 依赖之外还要求 `KNightTime`（knighttime 6.8.2）与 `Union`，都已构建。
* QPainter compositing 在 6.8 已不可用：`KWIN_COMPOSE=Q` 会直接
  `Could not fulfill the requested compositing mode ... Exiting`，不要用它做 fallback。

## 8. 本地 KWin 补丁（未提交上游）

* `src/core/renderdevice.cpp`：Vulkan `std::expected` 兼容（若不用新 Vulkan-Headers 时需要）。
* `src/core/outputlayer.cpp`：优先选择 opaque / 8bpc 格式（历史排查遗留的实验改动）。

## 9. 旧版已知坑

* Qt 6.11 的 `-system-md4c` 需要 `libmd4c-html0`（noble 默认只装 `libmd4c0`）→ 补装。
* ECM 6.31 要求 CMake ≥ 3.30 → 源码构建 CMake 3.31.12 到 `/opt/kde6`。
* MTT 源里的 Qt6 是 6.4.2；必须确保构建时 `CMAKE_PREFIX_PATH=/opt/kde6` 优先，
  否则会误链系统 Qt。
* `/opt/kde6` 下的库不写入 `/etc/ld.so.conf`；运行时靠 `LD_LIBRARY_PATH`/RPATH 接入。
