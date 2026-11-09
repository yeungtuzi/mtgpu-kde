# edr-probe

读取合成器通过 `wp_color_management_v1` 对**输出**通告的颜色描述，打印：

```
LUMINANCES min=... max=... reference=...
TARGET_LUM min=... max=...
```

`max/reference` 就是 EDR headroom。用来验证 KWin 实际通告给客户端的峰值亮度和 SDR 白点。

## 构建

需要 `wayland-protocols` 里的 `color-management-v1.xml`（本机 1.45 自带；KWin 实现到 v3，需用上游 main 分支的 XML 才能拿到 `ready2` 事件）：

```sh
curl -sfLO "https://gitlab.freedesktop.org/wayland/wayland-protocols/-/raw/main/staging/color-management/color-management-v1.xml"
wayland-scanner client-header color-management-v1.xml cm-client-protocol.h
wayland-scanner private-code  color-management-v1.xml cm-protocol.c
gcc -O1 -o probe probe.c cm-protocol.c $(pkg-config --cflags --libs wayland-client)
```

## 运行

```sh
XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 ./probe
```

对照：改 `kscreenctl <output> set-brightness N%` 后 `LUMINANCES reference` 应随之变化；
`max` 在打了 `patches/kwin-6.8.2-edr-peak-luminance.patch` 后应等于
`maxPeakBrightnessOverride`（本项目设为 500），未打补丁时恒为 200。
