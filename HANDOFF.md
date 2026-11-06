# HANDOFF — KDE Plasma 核心包移植（AIOS / ARM64）+ 全局色彩管理 + HDR

> 给新会话的自包含交接文档。所有环境事实都实测过，附证据；未验证的地方明确标注了。
> 写于 2026-11-05，基线机器 `aibook`。

---

## ⚠️ 2026-11-05 重要修正（先读这一段）

本文下方"路线 C / Plasma 5.27"的结论**已作废**，实际决定如下：

1. **目标是 Plasma 最新稳定版 6.8.2**（6.8.0 于 2026-10-14 发布），不是 5.27。
   Ubuntu 24.04 apt 源里只有 5.27，因此**全部从源码构建**：
   Qt 6.11.3 + KDE Frameworks 6.31 + Plasma 6.8.2。
2. 安装前缀 **`/opt/kde6`**（隔离，不覆盖 `/usr`）；编译器 **GCC 15.2**，
   `-O2 -march=native -mtune=native -pipe`，ccache。
3. **EDR 已经内置于 KWin 6.8**，不需要"解除 HDR 元数据限制"的补丁：
   内屏 + 有 brightnessDevice + 不支持标准 HDR 时，KWin 直接启用
   `Capability::Edr`，按屏幕内容动态抬 headroom（上限 3×）。见
   [notes/edr-findings-6.8.md](notes/edr-findings-6.8.md)。
4. 因此本项目的实际任务变为：
   构建 6.8 → tty3 起 Wayland → 每输出 ICC → 用 HDR 内容验证 EDR →
   回退与文档。HDR 标准模式（`HDR_OUTPUT_METADATA`）仍然做不了，结论不变。
5. 构建细节、当前进度、回退方法见
   [notes/build-6.8.md](notes/build-6.8.md)；
   亮度语义（物理亮度 / SDR 白 / headroom）见
   [notes/edr-brightness-semantics.md](notes/edr-brightness-semantics.md)。

> 下面第 3、4、5 节中关于 5.27 的路线描述仅作历史记录，**不要再照着执行**。

---

## 0. 一句话

在 AIOS（Ubuntu 24.04 ARM64，摩尔线程 M1000）上把 KDE Plasma 核心包跑起来，
交付**可用的桌面**和**全局色彩管理**（colord/ICC）。

**HDR 是可选加分项，不是验收项。** 驱动不支持标准接口，且不指望厂商补。
另外还有一条 **EDR（Apple 式扩展动态范围）** 的备选路线，见
`notes/edr-alternative.md`——**它不需要 HDR 面板，也不需要驱动支持**，
卡点只在 KWin 的功能开关，路线是"源码构建 Plasma 6 + 小补丁"。

---

## 1. 目标与验收标准

| # | 验收项 | 判定方式 |
|---|---|---|
| ① | Plasma 桌面能启动（Wayland 会话） | `startplasma-wayland` 进桌面，`plasmashell`/`kwin_wayland` 常驻 |
| ② | 全局色彩管理生效 | 系统设置里能给每个输出加载 ICC，`colord` 中出现对应 profile，`kwin_wayland` 日志显示应用了 LUT |
| ⑤ | 可回退 | Windows VM 与 viewer 随时能重新启动（VM 现已关闭，`sudo winvm start` 即可） |

**验收范围 = ① ② ⑤。**

~~③ HDR 可开关~~ / ~~④ HDR 内容验证~~ —— **降级为可选，不计入验收**。
原因：`mtgpu` 驱动不暴露 `HDR_OUTPUT_METADATA` / `Colorspace`，且已确认不指望厂商支持。
证据见 3.3，完整数据见 `notes/hdr-driver-findings.md`。

---

## 2. 环境事实（实测）

### 2.1 机器

