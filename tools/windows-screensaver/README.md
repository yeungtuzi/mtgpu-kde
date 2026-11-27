# MTGPU 兔头屏保（Windows）

abstract 深蓝背景上四处游走的四色兔头（与 Linux/macOS 屏保同一张背景），
每 700ms 切换一帧（左下 → 左上 → 右上 → 右下），与 aibook 的 Plymouth / ksplash 同节奏。
兔头按屏宽 12.5% 缩放、带圆角透明遮罩；支持多显示器（覆盖整个虚拟桌面）。

## 安装

1. 把 `rabbit.scr` 拷到 Windows；
2. 右键 → **安装**（或复制到 `C:\Windows\System32\`）；
3. 设置 → 个性化 → 锁屏界面 → 屏幕保护程序 → 选 **MTGPU Rabbit**；
4. 想锁屏就勾选“在恢复时显示登录屏幕”。

64 位 Windows 10/11。退出：移动鼠标或按任意键。

技术要点（避免高分辨率下闪烁）：

- 每帧先在离屏 DIB 里合成“背景 + 兔头”，再一次性 BitBlt 到窗口，不会看到擦除/重绘的中间态；
- 进程声明 Per-Monitor V2 DPI 感知，6K + 系统缩放时不会被 DWM 位图拉伸（否则既模糊又容易闪）；
- 内嵌精灵为 768px，6K（6144 宽）下仍能按 12.5% 屏宽显示，4K 下则降采样保持清晰。

## 构建

```bash
sudo apt install gcc-mingw-w64-x86-64 python3-pil
./build.sh          # 需要 ../ksplash-aibook 里的 4 张 480px 帧
```

产物：`rabbit.scr`（PE32+ GUI，静态链接，无 VC 运行库依赖）。
背景 PNG 与 4 帧 PNG（已加圆角 alpha）作为 RCDATA 嵌入资源，运行时无需外部文件。
背景图来自 `assets/background.png`（与 macOS 版 `bg-no-rabbit.png` 相同）。

## 参数

- `/s` 运行（默认）
- `/c` 显示说明
- `/p <hwnd>` 预览模式（未实现，直接返回）
