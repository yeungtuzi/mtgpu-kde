# tools

## set-full-damage

在 KWin 已经运行时，把 active primary plane 的 `FB_DAMAGE_CLIPS` 持续设置为
“整帧矩形” blob，用来验证 mtgpu/mtdisp 是否把 KWin 设置的 `0`（全帧）误解成半宽。

```sh
gcc -O2 -o set-full-damage set-full-damage.c $(pkg-config --cflags --libs libdrm)
sudo ./set-full-damage
```

程序会打印 plane id / CRTC 尺寸，然后每 5ms 设置一次，Ctrl-C 停止。
若设置后物理屏幕从“左半屏”变成完整画面，就确认是 `FB_DAMAGE_CLIPS` 的 0 值问题，
随后在 KWin 的 `DrmPipeline` 里改用同样的 full-rect blob。
