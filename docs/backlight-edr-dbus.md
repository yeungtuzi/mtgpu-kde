# 亮度滑块 / EDR 选项消失（backlighthelper 被系统包覆盖，2026-11-13）

## 症状

某次开机后同时出现：

* KDE 显示设置里 **亮度滑块失效**，Fn 亮度键无效；
* 显示设置里 **EDR 选项消失**；
* `kscreen-doctor -o` 显示：

```
Brightness control: unsupported
Allow EDR: unsupported
```

* `journalctl --user -b | grep powerdevil` 出现：

```
org.kde.powerdevil.backlighthelper.brightness failed 8
```

注意：这不是 EDR 补丁的问题，也不是 libkwin 的问题（换回旧二进制现象不变）。

## 根因

KDE 6 的 PowerDevil 通过 **system D-Bus 服务** `org.kde.powerdevil.backlighthelper`
读写面板背光，再用 KWin 的 `kde_external_brightness_v1` 协议把亮度设备注册给 KWin。
KWin 的 `Capability::Edr` 与 `Capability::BrightnessControl` 都依赖这个亮度设备存在：

```cpp
// src/backends/drm/drm_output.cpp
if (m_state.brightnessDevice && isInternal() && !(capabilities & Capability::HighDynamicRange)) {
    capabilities |= Capability::Edr;
}
```

而系统 D-Bus 服务文件被 **系统自带的 Plasma 5.27 `powerdevil` 包**覆盖成了：

```
/usr/share/dbus-1/system-services/org.kde.powerdevil.backlighthelper.service
  Exec=/usr/lib/kauth/libexec/backlighthelper      ← 5.27 的 helper
```

5.27 的 helper 与本机 MTT 背光设备不兼容（brightness 调用返回 error 8），
PowerDevil 因此注册不了亮度设备 → KWin 既没有 EDR 也没有亮度能力。
`/opt/kde6/share/dbus-1/system-services/` 里其实有正确的 KDE 6 版本，但 system bus 只读 `/usr/share`。

## 修复

把系统服务文件指回 `/opt/kde6`（备份原文件）：

```bash
sudo cp -a /usr/share/dbus-1/system-services/org.kde.powerdevil.backlighthelper.service \
           /usr/share/dbus-1/system-services/org.kde.powerdevil.backlighthelper.service.plasma527.bak
sudo tee /usr/share/dbus-1/system-services/org.kde.powerdevil.backlighthelper.service >/dev/null <<'EOF'
[D-BUS Service]
Name=org.kde.powerdevil.backlighthelper
Exec=/opt/kde6/lib/libexec/kf6/kauth/backlighthelper
User=root
EOF

systemctl --user restart plasma-powerdevil
sleep 5
kscreen-doctor -o | grep -E "Brightness|Allow EDR"
```

期望输出：

```
Brightness control: supported, set to N%
Allow EDR: always
```

## 防止再次被覆盖（必做）

系统 `powerdevil` 包升级/重装会再次改写这个文件。做两层保护：

```bash
# 1) 让包自带的文件写到 *.pkg，原件位置留给我们的版本
sudo dpkg-divert --local --rename \
  --divert /usr/share/dbus-1/system-services/org.kde.powerdevil.backlighthelper.service.pkg \
  --add    /usr/share/dbus-1/system-services/org.kde.powerdevil.backlighthelper.service

# 2) 然后重新写入上面的 [D-BUS Service] 内容（divert 会把旧文件改名，位置会空出来）

# 3) hold 住 powerdevil，避免自动升级
sudo apt-mark hold powerdevil
```

验证：

```bash
dpkg-divert --list | grep backlight
apt-mark showhold | grep -x powerdevil
```

解除（例如确实要升级 powerdevil）：

```bash
sudo apt-mark unhold powerdevil
sudo dpkg-divert --remove /usr/share/dbus-1/system-services/org.kde.powerdevil.backlighthelper.service
```

## 排查要点

* 先看 `kscreen-doctor -o` 的 `Brightness control` 是否为 supported——它比"滑块能不能拖"更直接；
* `journalctl --user -b | grep backlighthelper` 能看到 D-Bus 激活记录与错误；
* 不要用"换 libkwin"来试这个故障：已做过对照实验，换回旧二进制现象不变。
