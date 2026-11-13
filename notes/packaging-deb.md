# 把 /opt/kde6 打成 .deb + meta 包（方案，2026-11-05）

用户要求：编译好后提供一堆对应 .deb，用户 `dpkg -i` 即可，而不必自己编译。

## 1. 包拆分原则

按**上游模块**拆，一个模块一个包，方便单独升级/卸载；再加一个 meta 包。

命名：`kde6-mtgpu-<module>`，版本统一 `6.8.2-mtgpu1`（Qt/KF6 用各自版本）。

建议的包集合（核心）：

* `kde6-mtgpu-qtbase`、`kde6-mtgpu-qtdeclarative`、`kde6-mtgpu-qtwayland`、
  `kde6-mtgpu-qtsvg`、`kde6-mtgpu-qt5compat`、`kde6-mtgpu-qttools`、
  `kde6-mtgpu-qttranslations`、`kde6-mtgpu-qtimageformats`、
  `kde6-mtgpu-qtpositioning`、`kde6-mtgpu-qtlocation`、
  `kde6-mtgpu-qtmultimedia`、`kde6-mtgpu-qtspeech`
* `kde6-mtgpu-ecm`、`kde6-mtgpu-plasma-wayland-protocols`、`kde6-mtgpu-polkit-qt`
* `kde6-mtgpu-kf6-<framework>`（74 个；或按依赖组再合并，如 kf6-core、kf6-kio、kf6-plasma）
* `kde6-mtgpu-kwin`、`kde6-mtgpu-plasma-workspace`、`kde6-mtgpu-plasma-desktop`、
  `kde6-mtgpu-kscreen`、`kde6-mtgpu-libkscreen`、`kde6-mtgpu-kscreenlocker`、
  `kde6-mtgpu-kdecoration`、`kde6-mtgpu-breeze`、`kde6-mtgpu-systemsettings`、
  `kde6-mtgpu-plasma-integration`、`kde6-mtgpu-layer-shell-qt`、
  `kde6-mtgpu-kglobalacceld`、`kde6-mtgpu-kpipewire`、`kde6-mtgpu-powerdevil`、
  `kde6-mtgpu-polkit-kde-agent`、`kde6-mtgpu-kactivitymanagerd`、
  `kde6-mtgpu-libksysguard`、`kde6-mtgpu-ksystemstats`、
  `kde6-mtgpu-kirigami-addons`、`kde6-mtgpu-qcoro`、`kde6-mtgpu-union`、
  `kde6-mtgpu-cxx-rust-cssparser`、`kde6-mtgpu-corrosion`、
  `kde6-mtgpu-vulkan-headers`、`kde6-mtgpu-cmake`
* 会话集成：`kde6-mtgpu-session`（放 `/usr/share/wayland-sessions/plasma6-kde6.desktop`、
  env 文件、`/usr/lib/systemd/user` 和 D-Bus/polkit 的 symlink，postinst 创建）
* meta：`kde6-mtgpu`（`Depends:` 上面全部）

## 1b. 已实现（2026-11-13）

`tools/make-debs.sh` 现在会额外产出 **`kde6-mtgpu-session`**：装
`/usr/share/wayland-sessions/plasma6-kde6.desktop` 与
`/usr/share/mtgpu-kde/kde6-integration-symlinks.sh`，postinst 建立
systemd user unit / polkit / dbus 软链，prerm 删除；meta 包依赖它。
安装入口统一用 `tools/install-kde6-mtgpu.sh`（含依赖检查、KDE5 污染检测、安装后验证）。

## 2. 生成方式

不要用 `checkinstall`（会把整个前缀塞进一个包）。用 **CMake install manifest** 分文件：

```sh
# 每个模块构建目录里都有 install_manifest.txt
DESTDIR=/tmp/stage/<pkg> cmake --install <build-dir>   # 或用 manifest 过滤
```

更稳的做法：构建时保留每个模块的 `install_manifest.txt`，按模块把文件列表 stage 到
`/tmp/kde6-debs/<pkg>/`，再补 `DEBIAN/control`、`postinst`、`prerm`，`dpkg-deb --build`。

`control` 依赖：

* 我们的包之间用精确版本 `= 6.8.2-mtgpu1`；
* 系统依赖用 `dpkg-shlibdeps` 对 stage 里的 ELF 跑一遍，再映射到 Ubuntu 包名；
* 对 MTT 运行时（`mtgpu`/`mtdisp`/MUSA）只写 `Recommends` 或文档说明，**不要**让 apt 去动厂商包；
* `Architecture: arm64`，`Section: kde`，`Priority: optional`。

## 3. 安装前缀与冲突

* 所有文件仍在 `/opt/kde6`，**不碰 /usr 的库**；只有会话桌面文件、D-Bus/polkit/系统 systemd
  的 symlink 在 `/usr`，由 `kde6-mtgpu-session` 的 postinst 创建（prerm 删除）。
* `postinst` 里不要跑 `ldconfig`（/opt 不加入 ld.so.conf），继续靠 `env.sh` 的
  `LD_LIBRARY_PATH`；否则可能影响系统其他程序。
* 卸载：`dpkg -r kde6-mtgpu` 删 meta 不会删依赖包；用户可 `apt autoremove` 或手动 purge。

## 4. 发布

* GitHub Releases：每个 `.deb` 远小于 2 GB 上限；同时上传 `Packages.gz`/`Release`，
  用户也可以直接 `dpkg -i *.deb`。
* 提供 `SHA256SUMS` + GPG 签名（`gpg --detach-sign`），以及安装脚本
  `install-kde6-mtgpu.sh`（检查 Ubuntu 24.04/arm64、MTT 驱动、可用空间）。
* 带宽：GitHub Releases 对几百次下载没问题，但国内慢；建议同时镜像到阿里云 OSS/R2，
  或提供 BT/网盘。源码与补丁必须一起提供（GPL/LGPL 要求）。
* 版本策略：`6.8.2-mtgpu1`，修 bug 递增 `mtgpu2`；记录 `debian/changelog`。

## 5. 注意

* 这套二进制依赖构建机的 **glibc 2.39 + libstdc++ 15**（Ubuntu 24.04 + GCC 15）。
  目标机也必须是 noble/ARM64，并有可用的 MTT 用户态驱动；否则需要一并打包
  `libstdc++`/`libgcc` 或改为静态。
* Qt/KF6 的插件路径靠 `env.sh`，包本身不改系统环境；会话桌面文件的 `Exec` 指向
  `/opt/kde6/bin/plasma6-session`。
* 如果以后为了让 `.deb` 匹配特定 KWin 行为而 patch，必须带 patch 说明，
  并在 GitHub fork 同步源码。
