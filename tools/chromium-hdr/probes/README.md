# 探测脚本

| 脚本 | 用途 |
|---|---|
| `vpu-decode-test.sh` | 逐个编码（H.264 / HEVC / VP9 / AV1）播放测试片，长采样 `mthreads-gmi -q` 的 `Utilization → Decoder`，输出 VPU 峰值与非零采样数。用法：`./vpu-decode-test.sh noflags` 或 `./vpu-decode-test.sh withflags --enable-features=...` |
| `ab-flags.sh` | 单个测试片对比不同 flag 组合下 VPU 是否工作。用法：`./ab-flags.sh none` / `./ab-flags.sh ignoreonly --enable-features=VaapiIgnoreDriverChecks` |

依赖：`mthreads-gmi`、`mtgpu-chromium`（路径按脚本内 `~/chromium-build/src/out/hdr/chrome`，按需修改）。
判定标准只看 **VPU Decoder 利用率**，CPU 占用会因软解/合成路径产生误导。

配套的 EDR 探针在 `../edr-probe`（读 `wp_color_management_v1` 的 luminances / target_luminance），
合成测试图案在 `../edr-pattern`（四段 PQ 亮度条）。