| 项 | 值 |
|---|---|
| 主机 | `aibook`，`192.168.100.136` |
| 架构 | ARM64（aarch64） |
| 系统 | AIOS，基于 Ubuntu 24.04（`/etc/os-release` 为 Ubuntu noble） |
| 内核 | `7.0.14`（AIOS 定制，cmdline 带 `plymouth.enable=0`） |
| CPU/内存 | 12 核 / 31 GB |
| 磁盘 | `/` 935 G，已用 220 G，剩 668 G |
| 登录 | 用户 `lf`，**免密 sudo** |

从开发机（`192.168.100.252`，x86_64 Debian 13）访问：

```sh
ssh -i /root/.ssh/id_ed25519_aibook -o IdentitiesOnly=yes lf@192.168.100.136
```

**密码不要写在任何文件里，也不要传。**

### 2.2 图形栈现状

| 项 | 值 | 证据 |
|---|---|---|
| 当前会话 | GNOME / **Wayland**（GDM 自动登录 lf） | `gnome-shell` 进程 + `/run/user/1000/.mutter-Xwaylandauth.*` |
| 自动登录配置 | `/etc/gdm3/custom.conf` 里 `AutomaticLoginEnable=true` | — |
| 显示器 | 只有内置 `card0-eDP-1`（2880x1800），`DP-1`/`DP-2` 未接 | `for c in /sys/class/drm/card0-*; do cat $c/status` |
| 显示驱动 | `mtgpu` + `mtdisp`（摩尔线程 DRM 驱动） | `lsmod`、`/sys/class/drm/card0/device/driver` |
| GPU | M1000，Mesa 25.2.8（MTT 定制），OpenGL 4.5 | `glxinfo -B` / `dpkg -l libgl1-mesa-dri` |
| colord | **已在运行**（1.4.7-1build2） | `systemctl is-active colord` |

### 2.3 面板 HDR 能力（重要，且是好消息）

`edid-decode /sys/class/drm/card0-eDP-1/edid` 的结果：

```
Manufacturer: EDO   Model: 5160
Native Color Depth: 12 bpc
Native Maximum Luminance (Full Coverage): 507.5 cd/m^2
Native Minimum Luminance: 10 cd/m^2
Supported color space and EOTF combination 1: DCI-P3, BT.2020/SMPTE ST 2084   ← PQ = HDR10
HDR Static Metadata Data Block:
    Supported static metadata descriptors: Static metadata type 1
```

结论：**这块内置屏支持 HDR10（PQ/EOTF、12bpc、约 500 nits）**，不需要外接 HDR 显示器就能测。

### 2.4 软件包现状

| 项 | 值 |
|---|---|
| 已装 KDE | **无**（`plasma-desktop` 未安装） |
| 源里的 Plasma | `plasma-desktop 4:5.27.12-0ubuntu0.1`、`kwin-wayland 4:5.27.11-0ubuntu3` |
| 构建工具 | `cmake` ✓、`ninja` ✓（/usr/local/bin）、`meson` ✗、`kdesrc-build` ✗ |

---

## 3. 决定性结论（开工前必须接受的前提）

### 3.1 Plasma 5.27 **没有 HDR**

Ubuntu 24.04 源里是 5.27。KWin 的 HDR 支持是 **Plasma 6** 才有的（6.0 引入，6.1/6.2 才逐步可用）。
⇒ 想开 HDR 至少得 Plasma 6。**但这不是瓶颈**——3.3 实测驱动根本不支持 HDR，
换 Plasma 6 也没用（见下）。5.27 能做的是全局色彩管理（colord + ICC + 每输出 profile），
这部分可以作为阶段成果交付。

### 3.2 HDR 必须走 **Wayland**

KWin 的 HDR 只在 Wayland 会话下可用，X11 没有。
⇒ Plasma 6 + Wayland + 驱动三个条件同时满足才行。前两个可以自己解决，第三个（驱动）不行。

### 3.3 驱动能力 —— **已实测（P0 完成）**

工具：`sudo apt install libdrm-tools`，然后 `modetest -c -p`。

驱动标识：

```
opened device `Moorethreads DRM/KMS Driver` on driver `mtgpu` (version 2.1.0 at 0)
```

**eDP-1 连接器的全部属性**（就这 5 个，没有更多）：

