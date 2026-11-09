# edr-pattern

最小的 Wayland EDR 测试客户端：用 `wl_shm` 提交一块 PQ/BT.2020 画面
（四条竖带 = 100 / 203 / 500 / 1000 nit），并通过 `wp_color_management_v1`
把这块 surface 标记为 ST2084 + BT.2020。**不依赖 GL / Vulkan**，所以在
MTT 驱动缺 Wayland EGL 平台、Vulkan WSI 又坏掉的机器上依然能验证 KWin 的 EDR。

## 构建

```sh
# 协议代码（KWin 6.8 实现到 v3，需上游 main 的 XML 才有 ready2）
curl -sfLO "https://gitlab.freedesktop.org/wayland/wayland-protocols/-/raw/main/staging/color-management/color-management-v1.xml"
wayland-scanner client-header color-management-v1.xml cm-client-protocol.h
wayland-scanner private-code  color-management-v1.xml cm-protocol.c

wayland-scanner client-header /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml xdg-shell-client-protocol.h
wayland-scanner private-code  /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml xdg-shell-protocol.c

gcc -O1 -o edr-pattern edr-pattern.c cm-protocol.c xdg-shell-protocol.c \
    $(pkg-config --cflags --libs wayland-client) -lm
```

## 运行

```sh
XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 ./edr-pattern
```

窗口出现四条竖带，从左到右 100 / 203 / 500 / 1000 nit。预期观感：

* 带 2（203 nit）≈ SDR 白；
* 带 3（500 nit）明显亮于带 2 —— 这是 EDR 生效的标志；
* 带 4（1000 nit）与带 3 同色，因为面板峰值只有 500 nit，超出部分被裁切。

若带 3 与带 2 一样亮，说明合成器通告的 `max` 仍是 200（未打
`patches/kwin-6.8.2-edr-peak-luminance.patch`）。
