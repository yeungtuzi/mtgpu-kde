# 发布检查清单（强制）

> 起因：2026-11-13 `mtgpu-kwin-edr 6.8.2-mtgpu4` 的 deb 残留构建树前缀 `/opt/kwin-patched`，
> 其中 `plasma-kwin_wayland.service` 会让用户机器 KWin 以 `203/EXEC` 启动失败。
> 该版本资产已撤回，`mtgpu5` 修正。以下每一条都必须打勾才能上传。

## 打包阶段（脚本自动执行，失败即中止）

1. `dpkg-deb -x` 解包到临时目录；
2. 扫描所有**文本文件**（`*.service` `*.desktop` `*.knsrc` `*.h` `*.cmake` `*.pc` `*.sh`）
   是否包含**构建树前缀**（`/opt/kwin-patched` 等非安装前缀）；
3. 若命中数 > 0 → **中止打包**；
4. 检查 `ExecStart=` 指向的二进制在系统里真实存在；
5. 校验 deb 能正常 `dpkg -i`，`dpkg -L` 文件数与预期一致。
   5b. **必须包含 `libkwin.so.6.8.2`**（多架构路径 `lib/aarch64-linux-gnu/` 要映射回 `lib/`）；
   5c. 二进制 RUNPATH 只能是 `/opt/kde6/...`，不得出现构建树路径；
   5d. 解包后逐文件 md5 与 deb 载荷一致。

## 安装/集成阶段

5e. `kde6-mtgpu-session` 必须存在且 postinst 能建立以下软链：
   `/usr/share/wayland-sessions/plasma6-kde6.desktop`、`/usr/lib/systemd/user/plasma-*`、
   `/usr/share/polkit-1/actions/org.kde.powerdevil.*.policy`、
   `/usr/share/dbus-1/system.d/org.kde.powerdevil.*.conf`；
5f. 缺省安装后运行 `tools/install-kde6-mtgpu.sh --check`，确认依赖警告清单符合预期；
5g. 托盘功能抽查：网络、音量、蓝牙 applet 存在；亮度滑块出现（`backlighthelper` 能注册 D-Bus）。

## 发布阶段（人工核对）

6. 在**本机先安装**该 deb，重启会话，确认桌面正常（EDR、输入法、窗口装饰）；
   6b. 在 chroot 测试根（先装 kde6-mtgpu 基础包）里装一遍，校验 `ldd` 0 个 not found、`kwin_wayland --version` 正常；
7. 若涉及 systemd 单元：确认 `/etc/xdg` 与 `/opt/kde6` 的单元路径一致；
8. 上传后立即 `gh release download` 回读一次，重复步骤 2 的扫描；
9. 版本号必须递增；**已发布资产不可静默替换**，修正要走新版本并撤回旧资产；
10. release notes 写明：改动、验证环境、已知限制、回滚方法。

## 回滚

- 保留上一版 deb 与改动前的 `libkwin.so` 备份（`~/build/kwin-hdr/backup/`）；
- 系统级单元文件改动前 `cp -n` 备份为 `*.mtgpu-bak`。