```
EDID / DPMS / link-status / non-desktop / TILE
```

⇒ **没有 `HDR_OUTPUT_METADATA`，没有 `Colorspace`，没有 `max bpc`。**

**CRTC 属性**：有标准 `GAMMA_LUT`（blob）和 `GAMMA_LUT_SIZE = 256`，另有厂商私有的
`COLOR_RANGE` / `DATA_EXTEND` / `DATA_TRUNC` / `DEGAMMA` / `DE_MULTIPLY` / `DITHER_ENABLED` / `DMA_CONFIG`。
**没有 `CTM`**（颜色变换矩阵）。

**平面支持的格式**：

```
XR12 XB12 RX12 BX12 AR12 AB12 RA12 BA12 XR15 ... RG16 BG16 XR24 ... 
YV12 YU12 NV12 NV21 NV16 NV61 P010 P210
```

有 `P010`/`P210`（10-bit YUV，视频/解码用）和一组 `XR12/AR12`（疑似 10/12-bit RGB），
但 **connector 层没有任何 HDR 信令属性**。

#### 结论

| 能力 | 状态 | 依据 |
|---|---|---|
| 面板 HDR10 | ✅ 支持 | EDID：PQ/EOTF、12bpc、507 nits |
| 平面 10-bit 输出 | ⚠️ 部分 | 有 P010/P210，RGB 10-bit 待确认 |
| **HDR 元数据下发** | ❌ **不支持** | connector 无 `HDR_OUTPUT_METADATA` |
| 色彩空间切换 | ❌ 不支持 | 无 `Colorspace` |
| 硬件 gamma LUT | ✅ 支持 | `GAMMA_LUT`，size 256 |
| 硬件 CTM | ❌ 无 | 无 `CTM` |

**HDR 在驱动层就被卡住了。** KWin 的 HDR 实现（Plasma 6）靠设置
`HDR_OUTPUT_METADATA` connector property 来告诉显示器"这是 HDR 内容"，
这个属性不存在，合成器就无法把显示器切进 HDR 模式——面板硬件支持也没用。

⇒ **不换驱动/内核，HDR 做不了。** 这不是 Plasma 版本问题，也不是配置问题。

**补充（重要，别误判）**：驱动并非完全没有 HDR 能力。平面属性里有私有的
`HDR`(0/1)、`EOTF`、`GAMUT_MAP`、`TONE_MAP` blob，CRTC 上有 `BLD_EOTF`/`BLD_OETF`/`BLD_GAMUT_MAP`，
以及 `CCM_LNR`/`CCM_NON_LNR` 色彩矩阵。也就是说**硬件/驱动层有 HDR 管线，只是走私有接口**，
上游 KWin 只认标准的 `HDR_OUTPUT_METADATA`，所以用不上。

⇒ **项目决定（2026-11-05，用户确认）：HDR 为可选项，不计入验收；不指望厂商补驱动。**
将来若要做，路径是：反推私有 blob 格式 → 给 KWin 打补丁（或写最小合成器）去设这些属性。
完整证据与设想见 `notes/hdr-driver-findings.md`。

好消息是**全局色彩管理可以正常做**：有 `GAMMA_LUT`（硬件 LUT）且 `colord` 已在运行，
KWin 也能在着色器里做 LUT。

### 3.4 这台机器是**开发机**（2026-11-05 起）

之前 `aibook` 上跑着 Windows VM，现在**已关机**，后台 AIOS 服务也已停用，
处于低负载状态（内存 2.6 GB / 31 GB，CPU 基本空闲）。详见 `notes/lowload-baseline.md`。

* 需要 VM 时：`sudo winvm start`（关机用 guest 内 `shutdown.exe /s /t 0 /f`，ACPI 不生效）
* `memguard` 已停用——**编译任务务必保持它关闭**，否则它可能在内存紧张时杀掉编译器
* load average 显示 7 是 VPU 内核线程卡 D 状态的假象，不代表真实负载
* 仍然建议 KDE 测试在独立 TTY（`Ctrl+Alt+F3`）里做，别把 GNOME 会话搞乱

