# kde6-mtgpu

**KDE Plasma 6.8 在 AIOS（Ubuntu 24.04 / ARM64 / 摩尔线程 M1000）上的移植与色彩管理/EDR 验证。**

目标（按优先级）：

1. **硬性**：全局色彩管理——每个输出能加载各自的 ICC，colord 中有对应 profile，KWin 实际把 LUT/ICC 应用到输出。
2. **硬性**：可用的 Wayland 桌面，在 tty3 独立测试，不改变 GNOME 默认会话，随时可回退。
3. **探索**：HDR 在驱动层被卡死（connector 没有 `HDR_OUTPUT_METADATA`/`Colorspace`）；
   因此改为验证 **Apple 式 EDR**（不需要 HDR 元数据，只要求面板峰值 > SDR 白）。

## 配置指南

**装完先看 [CONFIG.md](CONFIG.md)**：输入法（用 fcitx5，不要用 ibus-rime）、
半屏/黑屏规避、显示与 EDR 设置、回退方法都在里面。

| 工作状态 | 典型故障（半屏） |
|---|---|
| ![](screenshots/plasma6-working-2880x1800-edr.jpg) | ![](screenshots/failure-half-screen.jpg) |

## 关键结论（2026-11-05 修正）

* 上一版交接文档（`HANDOFF.md` 早先内容）说"最新稳定版是 5.27、走路线 C"是**错的**：
  Ubuntu 24.04 的 apt 源里确实只有 Plasma 5.27，但 KDE 最新稳定版是 **Plasma 6.8.x**（6.8.0 于 2026-10-14 发布）。
  本项目按用户要求使用**最新稳定版 6.8.2**，全部从源码构建。
* KWin 6.8 **已经内置 EDR 支持**，不再需要"给 KWin 打补丁解除 HDR 元数据限制"：
  * `drm_output.cpp` 在「有 brightnessDevice + 内屏 + 不支持标准 HDR」时直接置 `Capability::Edr`；
  * `compositor.cpp` 会按屏幕上 HDR 内容的 `maxHdrLuminance/referenceLuminance` 动态提升"人工 HDR headroom"（上限 3×，按亮度余量封顶）；
  * 每个输出有 `edrPolicy`（Always/Never），默认 Always。
  * 见 `notes/edr-findings-6.8.md`。
* 因此本项目不再需要补丁 KWin 来"打开 EDR"；要做的是**构建 6.8、跑起来、用 HDR 内容验证 EDR**。
  若后续为了调参确实要改 KWin，再 fork 上游并同步到 GitHub。

## 构建策略

* **全部源码构建**：Qt 6.11.3 → KDE Frameworks 6.31 → Plasma 6.8.2。
* **隔离前缀 `/opt/kde6`**：不覆盖系统 `/usr` 里的任何文件；KDE 只通过运行时环境变量接入。
* 编译器：**GCC 15.2**（系统已有 `/usr/bin/gcc-15`），`-O2 -march=native -mtune=native -pipe`，ccache 加速。
* 构建工具从源码补齐：CMake 3.31.12（ECM 6.31 要求 ≥3.30）。
* 系统 apt 只安装"构建期依赖"（dev 头文件等），**不升级/降级厂商（MTT）运行时二进制**；
  对 MTT 源里优先级 1001 的 polkit/libinput/pipewire 已做 pin/hold，避免改动。

## 文档

* [HANDOFF.md](HANDOFF.md) —— 环境事实与总览（顶部有 2026-11-05 修正）
* [notes/build-6.8.md](notes/build-6.8.md) —— 从源码构建的完整步骤、路径、日志
* [notes/edr-findings-6.8.md](notes/edr-findings-6.8.md) —— KWin 6.8 的 EDR 实现与验证方法
* [notes/edr-brightness-semantics.md](notes/edr-brightness-semantics.md) —— 物理亮度 / SDR 白 / headroom 的映射设计
* [notes/hdr-driver-findings.md](notes/hdr-driver-findings.md) —— 驱动能力实测（P0，仍有效）
* [notes/troubleshooting-half-screen.md](notes/troubleshooting-half-screen.md) —— KWin 半屏问题的证据与排查
* [CONFIG.md](CONFIG.md) —— 安装后配置清单（fcitx5 / 半屏 / EDR）
* [notes/packaging-deb.md](notes/packaging-deb.md) —— 把 /opt/kde6 打成 .deb + meta 包的方案
* [notes/lowload-baseline.md](notes/lowload-baseline.md) —— 机器低负载基线

当前状态（2026-11-05 20:30）：

* **构建**：Qt 6.11.3、KF6 6.31、Plasma 6.8.2 核心已全部构建并安装到 `/opt/kde6`；
  GDM 可自动登录 `Plasma 6.8 (kde6-mtgpu)` 会话，`plasmashell`/`kwin_wayland`/`powerdevil` 均可启动。
* **ICC**：`kscreenctl eDP-1 set-icc-profile ...` 成功，`kwinoutputconfig.json` 中
  `iccProfilePath` 已持久化；`kscreenctl list-outputs` 显示 ICC profile 已挂到 eDP-1。
* **EDR**：KWin 6.8 的 `Allow EDR: always` 已出现（需要 powerdevil 提供 brightness device；
  已把 powerdevil 的 D-Bus system service 注册到 `/usr/share/dbus-1/system-services`）。
  HDR 内容触发 headroom 的实测尚未完成。
* **阻塞**：KWin 在 mtgpu 上只把 framebuffer 的左半边扫描到面板（kmsgrab 证明 framebuffer 完整，
  GNOME 同模式完整）。详见 `notes/troubleshooting-half-screen.md`。
* **回退**：把 `/var/lib/AccountsService/users/lf` 的 `Session=` 改回 `ubuntu` 并
  `sudo systemctl restart gdm` 即回 GNOME；GNOME 本身未改动。
