# 面向 aibook（M1000）的 CachyOS arm64 移植计划

> 状态：**调研报告，未动手**。目标是把"能不能做、要做什么、代价多大"说清楚。
> 机器：aibook / AIOS（Ubuntu 24.04 派生）/ 12×Cortex-A78 / 31 GB / M1000 vGPU。

## 1. 结论摘要

1. **CachyOS 目前没有 arm64 版本**，其上游 Arch Linux 官方也不支持 arm64；可用的底座是
   **Arch Linux ARM (ALARM)** 或 2026 年启动的 **Arch Linux Ports（aarch64）**。
2. 真正的难点不是"编软件"，而是**闭源内核 + 闭源 GPU 驱动**带来的硬约束：
   内核 7.0.14 是 MTT 定制版，`mtgpu`/`mtdisp`/`mt_ion` 等模块与固件只以该内核的二进制形式提供。
   ⇒ 移植的实质是**"厂商内核 + 新用户空间"**，不是换内核。
3. 因此 CachyOS 的招牌特性大部分**无法照搬**：
   - BORE 调度器 / sched-ext：需要内核源码与补丁，**放弃**；
   - x86-64-v3/v4 优化仓库：arm64 上无意义，等价物是 `-mcpu=cortex-a78+nocrypto` 的**全量重编**；
   - cachyos-kernel-manager / 自定义内核：**不适用**。
4. 可行的是"**CachyOS 风格的用户空间发行版**"：pacman + ALARM/Ports 仓库 + cachyos-settings 类调优
   + 我们已验证可源码构建的 KDE 6.8 与 Chromium。
5. 工作量：**单人 2–3 个月**可做出"本机可日常使用的镜像"；要成为**可维护的发行版**（滚动更新、
   CI、安装器、签名仓库）需 **3–6 人月以上**，且强依赖厂商对内核 ABI 的承诺。

## 2. 本机硬约束（实测）

| 项 | 现状 | 对移植的影响 |
|---|---|---|
| 内核 | `7.0.14`（MTT 定制） | 必须原样保留；不能用 Arch 通用内核 |
| 内核头文件 | `/usr/src/linux-headers-7.0.14` 存在，但 `/lib/modules/7.0.14/build` 符号链接缺失 | 可编第三方 DKMS 模块，但需修符号链接 |
| GPU 模块 | `mtgpu`、`mtdisp`、`mt_ion`、`drm_dma_helper`、`drm_display_helper`（闭源二进制） | 与内核 ABI 绑定，**无法重编** |
| 图形用户态 | MTT Mesa（`libEGL_mtgpu.so.0`，EGL/GLES）；Vulkan 仅有 Mesa 各 ICD，**无 MTT Vulkan ICD** | Wayland 合成器只能走 GLES；Vulkan 应用受限 |
| 启动 | GRUB + EFI | arm64 需 `grub-install --target=arm64-efi` |
| 包管理 | dpkg，3137 个包，其中 127 个 MTT 包（控制面板、主题、agent 等） | 需把这些"厂商层"重新打包成 pacman 包或在镜像中保留 |
| 网络 | 有线网卡偶发掉线，Wi-Fi 可用；Google CDN 需代理 | 影响 CI/镜像分发 |

## 3. 上游现状（调研）

