# 把 aibook 的开机视觉搬到另一台 CachyOS / KDE 6.8 机器

适用：x86_64、CachyOS（Arch 系）、KDE Plasma 6.8.x、4K 屏（3840×2160，1:1 渲染）。
目标是复刻 aibook 的兔头开机链路：**Plymouth → 登录器 → ksplash → 桌面壁纸**。

> 注意：KDE 6.8 的新登录器 **Plasma Login Manager（plasmalogin）** 不是 SDDM。
> 它是 SDDM 的 fork，但前端换成 KWin + Plasma 壁纸插件，**不能加载 `tools/sddm/theme-mtgpu-kde` 那套 QML 主题**。
> 登录屏能定制的是壁纸（`org.kde.image` 在白名单内）。

## 0. 素材位置

| 内容 | 路径 |
|---|---|
| Plymouth 主题（脚本 + 4 帧 480px） | `tools/plymouth-aibook/{aibook.plymouth,aibook.script,frames-480/}` |
| Plymouth 帧生成器（aibook 原尺寸/4K） | `tools/plymouth-aibook/gen-frames.py --size 480` |
| ksplash 主题（4 帧硬切） | `tools/ksplash-aibook/org.aibook.splash/` |
| 壁纸（abstract 风格 / Topography3 换标 / 四色兔头源图） | `tools/wallpapers/` |
| 壁纸生成器 | `tools/wallpapers/gen-wallpapers.py` |

## 1. Plymouth

```bash
# 在目标机上，把仓库里的素材拷到 ~/aibook-theme/plymouth
sudo install -d /usr/share/plymouth/themes/aibook
sudo cp -a ~/aibook-theme/plymouth/. /usr/share/plymouth/themes/aibook/
sudo chown -R root:root /usr/share/plymouth/themes/aibook
sudo cp -a /etc/plymouth/plymouthd.conf /etc/plymouth/plymouthd.conf.bak-mtgpu
sudo plymouth-set-default-theme -R aibook
```

- `-R` 会重建 initramfs（Arch 系用 mkinitcpio，确认 `plymouth` hook 已存在）。
- 4K/1:1 屏用 `frames-480`；2880×1800@2x 的 aibook 用 180px 帧（`gen-frames.py` 默认）。
- 回退：`sudo plymouth-set-default-theme -R cachyos-bootanimation`

## 2. ksplash

```bash
sudo cp -a ~/aibook-theme/org.aibook.splash /usr/share/plasma/look-and-feel/
sudo chown -R root:root /usr/share/plasma/look-and-feel/org.aibook.splash
sudo chmod -R a+rX /usr/share/plasma/look-and-feel/org.aibook.splash

mkdir -p ~/.config
printf '[KSplash]\nTheme=org.aibook.splash\n' > ~/.config/ksplashrc
```

`Splash.qml` 以屏宽 12.5% 居中显示兔头，每 700ms 硬切一帧，与 Plymouth 同节奏。

## 3. 登录器（plasmalogin）

- 不支持 SDDM QML 主题；如需兔头背景，用**系统设置 → 登录屏幕 → 壁纸 → 图像**，
  选 `/usr/share/wallpapers/cachyos-wallpapers/Aibook_Abstract_4K.png`（或任意兔头图）。
- 手动指定插件（可选）：`/etc/plasmalogin.conf` 加

  ```ini
  [Greeter]
  WallpaperPluginId=org.kde.image
  ```

- 已知问题：注销后登录器的 KWin 偶发 `status=11/SEGV`，greeter 随之 ABRT，表现为无法登录。
  恢复：`sudo systemctl restart plasmalogin`（无需重启机器）。

## 4. 壁纸

```bash
sudo install -m 644 ~/aibook-theme/aibook-abstract-4k.png \
  /usr/share/wallpapers/cachyos-wallpapers/Aibook_Abstract_4K.png
sudo install -m 644 ~/aibook-theme/aibook-topography3.jpg \
  /usr/share/wallpapers/cachyos-wallpapers/Aibook_Topography3.jpg
```

在用户会话里应用（需要会话环境）：

```bash
plasma-apply-wallpaperimage /usr/share/wallpapers/cachyos-wallpapers/Aibook_Abstract_4K.png
```

壁纸可重新生成：

```bash
python3 tools/wallpapers/gen-wallpapers.py \
  --out /tmp/out \
  --topography /usr/share/wallpapers/cachyos-wallpapers/Cachy_Topography3.jpg
```

需要 pillow；`--topography` 另需 opencv-python（cv2）。

## 5. 验证清单

- [ ] `plymouth-set-default-theme` 输出 `aibook`
- [ ] `/boot/initramfs*.img` 时间戳已更新
- [ ] 登录后 `cat ~/.config/ksplashrc` 为 `org.aibook.splash`
- [ ] 壁纸列表里能看到 `Aibook_Abstract_4K` / `Aibook_Topography3`
