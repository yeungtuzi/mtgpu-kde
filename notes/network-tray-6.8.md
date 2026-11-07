# Wi-Fi 设置与系统托盘缺失的排查（Plasma 6.8.2）

2026-11-08。症状：系统设置里没有「Wi-Fi 和互联网」，任务栏右下角没有系统托盘。

## 结论

两个独立问题叠在一起：

1. **plasma-nm 从来没有编译成功**，所以既没有 Wi-Fi KCM，也没有
   `org.kde.plasma.networkmanagement` 这个托盘插件——托盘容器本身在，但里面没有网络项。
2. **无线网卡被 rfkill 软屏蔽**（`phy0: Soft blocked: yes`），NetworkManager 的
   Wi-Fi radio 也处于 disabled，即便有 KCM 也扫不到网络。

## 根因链

`~/kde6/build/plasma-nm-6.8.2/` 里只有 `CMakeCache.txt`，没有 `build.ninja`，说明
configure 阶段就失败了。依次补依赖才走通：

1. `Qt6Keychain >= 0.16.0` 缺失（Ubuntu 24.04 只有 0.14.2）→ 源码编译 **qtkeychain 0.16.0**：
   ```bash
   cmake -S . -B build -G Ninja -DCMAKE_INSTALL_PREFIX=/opt/kde6 \
         -DCMAKE_PREFIX_PATH=/opt/kde6 -DCMAKE_BUILD_TYPE=Release \
         -DBUILD_WITH_QT6=ON -DBUILD_TEST_APPLICATION=OFF
   cmake --build build -j$(nproc) && sudo cmake --install build
   ```
2. `KF6ModemManagerQt` 缺失 → 先装 `libmm-glib-dev`（apt，纯构建期依赖），
   再源码编译 **modemmanager-qt 6.31.0** 到 `/opt/kde6`。
3. 重新 configure **plasma-nm 6.8.2**，然后 build + install。
4. 打开无线：
   ```bash
   sudo rfkill unblock wifi
   sudo nmcli radio wifi on
   ```
5. 重启 plasmashell，让新的 applet/KCM 被扫描到：
   ```bash
   systemctl --user restart plasma-plasmashell
   ```

## 坑

* **必须用 `/opt/kde6/bin/cmake`（3.31.12）**。系统自带的 3.28 会被
  `cmake_minimum_required(3.30)` 直接挡下。
* 构建时的 `CMAKE_PREFIX_PATH=/opt/kde6` 不能少，否则会去找 `/usr` 下的 Qt/KF6。
* `kcmshell6 kcm_networkmanagement` 在 SSH 里直接跑会出现**黑窗口**——不是 KCM 坏了，
  是缺 `QML2_IMPORT_PATH=/opt/kde6/qml:/opt/kde6/lib/qml` 等会话环境变量；
  在真实会话里（系统设置 → Wi-Fi 和互联网）一切正常。

## 验证

* 系统设置 → 网络 → **Wi-Fi 和互联网**：能列出网卡、扫到周边 AP
* 任务栏托盘出现网络图标，点击可切换 Wi-Fi
* `nmcli radio all`：`WIFI 已启用`；`nmcli dev status`：`wlp129s0:wifi:disconnected`

## 复现脚本

`tools/build-plasma-nm.sh` 把上面 1–3 步串起来（可重复执行，已装则跳过）。