---

## 4. 技术路线（P0 之后已收敛）

P0 的结论改变了原计划：**HDR 被驱动卡住，Plasma 6 也救不了**。
所以"要不要上 Plasma 6"这个问题，答案取决于你想不想为 HDR 以后能开而提前铺路。

### 路线 C（推荐，先做）：Plasma 5.27 + 全局色彩管理

```sh
sudo apt install -y plasma-desktop plasma-workspace kwin-wayland \
  colord-kde plasma-systemmonitor
```

* 交付 ①②（桌面 + 全局色彩管理），这部分**现在就能验证**
* 5.27 的 KWin 在 Wayland 下支持每输出 ICC（colord + shader LUT）
* 装完不动 GDM 默认会话，先在 TTY 里试 `dbus-run-session -- startplasma-wayland`
* 1–2 小时能出结果

### 路线 A：源码构建 Plasma 6（只在需要新特性时才走）

HDR 已经不是理由了（见 3.3）。如果只是想要 Plasma 6 本身的新特性
（新的系统设置、更好的 Wayland 支持、更新的 KWin 特效），可以走这条路。

代价：ARM64 编译全套要几小时，依赖链长。产物装 `~/kde/usr`，不动系统包。

### 路线 B（要做成包）：在更新的发行版里构建 deb

如果目标是把 Plasma 6 打成 AIOS 能装的 deb，用 nspawn/debootstrap 起一个
Ubuntu 25.04（Plasma 6.3）环境构建打包。

### 关于 HDR 本身，能做的只有两条

1. **推驱动**：向摩尔线程要支持 `HDR_OUTPUT_METADATA` + `Colorspace` 的 `mtgpu`/`mtdisp`，
   或拿到源码自己加（需要 HDR 元数据沿 atomic commit 传到面板、并让面板进 PQ 模式）。
2. **绕开 DRM**：极不推荐，且 KWin 不会配合。

在驱动到位之前，③④ 应当**明确记为"阻塞在驱动"**，而不是反复尝试 Plasma 版本。

## 5. 分阶段计划

### P0 驱动能力验证 —— ✅ **已完成**（见 3.3）

结论：无 `HDR_OUTPUT_METADATA` / `Colorspace`，HDR 不可用；有 `GAMMA_LUT`，色彩管理可做。

### P1 桌面跑起来（半天，路线 C）

1. `apt install plasma-desktop plasma-workspace kwin-wayland colord-kde`
2. 在 tty3 用 `dbus-run-session -- startplasma-wayland` 起测试会话，**不动 GDM**
3. 确认 `plasmashell` / `kwin_wayland` 常驻、桌面可用
4. 记录与 GNOME 共存的注意事项（colord 两边共用）

> 如果用户要求"为 HDR 铺路"，这一步换成 kdesrc-build 构建 Plasma 6（数小时）。

### P2 色彩管理（1 天）

1. 系统设置 → 显示 → 色彩校正，加载 ICC
2. 确认 `colord` 里有 profile、`kwin_wayland` 日志有 LUT 应用
3. 用 `colormgr`/`colord-kde` 验证每输出独立 profile

### P3 可选：EDR / HDR 探索 —— **不做**（已排除出范围）

如果要碰，先读 `notes/edr-alternative.md`。

要点：**EDR 不需要 HDR 面板**（Apple 在 MacBook Air / iPad Air 这类普通 LCD 上就有），
只要面板够亮、合成器把 SDR 白压在峰值以下即可。本机面板 507 nits，余量足够。
真正的障碍是 KWin 把这条路径锁在"连接器支持 HDR 元数据"之后——需要打补丁解除。

#### 原 HDR 说明

已确认：标准 DRM HDR API 缺失，但驱动有私有 HDR 管线（平面 `HDR`/`EOTF`/`GAMUT_MAP`/`TONE_MAP`）。
要做就得反推私有 blob 格式 + 给 KWin 打补丁，属于独立课题，不在本项目内。

