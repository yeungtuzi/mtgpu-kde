# MTGPU 兔头屏保（Windows）

黑底上四处游走的四色兔头，每 700ms 切换一帧（左下 → 左上 → 右上 → 右下），
与 aibook 的 Plymouth / ksplash 动画同节奏。支持多显示器（窗口覆盖整个虚拟桌面）。

## 安装

1. 把 `rabbit.scr` 拷到 Windows；
2. 右键 → **安装**（或复制到 `C:\Windows\System32\`）；
3. 设置 → 个性化 → 锁屏界面 → 屏幕保护程序 → 选 **MTGPU Rabbit**；
4. 想锁屏就勾选“在恢复时显示登录屏幕”。

64 位 Windows 10/11。退出：移动鼠标或按任意键。

## 构建

```bash
sudo apt install gcc-mingw-w64-x86-64 python3-pil
./build.sh          # 需要 ../ksplash-aibook 里的 4 张 480px 帧
```

产物：`rabbit.scr`（PE32+ GUI）。帧在构建时被合成到黑底并转成 24 位 BMP 嵌入资源，
运行时无需外部文件。

## 参数

- `/s` 运行（默认）
- `/c` 显示说明
- `/p <hwnd>` 预览模式（未实现，直接返回）
