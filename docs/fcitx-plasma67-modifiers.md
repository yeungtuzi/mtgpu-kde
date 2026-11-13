# fcitx5 在 KWin 输入法模式下吞掉修饰键（Ctrl/Shift）

**现象**：把 fcitx5 设为 KWin 的 Wayland 输入法（设置 → 键盘 → 虚拟键盘 → Fcitx 5，或
`kwinrc [Wayland] InputMethod=/usr/share/applications/org.fcitx.Fcitx5.desktop`）后：

- `Ctrl+C` / `Ctrl+V` 只输出 `c` / `v`，`Ctrl+L` 在 Konsole 里输出 `l` 而不是清屏；
- `Shift+字母` 不大写；
- 单按 `Shift` 切换中英也失效；
- 退格偶尔失灵。

**这是已知回归，不是本项目的配置问题。**

## 上游来源

| 来源 | 内容 |
|---|---|
| [KWin MR !1790](https://invent.kde.org/plasma/kwin/-/merge_requests/1790/commits)（2021） | "forward modifier update to input method"：合成器要求输入法把修饰键状态回传 |
| [KWin commit 0117122](https://invent.kde.org/plasma/kwin/-/commit/0117122679e8ff09d0b88a3408e0d54a776b2216.patch)（2020） | `modifiers` 请求语义：IM 按被抓住键盘的 keymap 回传原始修饰键状态 |
| [fcitx5 commit a05d898f](https://github.com/fcitx/fcitx5/commit/a05d898f04dcde0a57a81e7c7b7ee8d291c9b995)（2025-03-21） | 修复：`WaylandIMInputContextV1::modifiersCallback()` 末尾补 `ic_->modifiers(...)` |
| [KDE Discuss 帖子](https://discuss.kde.org/t/modifier-keys-doesnt-work-under-kde-plasma-6-7-x-and-fcitx-5/48611) | Plasma **6.7.x** 起同样症状；社区结论是 Ubuntu 24.04 的 fcitx 太旧 |

## 根因

1. fcitx5 的 `zwp_input_method_v1` 前端通过 `grab_keyboard` 拿走键盘；
2. 它只把"未处理"的按键用 `zwp_input_method_context_v1.key` 回放给合成器，
   **从不发送 `modifiers` 请求**；
3. Plasma 6.7 起，KWin 在 IM 抓住键盘后不再自行向应用推送硬件修饰键状态
   （`InputFilter::passToInputMethod()` 直接把事件交给 IM 并返回 true），
   完全依赖第 2 步的 `modifiers` 请求；
4. 结果应用只收到裸键码 → Ctrl/Shift 丢失。

Plasma 6.6 及更早版本 KWin 还会兜底，所以问题在 6.7+ 才暴露。

## 版本说明

- 修复提交晚于 **5.1.12**（当前最新正式版），因此"升级到最新 fcitx5"并不解决问题；
- Ubuntu 24.04 自带 **5.1.7**，同样没有该修复；
- 我们的做法：保留系统 5.1.7 的 ABI 与插件生态（pinyin 等 addon 不受影响），
  只重编并替换 `libwaylandim.so`。

## 修复方式

源码补丁见 [`patches/fcitx5-5.1.7-waylandim-modifiers.patch`](../patches/fcitx5-5.1.7-waylandim-modifiers.patch)
（即上游 `a05d898f` 的 2 行）。

一键安装/回滚脚本：[`tools/install-fcitx-waylandim-fix.sh`](../tools/install-fcitx-waylandim-fix.sh)

```bash
sudo bash tools/install-fcitx-waylandim-fix.sh        # 默认 5.1.7
# 或指定版本
sudo VER=5.1.12 bash tools/install-fcitx-waylandim-fix.sh
```

源码与构建产物放在持久目录 `$HOME/build/fcitx5-waylandim`（可用 `WORKDIR=` 覆盖），
**不使用 `/tmp`**（tmpfs 占内存且重启即丢）。

脚本会：

1. 安装构建依赖（`libjson-c-dev` 等）；
2. 下载并解压 fcitx5 源码；
3. 应用补丁（`patch -p1`）；
4. `cmake` + `ninja waylandim`；
5. 备份系统模块（`.orig`），用 `dpkg-divert` 把包自带文件改写到 `.pkg`，
   再安装我们的模块，并 `apt-mark hold fcitx5-modules` 防止升级覆盖；
6. `ldd` 校验无未解析依赖。

装完**注销重登或重启**，让 KWin 用它自己的 `WAYLAND_SOCKET` 拉起 fcitx5。

## 验证

```bash
# fcitx5 应是 kwin_wayland 的子进程，且带 WAYLAND_SOCKET
P=$(pgrep -x fcitx5 | head -1)
ps -o comm= -p "$(ps -o ppid= -p "$P" | tr -d ' ')"     # 期望 kwin_wayland
tr '\0' '\n' < /proc/$P/environ | grep WAYLAND_SOCKET

# 加载的是打过补丁的模块
grep libwaylandim /proc/$P/maps
```

实测（2026-11-13，Plasma 6.8.2 / fcitx5 5.1.7 / 补丁模块 md5 `35f37b84`）：
Konsole、Kate、Brave（原生 Wayland）里中文输入、Ctrl+C/V、Shift+字母、单按 Shift 切换全部正常。

## 回滚

```bash
sudo dpkg-divert --remove /usr/lib/aarch64-linux-gnu/fcitx5/libwaylandim.so
sudo cp -a /usr/lib/aarch64-linux-gnu/fcitx5/libwaylandim.so.orig \
           /usr/lib/aarch64-linux-gnu/fcitx5/libwaylandim.so
sudo apt-mark unhold fcitx5-modules
```
