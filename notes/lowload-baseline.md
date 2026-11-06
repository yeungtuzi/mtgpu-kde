# 低负载基线（2026-11-05）

> aibook 定位变更：**开发机**，不是生产机。
> 为了让 KDE 移植/编译有一个干净环境，关掉了 Windows VM 和后台服务。

## 已停掉的东西

| 项目 | 操作 | 恢复方式 |
|---|---|---|
| Windows VM（QEMU + viewer） | 已关机 | `sudo winvm start` |
| `display-aware-prioritizer`（AIOS 调度器，nice -10） | stop + disable | `sudo systemctl enable --now display-aware-prioritizer` |
| `memguard`（内存不足时杀最新大进程） | stop + disable | `sudo systemctl enable --now memguard` |
| `mt-update-manager`（更新管理） | stop | `sudo systemctl start mt-update-manager` |
| `benchserver`（我建的基准服务器） | stop + disable | `sudo systemctl enable --now benchserver` |

`winvm-dbus` 保留运行（几乎不耗资源，重开 VM 时要用）。

> ⚠️ **`memguard` 会在内存紧张时杀掉"最新的大进程"**——Plasma 编译时这可能正好是
> 编译器进程。做编译任务时务必保持它关闭，否则会遇到莫名其妙的 `Killed`。

## 关机方式（重要）

`winvm stop` 发的是 ACPI `system_powerdown`，**这台 guest 不响应**
（QMP 命令返回正常，但 Windows 不动）。可靠做法是从 guest 内部关机：

```powershell
# 通过 guest agent
shutdown.exe /s /t 0 /f
```

```sh
# 或者直接跑
python3 /tmp/agent_cli.py run /tmp/q_shutdown.ps1   # 内容是上面那行
```

QEMU 会在 Windows 断电后几秒内退出。

## 基线数据

```
内存:   31 GB 总量，2.6 GB 已用，24 GB 空闲
CPU:    几乎全闲（gnome-shell ~2.8% 是最大项）
进程:   只剩 GNOME 会话 + 系统服务
```

**注意 load average 显示 7 左右是假象**：

```
D  200 vpu-codec0-3      ← MTGPU 的 VPU 编解码内核线程
D  201 vpu-codec0-4
D  202 vpu-read-msg0
D  kworker/u51:2+events_unbound
```

这些线程卡在不可中断睡眠（D 状态）里，**不消耗 CPU**（`top` 显示 100% idle），
只是把 load average 抬高了。重启可以清掉，不用管它。

## 还开着的

| 服务 | 说明 |
|---|---|
| `gdm` + GNOME | 图形会话，约 500 MB 内存；如果完全不需要图形界面可以 `systemctl stop gdm` |
| `winvm-dbus` | 私有 D-Bus |
| `smbd` / `nmbd` / `cups` / `bluetooth` 等 | AIOS 默认服务，未动 |