- CachyOS 官方论坛明确：**暂无 ARM64 计划**，因为其上游 Arch Linux 不支持 ARM
  ([讨论](https://discuss.cachyos.org/t/arm-future-for-cachyos/727/3)、[再次请求](https://discuss.cachyos.org/t/please-make-an-arm64-version/28549/9))。
- 可用的 arm64 底座：
  - **Arch Linux ARM (ALARM)**：成熟、有 aarch64 仓库，但偏向开发板/树莓派；
  - **Arch Linux Ports (aarch64)**：2026 年启动的准官方移植，安装器"bootloader 支持"仍是 open item。
- CachyOS 的内核特性（BORE、sched-ext）与优化仓库（x86-64-v3/v4）
  见 [CachyOS wiki: kernel](https://github.com/CachyOS/wiki/blob/318ffe4dd72f9f9de1a4c63578dedf242db9f7a0/src/content/docs/features/kernel.md)，
  均依赖**可修改的内核**或 **x86 指令集基线**，本机都不成立。

## 4. 方案选项

### 方案 A：AIOS 之上叠加 "CachyOS 用户层"（MVP，推荐先做）
- 保留现有内核/驱动/固件与 MTT 包不动；
- 用 pacman 在独立 prefix（如 `/opt/cachy`）或容器（systemd-nspawn）里装 ALARM 用户空间；
- 验证桌面/浏览器/多媒体可用后，再决定是否做成整机镜像。
- 优点：风险最低、可回滚（现有系统不动）；缺点：不是真正的发行版。

### 方案 B：基于 ALARM/Ports 重建整机 rootfs，沿用厂商内核
- 用 ALARM aarch64 bootstrap 建 rootfs；把 MTT 的内核、initramfs、模块、固件、GPU 用户态库、
  127 个厂商包**原样迁移**并打成 pacman 包（`mtt-kernel`、`mtgpu-driver`、`mtt-settings`…）；
- pacman 里 `IgnorePkg` 锁定内核相关包，防止滚动更新破坏驱动；
- 安装器用 archiso(aarch64) 定制，预置上述包。
- 优点：真正的"自己的发行版"；缺点：工作量大，需长期跟进厂商更新。

### 方案 C：从零构建（LFS/Buildroot 风格）
- 不推荐：CachyOS 的价值在包管理与生态，自建工具链收益极低（我们已经在 Chromium 上体会过一次）。

## 5. 工作分解（WBS）

| # | 工作包 | 主要产出 | 估算（人日） |
|---|---|---|---|
| 1 | 底座选型与 bootstrap | ALARM/Ports aarch64 rootfs 可 chroot 启动 | 3–5 |
| 2 | 厂商层打包 | `mtt-kernel`（内核+模块+固件）、`mtgpu-userspace`（EGL/GLES 库、`00_mtgpu.json`）、`mtt-packages`（127 个 deb 转 pacman） | 10–15 |
| 3 | 内核/驱动集成 | initramfs 生成（dracut/mkinitcpio）、`/lib/modules/.../build` 修复、模块签名/加载顺序、DRM 权限 | 5–8 |
| 4 | 图形栈 | MTT Mesa 与系统 Mesa 共存（EGL vendor 选择）、Wayland 合成器（KWin）GLES 路径、屏幕亮度/EDR | 5–10 |
| 5 | 多媒体 | GStreamer/FFmpeg 硬解（HEVC/H.264）、VA-API 或厂商路径、音频 | 3–5 |
| 6 | 桌面 | KDE Plasma 6.8（源码构建已验证）+ SDDM + 输入法 + 主题 | 5–8 |
| 7 | CachyOS 风格调优 | `cachyos-settings` 类 sysctl/zram/udev、`ananicy-cpp`、镜像排序；**替代 BORE**：`-mcpu=cortex-a78+nocrypto` 全量重编 | 5–10 |
| 8 | 包仓库与 CI | 本机 12 核做 build farm、签名、pacman repo、增量构建 | 8–12 |
| 9 | 安装镜像 | archiso aarch64 定制、分区/GRUB arm64-efi、首启脚本 | 8–12 |
| 10 | 测试与回归 | GPU/显示/EDR、Wi-Fi/BT、电源/风扇、睡眠、外设、Steam(FEX)、Chromium | 10–15 |

合计：**约 62–100 人日**（单人 3–5 个月），不含长期维护。

## 6. 关键技术难点与对策

1. **内核 ABI 锁定**：厂商模块只对 7.0.14 有效。对策：内核包固定版本 + `IgnorePkg`，
   并提供"厂商内核更新 → 重建镜像"的流程；向厂商索取 **ABI 稳定性承诺**。
2. **pacman 与厂商包冲突**：MTT 的 127 个 deb 需转 pacman（`debtap` 或手写 PKGBUILD），
   文件冲突用 `backup=`/`conflicts=` 明确声明。
3. **EGL 供应商选择**：`__EGL_VENDOR_LIBRARY_FILENAMES` 已证明可强制走 MTT；
   需在镜像里固化 udev/环境变量，避免误用 Mesa 软件渲染。
4. **无 Vulkan**：MTT 未提供 Vulkan ICD ⇒ KWin 的 Vulkan 后端、部分游戏/浏览器 GPU 路径不可用；
   需以 GLES 为主，并在文档中标注限制。
5. **CachyOS 特性不可移植**：BORE/sched-ext 需内核源码；优化仓库需 x86 基线。
   替代：`-mcpu=cortex-a78+nocrypto`、`-O3 -flto`、PGO（Chromium 已可 `chrome_pgo_phase`）。
6. **滚动更新风险**：Arch 是滚动发行，而内核被钉死。对策：**快照式更新**（Btrfs/snapper），
   并在 CI 中做"更新后 GPU 仍可用"的门禁测试。
7. **许可与再分发**：厂商 blob（内核模块、GPU 用户态）的再分发许可需书面确认，否则只能做"本机自用镜像"。

## 7. 里程碑

- **M1（2 周）**：chroot 内跑起 ALARM 用户空间 + MTT 图形栈，能开 KWin/播放视频。
- **M2（6 周）**：可启动的整机镜像（厂商内核 + ALARM 用户空间 + KDE），日常可用。
- **M3（3 个月）**：pacman 仓库 + CI + 安装器 + 更新门禁，形成"可维护的最小发行版"。
- **M4（可选）**：Chromium/Firefox 的 aarch64 优化构建进入仓库（我们已有 Chromium 构建管线）。

## 8. 风险登记

| 风险 | 影响 | 缓解 |
|---|---|---|
| 厂商不提供内核源码/ABI 承诺 | 内核无法升级，安全更新滞后 | 合同层面约束；或接受"冻结内核" |
| 驱动只支持特定 Mesa/内核组合 | 升级即黑屏 | 版本矩阵 + 快照回滚 |
| 无 Vulkan ICD | 部分应用不可用 | 明确支持矩阵，GLES 优先 |
| 再分发许可不明 | 不能公开发布镜像 | 先做自用，商用前法务确认 |
| 单人维护滚动发行版 | 长期不可持续 | 缩小范围（单机型、冻结内核、季度更新） |

## 9. 建议的最小可行路径

1. 先做**方案 A**：在现有 AIOS 上开一个 `systemd-nspawn` 的 ALARM 容器，装 KDE + 我们的 Chromium，
   验证图形/音频/输入/EDR 全链路（1–2 周，零风险、可随时删除）。
2. 同时向厂商索取：内核源码或 ABI 承诺、GPU 用户态再分发许可、固件清单。
3. 若 A 验证通过且厂商配合，再投**方案 B**（整机镜像）。
4. 不建议一上来就做安装器与仓库——那是最后 30% 工作量、却占 50% 维护成本。

## 10. 与本项目已有成果的关系

- KDE 6.8.2 源码构建、EDR 补丁、Chromium 构建管线**可直接复用**；
- `tools/chromium-hdr/README.md` 里记录的 aarch64 工具链经验（原生 clang/rust、禁止 FEX 混入、
  `-mcpu=cortex-a78+nocrypto`）正好是"发行版级重编"的地基；
- 结论：**软件层已经证明可行，瓶颈在闭源内核/驱动的可维护性**。

---

# 附录：向厂商（Moore Threads / MTT）索取的清单

> 目标：让"第三方基于厂商硬件做发行版"在**技术与法律**上都成立。
> 分三级：**P0 没有就做不成**、**P1 没有会很难维护**、**P2 有则更好**。

## P0 —— 阻塞项

| # | 索取内容 | 为什么必须 | 可接受的替代方案 |
|---|---|---|---|
| 1 | **内核源码**（7.0.14 对应的 MTT 补丁集 + `.config`） | 冻结内核无法收安全补丁；无法开 BORE/sched-ext；无法适配新硬件 | 若不能开源：提供**至少 3 年 LTS 维护承诺 + 安全补丁的二进制内核更新** |
| 2 | **GPU 内核模块的再分发许可**（`mtgpu`/`mtdisp`/`mt_ion`） | 镜像无法发布，只能自用 | 允许"随镜像原样分发二进制模块"的书面条款 |
| 3 | **GPU 用户态库（MTT Mesa/EGL/GLES）的再分发许可** | 同上；`libEGL_mtgpu.so.0` 是发行版必需 | 提供可再分发的独立包（deb/pacman） |
| 4 | **固件（firmware blobs）清单与许可** | 缺固件则 GPU 不工作 | 提供固件包 + 允许再分发 |
| 5 | **驱动 ABI 稳定性承诺** | 内核小版本升级即黑屏，滚动发行版无法维护 | kABI 稳定，或承诺"ABI 变更提前 6 个月通知" |
| 6 | **内核/驱动/固件的版本兼容矩阵** | 我们要据此锁定 pacman 包版本 | 一张表即可（driver X ↔ kernel Y ↔ firmware Z） |

## P1 —— 没有会很痛苦

| # | 索取内容 | 用途 |
|---|---|---|
| 7 | ~~官方 aarch64 工具链~~ **已删除** | 我们的 clang/rust 来自 LLVM/Rust 上游源码，与厂商无关；此项应自行解决，不应向厂商索取 |
| 8 | **Vulkan ICD**（当前完全缺失） | KWin Vulkan 后端、部分游戏/浏览器 GPU 路径 |
| 9 | **VA-API / 硬解组件**（HEVC/H.264）与许可 | 视频播放与功耗 |
| 10 | **EGL/GLES 平台支持修复**（`EGL_PLATFORM_WAYLAND` 缺失，已提交探针） | mpv/GTK4 等原生 Wayland 客户端 |
| 11 | **色彩管理文档**：`wp_color_management_v1` 支持度、面板峰值/参考白、EDR 行为 | 我们已在其上做 EDR 补丁，需要厂商确认面板能力（500 nit / 参考 200 nit） |
| 12 | **电源/热/背光接口文档**（`m1000_backlight`、风扇、热区、休眠） | 发行版的电源管理与温控策略 |
| 13 | **MTT 自有 deb 包的 PKGBUILD/打包脚本**（127 个包） | 省掉 10–15 人日的 deb→pacman 转换与文件冲突排查 |
| 14 | **变更日志与早期访问通道**（beta 驱动） | 发行版需要提前适配 |

## P2 —— 加分项

| # | 索取内容 |
|---|---|
| 15 | 板级初始化/控制的 **headless API**（现在只有 GUI 的 smart control panel） |
| 16 | 设备树/ACPI 表、启动链要求（GRUB/EFI、Secure Boot 策略） |
| 17 | 官方**回归测试镜像或测试清单**（GPU/显示/音频/休眠） |
| 18 | 商标/品牌许可：能否称"for M1000"、能否使用其 logo |
| 19 | 技术对接人与 issue tracker（而不是只走商务） |
| 20 | 是否允许我们把补丁（如 KWin EDR）**回馈上游**并公开 |

## 给厂商的一页纸（可直接发）

> 我们计划基于 M1000 平台构建一个第三方 Linux 发行版（Arch/CachyOS 风格 + KDE），
> 需要以下最小支持，请确认可行性与时间表：
>
> 1. **内核**：7.0.14 的源码与配置，或 ≥3 年 LTS 二进制维护承诺；
> 2. **许可**：内核模块、GPU 用户态库、固件的**再分发许可**书面确认；
> 3. **ABI**：驱动与内核的兼容矩阵与 ABI 稳定承诺；
> 4. **图形**：Vulkan ICD 计划、VA-API 硬解组件、`EGL_PLATFORM_WAYLAND` 修复；
> 5. **工具链**：aarch64 官方 clang/rust，或允许我们再分发自建工具链；
> 6. **打包**：MTT 自有 deb 的打包脚本或 PKGBUILD 参考；
> 7. **文档**：电源/热/背光/色彩管理接口说明；
> 8. **流程**：技术对接人、issue tracker、beta 驱动通道。

## 如果厂商拒绝，我们能退到什么程度

| 拒绝项 | 退路 |
|---|---|
| 内核源码 | 冻结内核 + 快照回滚 + 只做用户空间发行版（安全补丁缺失，需明示） |
| 再分发许可 | **只做本机自用镜像**，不公开分发；或提供"构建脚本 + 用户自取驱动" |
| ABI 承诺 | 每次驱动更新重建镜像；用 Btrfs 快照保证可回滚 |
| Vulkan ICD | 明确"GLES-only"支持矩阵 |
| 工具链 | 继续自建（我们已有完整管线与文档） |

> 勘误（2026-11-10）：Chromium 与 mtgpu 在**编译期没有任何耦合**：
> 我们构建的是通用 aarch64 Chromium，只依赖 Wayland/EGL/GBM/DMA-BUF 标准接口；
> MTT 驱动仅在**运行期**通过 GLVND 提供 EGL/GLES。此前文档中“与 mtgpu 一起编”的表述有误。
