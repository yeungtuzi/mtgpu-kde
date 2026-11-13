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

## 发布阶段（人工核对）

6. 在**本机先安装**该 deb，重启会话，确认桌面正常（EDR、输入法、窗口装饰）；
7. 若涉及 systemd 单元：确认 `/etc/xdg` 与 `/opt/kde6` 的单元路径一致；
8. 上传后立即 `gh release download` 回读一次，重复步骤 2 的扫描；
9. 版本号必须递增；**已发布资产不可静默替换**，修正要走新版本并撤回旧资产；
10. release notes 写明：改动、验证环境、已知限制、回滚方法。

## 回滚

- 保留上一版 deb 与改动前的 `libkwin.so` 备份（`~/build/kwin-hdr/backup/`）；
- 系统级单元文件改动前 `cp -n` 备份为 `*.mtgpu-bak`。