证据已留档在 `notes/hdr-driver-findings.md`，将来想做直接从那篇开始，不要重复调研。

### P4 收尾

1. 决定是否把 KDE 设为默认会话（**会改变这台开发机的日常使用，需用户确认**）
2. 把过程写成文档，提交到本目录
3. 清理：不要把半成品留在系统里

---

## 6. 风险清单

| 风险 | 影响 | 应对 |
|---|---|---|
| `mtgpu` 不暴露 HDR 属性 | HDR 路线直接断 | P0 先验证；不行就收敛到色彩管理 |
| Plasma 6 在 ARM64 上编译失败 | 卡在 P1 | 优先只构建 kwin + plasmashell；必要时用路线 B |
| 换 DM 导致 viewer 消失 | 用户体验中断 | 只在 TTY 测试，不碰 GDM；出问题 `systemctl restart gdm3` |
| Mesa 25.2.8 是 MTT 定制版 | 上游 KWin 的某些路径可能不兼容 | 记录差异；必要时给 Mesa 打补丁 |
| 面板虽支持 HDR 但驱动只给 8-bit | HDR 观感差 | P0 验证 10-bit 格式；否则记录为限制 |
| 磁盘/编译时间 | 构建 Plasma 全套很慢 | 只构建核心包，`-j12` |

---

## 7. 环境速查

### 7.1 常用命令

```sh
# 看当前会话
loginctl list-sessions
ps -o cmd= -C gnome-shell

# 看 DRM
modetest -c -p -M mtgpu
cat /sys/class/drm/card0-eDP-1/status

# 看面板 HDR
sudo cp /sys/class/drm/card0-eDP-1/edid /tmp/panel.edid
edid-decode /tmp/panel.edid | grep -iE "HDR|luminance|bpc|EOTF"

# 从 TTY 起一个测试会话（不动 GDM）
dbus-run-session -- startplasma-wayland

# 恢复图形会话 / 重开 VM
sudo systemctl restart gdm
sudo /usr/local/bin/winvm start      # 需要 Windows 时

# 看 KWin 日志
journalctl --user -u plasma-kwin_wayland -f
```

### 7.2 与本机已有项目的关系

* `aibook` 上的 Windows VM 属于另一个项目（`mtgpu-woa`，见 `/root/lvllm/repos/mtgpu-woa`）
* **不要修改** `/usr/local/bin/winvm`、`/opt/mtvmm/bin/winvm-viewer`、`winvm-dbus`
* 两个项目共用同一块 GPU：VM 在跑时 mdev 被占用，**KDE 的 3D 测试要等 VM 停掉再做**

---

## 8. 给新会话的开场提示词

```
读 /root/lvllm/repos/kde-plasma-hdr/HANDOFF.md。

P0 已经做完了。验收范围已定为：桌面 + 全局色彩管理 + 可回退（HDR 可选，已排除）。
驱动有 GAMMA_LUT（size 256），色彩管理可做。按路线 C 走：
装 Plasma 5.27，在 TTY 里起测试会话，把桌面和每输出 ICC 跑通。

aibook 现在是开发机（VM 已关机、后台 AIOS 服务已停，见 notes/lowload-baseline.md）。
KDE 测试在 TTY（tty3）里做，先别改默认会话；需要 Windows 时 sudo winvm start。
```

---

## 9. 已定的决策与剩余问题

### 已定（2026-11-05）

1. **HDR 是可选，不计入验收**；不指望厂商补驱动。
2. **验收范围 = ①②⑤**（桌面 / 全局色彩管理 / 可回退）。
3. 技术路线走 **C：apt 装 Plasma 5.27 先跑通**。

### 还需要确认

1. **交付形态**：只是把环境跑起来，还是要打成 deb 包给 AIOS 分发？
2. **最终是否让 KDE 取代 GNOME 作为默认桌面？** 这会改变这台机器的日常使用，
   也会影响 Windows VM 的 viewer 显示在哪个会话里。
3. ~~有没有第二台 ARM64 机器当测试机？~~ 已确认 aibook 就是开发机，可以直接用。
