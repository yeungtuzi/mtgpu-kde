# 启动速度优化（aibook）

实测：**28.16s → 5.94s**（kernel 3.18s + userspace 2.76s）。

| 阶段 | 优化前 | 优化后 |
|---|---|---|
| kernel | 3.59s | 3.18s |
| userspace（到 multi-user） | 24.57s | 2.76s |
| `graphical.target` | 24.49s | 2.66s |
| ksplash 播完 | ~?（被 20s 计时器拖延） | 开机后 ~11s |

## 1. GDM autologin 固定等 20 秒（最大头）

`plymouth-quit-wait.service` 曾耗时 **21s**。根因是 **GDM 在 autologin 时固定设 20 秒计时器才 quit plymouth**
（[GNOME/gdm #1031](https://gitlab.gnome.org/GNOME/gdm/-/work_items/1031)）。
桌面其实早已就绪（ksplash 约 7s 完成），只是 target 被这个等待拖着。

处置：

```bash
sudo systemctl mask plymouth-quit-wait.service
```

Plymouth 到点仍会自行退出，只是不再阻塞 `multi-user.target`；当前桌面在 Plymouth 释放 DRM 后立即由 ksplash 接管。

## 2. 网络层：ufw → nftables

`ufw.service` 声明 `Before=network-pre.target`，而 `gdm.service` → `systemd-user-sessions.service` →
`network.target` → `network-pre.target`，于是 **ufw 串行拖了 gdm 2.21s**
（`systemd-user-sessions.service` 的 `After=remote-fs.target nss-user-lookup.target network.target home.mount`
是 Ubuntu 为网络账户/远程家目录准备的，本机用不到，但 systemd 排序只增不减，无法用 drop-in 去除）。

处置：用静态 nftables 规则替换 ufw（毫秒级加载，语义不变：默认拒绝入站、放行 22 与局域网 samba/netbios）。

```bash
sudo ufw disable
sudo systemctl disable ufw.service
sudo install -m 644 nftables.conf /etc/nftables.conf
sudo systemctl enable --now nftables.service
```

## 3. 无用的开机服务

| 单元 | 原因 |
|---|---|
| `NetworkManager-wait-online.service` | 曾占 5.97s；网络是静态配置 + NM 自管，不需要等 online |
| `snapd.service` / `snapd.socket` / `snapd.seeded` | `snap list` 为空，未安装任何 snap |
| `cloud-init*.service`（4 个，含 mask） | 容器/VM 用途；`cloud-config.service` 还 `Before=gdm.service` |
| `sssd.service` 等 | 无 `/etc/sssd/sssd.conf`，本地账户用不到 LDAP/AD |

## 4. 内核/控制台

```
quiet splash loglevel=0 systemd.show_status=false rd.systemd.show_status=false
plymouth.ignore-serial-consoles vt.global_cursor_default=0 mitigations=off
```

- 不要加 `plymouth.debug`：会导致启动时闪文本控制台（见 [plymouth-splash.md](plymouth-splash.md)）；
- `mitigations=off` 关闭软件侧信道缓解；ARM 的 CSV2/BHB 是硬件级，无开关。

## 剩余可选

`kdump-tools.service`（~0.48s，无任何 `/var/crash` 记录）、`ubuntu-fan.service`（~0.2s）、
`apport.service`（~0.26s）可再关；kernel 3.18s 主要是硬件/驱动初始化，空间有限。
