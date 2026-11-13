# 中文输入法：应用层 fcitx5（2026-11-13）

## 症状

在 KWin 的 Wayland 输入法路径（`kwinrc [Wayland] InputMethod=` 指向 fcitx5）下：

* 中文能输入，但 **Ctrl / Shift 被吞**：`Ctrl+C` 变成 `c`，`Shift+字母` 不大写；
* 切到英文状态后，`Shift+数字` 仍被翻译成中文标点（fcitx5 的 punctuation 插件在 inactive 状态也生效）；
* 本质：KWin 用 `zwp_input_method_v1` 把整块键盘托管给 fcitx5，fcitx5 必须把未处理的键**重新注入**；
  fcitx5 5.1.7 的 waylandim 在重放修饰键状态时有缺陷，补发的 Shift/Ctrl 到不了应用。
  这是协议路径问题，不是热键配置问题——把热键改成 `F9`、`Super+space` 都不能根治。

## 方案：改用应用层 IM

Qt / GTK 各自加载输入法模块，直接和 fcitx5 走 DBus，**不经过合成器的输入法转发**：

* Qt 应用：`fcitx5-qt` 的 `platforminputcontext` 插件（必须针对 `/opt/kde6` 的 Qt 6.11 编译，
  系统 Qt 6.4 的 `libfcitx5platforminputcontextplugin.so` 无法被 6.11 应用加载）；
* GTK 应用：系统的 `fcitx5-frontend-gtk3/4`（已在系统中安装）；
* KWin：`[Wayland] InputMethod=` 置空，不再托管键盘。

这样 Shift/Ctrl 由应用直接收到；单按 Shift 做切换也恢复正常（fcitx5 的"延迟判定 + 补发"在应用事件循环里工作正常）。

## 构建 fcitx5-qt 插件

系统包 `libfcitx5-qt6-1` 是给 Qt 6.4 用的，不能用于 `/opt/kde6`。从源码编：

```bash
sudo apt-get install -y libfcitx5core-dev extra-cmake-modules libfmt-dev
curl -L -o fcitx5-qt.tar.gz https://github.com/fcitx/fcitx5-qt/archive/refs/tags/5.1.7.tar.gz
tar xf fcitx5-qt.tar.gz && cd fcitx5-qt-5.1.7
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/opt/kde6 \
  -DCMAKE_PREFIX_PATH=/opt/kde6 \
  -DENABLE_QT5=OFF -DENABLE_QT6=ON -DENABLE_X11=OFF \
  -DENABLE_QT6_WAYLAND_WORKAROUND=OFF \
  -DBUILD_ONLY_PLUGIN=On
ninja -C build
sudo cp build/qt6/platforminputcontext/libfcitx5platforminputcontextplugin.so \
        /opt/kde6/plugins/platforminputcontexts/
```

### 三个必须处理的坑

1. **`Qt6::GuiPrivate` 目标缺失**
   `/opt/kde6` 的 Qt 安装了私有头文件（`include/QtGui/6.11.3/QtGui/private`），
   但没有 `Qt6GuiPrivateConfig.cmake`，`find_package(Qt6GuiPrivate)` 找不到。
   处理：在 `/opt/kde6/lib/cmake/` 放一个最小 shim，定义 `Qt6::GuiPrivate` 为
   `INTERFACE` 目标，包含头目录并链接 `Qt6::Gui`。
2. **私有头路径**
   `qpa/qplatforminputcontextplugin_p.h` 会 include `QtGui/private/qtguiglobal_p.h`，
   编译时需同时加 `-I/opt/kde6/include/QtGui/6.11.3`、`-I/opt/kde6/include/QtGui/6.11.3/QtGui`、
   `-I/opt/kde6/include/QtGui/6.11.3/QtGui/private`、`-I/opt/kde6/include`。
3. **moc 解析 IID 失败**
   `main.h` 里 `Q_PLUGIN_METADATA(IID QPlatformInputContextFactoryInterface_iid FILE ...)`
   在 moc 下报 `Parse error at "IID"`。改为字面量：
   `IID "org.qt-project.Qt.QPlatformInputContextFactoryInterface.5.1"`。

> 版本要匹配：插件源码版本（5.1.7）与系统 `fcitx5` 核心一致，避免 ABI/接口漂移。

## 会话配置

`~/.config/plasma-workspace/env/10-fcitx-wayland.sh`：

```sh
#!/bin/sh
# 应用层输入法：Qt/GTK 直接与 fcitx5 通信，不经过 KWin 的 Wayland 输入法转发。
export QT_IM_MODULE=fcitx
export GTK_IM_MODULE=fcitx
export XMODIFIERS="@im=fcitx"
```

`~/.config/kwinrc`：

```ini
[Wayland]
InputMethod=
```

fcitx5 自启（`~/.config/autostart/org.fcitx.Fcitx5.desktop`，Exec 不带 `-d`，让 systemd 单元保持 active），
并给生成的 autostart 单元加重启策略：

```ini
# ~/.config/systemd/user/app-org.fcitx.Fcitx5@autostart.service.d/override.conf
[Service]
Restart=on-failure
RestartSec=3
```

fcitx5 热键（`~/.config/fcitx5/config`）：

```ini
[Behavior]
ActiveByDefault=True

[Hotkey]
AllowModifierOnly=True

[Hotkey/TriggerKeys]
0=Shift_L
1=Shift_R
2=Control+space
```

`AllowModifierOnly=True` 才会把"单独按 Shift"识别为切换；fcitx5 的语义是：
按下修饰键先扣住，若超时内无其它键 → 判定为切换；若有其它键 → 判定为组合并把 Shift 补发给应用。

## 验证

```bash
# Kate 进程里应有插件加载（4 个 fcitx 条目）
grep -c fcitx /proc/$(pgrep -x kate | head -1)/maps

# 聚焦输入框后：
fcitx5-remote -n     # 期望 pinyin
fcitx5-remote -q     # 期望 Default
```

实测：中文候选正常；单按 Shift 切中英；Shift+字母大写；Ctrl+C/V 正常。

## 回滚

```bash
rm /opt/kde6/plugins/platforminputcontexts/libfcitx5platforminputcontextplugin.so
# 环境脚本改回 unset QT_IM_MODULE/GTK_IM_MODULE，并恢复 kwinrc 的 InputMethod
# 之后按 "修改 fcitx5 配置后的正确重启方式" 注销重登一次
```
