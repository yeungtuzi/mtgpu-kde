# 测试视频

用于验证 EDR 亮度滚降与硬解，全部为本仓库自制，可直接在 `mtgpu-chromium` 里打开。

| 文件 | 编码 | 说明 |
|---|---|---|
| `hdr-bars.mp4` | HEVC Main10 / PQ / BT.2020 | 四段亮度条 100 / 203 / 500 / 1000 nit，用于验证 HDR1000 → TrueBlack HDR500 映射 |
| `hdr-bars-vp9.webm` | VP9 10-bit / PQ / BT.2020 | 同上内容的 VP9 版本，给没有 HEVC 的构建用 |
| `h264-test.mp4` | H.264 High / 8-bit | 硬解对比用测试片（720p，5 s） |
| `vp9-test.webm` | VP9 / 8-bit | VP9 硬解测试片 |
| `av1-test.mkv` | AV1 / 8-bit | AV1 硬解测试片 |

四段亮度条的正确观感（面板峰值 500 nit）：

| 档位 | 100 % 亮度（SDR 白 500） | 40 % 亮度（SDR 白 203） |
|---|---|---|
| 1（100 nit） | 偏暗 | 略高于白 |
| 2（203 nit） | 约等于白 | 2.4× 白 |
| 3（500 nit） | 峰值 | 峰值 |
| 4（1000 nit） | 经 BT.2390 映射到峰值，应与 3 可区分 | 同上 |

注意：`spectacle` 截屏会经过合成器的 SDR 转换，**高光会被压缩/削顶**，截图只能证明"有滚降"，不能当亮度计用；实际观感更接近 TrueBlack HDR500。推荐观看 HDR 时亮度 40–50 %。

生成方式（示例）：

```sh
ffmpeg -i hdr-bars.mp4 -c:v libvpx-vp9 -pix_fmt yuv420p10le \
  -color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc hdr-bars-vp9.webm
ffmpeg -f lavfi -i testsrc2=size=1280x720:rate=30 -t 5 -c:v libx264 -pix_fmt yuv420p h264-test.mp4
```
