# 在 AIOS / M1000（arm64）上从源码构建 Chromium

目标：得到能验证 EDR 的 Chromium，并让窗口使用 KDE 的服务端装饰。

版本：**157.0.8103.38**（Stable tag，2026-11 最新 release）。

## 0. 结论先行

上游对 **arm64 Linux host 的支持不完整**：DEPS 为 Linux 只提供 `Linux_x64` 的
clang 与 rust 工具链，直接构建会全部跑在 FEX 模拟上（慢 10 倍以上），且
proc-macro（aarch64 `.so`）无法被 x86_64 rustc 加载。另外本机 Go 1.25 运行时
需要 `GODEBUG=asyncpreemptoff=1`，且 A78 核**没有 AES 扩展**。

## 1. 取源码

```sh
git clone --depth 1 --branch 157.0.8103.38 \
  https://chromium.googlesource.com/chromium/src.git src
cd .. && gclient config --unmanaged .../src.git --name=src
gclient sync --no-history -D --nohooks --revision src@refs/tags/157.0.8103.38
gclient runhooks          # 生成 LASTCHANGE.committime 等
```

注意：`git fetch --depth=1 origin <sha>` 会被服务端拒绝，必须用 **tag**。

## 2. 系统依赖

```sh
sudo bash build/install-build-deps.sh --no-prompt --no-chromeos-fonts
```

`libbluetooth-dev` 与 MTT 的 `libbluetooth3`（5.85）冲突，需从
`build/install-build-deps.py` 的包列表里去掉。

## 3. 原生工具链（关键）

| 组件 | 上游 | 替换为 |
|---|---|---|
| clang | `Linux_x64` x86-64 | `apt.llvm.org` 的 **clang-21 (aarch64)** |
| rust | `Linux_x64` x86-64 | 上游 **nightly 2026-09-10 aarch64**（含 rust-src、bindgen 从旧工具链拷入） |

```sh
curl -fsSLO https://apt.llvm.org/llvm.sh && sudo bash llvm.sh 21
sudo apt-get install -y lld-21 libclang-rt-21-dev
# clang 头文件按版本 24 拼路径，做符号链接
sudo ln -sfn /usr/lib/llvm-21/lib/clang/21 /usr/lib/llvm-21/lib/clang/24
```

rust 替换：把 nightly 解包后 `install.sh --prefix=...`，覆盖
`third_party/rust-toolchain/{bin,lib,libexec,etc}`；再补：

* `lib/rustlib/src/rust`（compiler-builtins 等源码）
* `lib/third_party/crubit`
* `bin/bindgen`、`bin/cc_bindings_from_rs`（从旧的 x86-64 工具链拷贝）
* `VERSION` 文件（gn 会读）

## 4. gn 参数

```sh
gn gen out/hdr --args='
  is_debug=false is_component_build=false
  symbol_level=1 blink_symbol_level=0 v8_symbol_level=0
  proprietary_codecs=true ffmpeg_branding="Chrome"
  enable_nacl=false chrome_pgo_phase=0
  dcheck_always_on=false treat_warnings_as_errors=false
  enable_linux_installer=false use_siso=false
  clang_base_path="/usr/lib/llvm-21"
  clang_use_chrome_plugins=false
  mtgpu_legacy_clang=true'
```

`proprietary_codecs=true` 在 Linux 上会自动打开
`enable_hevc_parser_and_hw_decoder` → M1000 硬解 HEVC/H.264。

## 5. 必需的源码补丁

1. **`-mcpu=cortex-a78+nocrypto`**（`build/config/compiler/BUILD.gn`）
   A78 核没有 AES 扩展，默认 `-mcpu=cortex-a78` 会让 absl 哈希生成 `aesd`
   指令 → 运行即 SIGILL。
2. **clang-24 专属参数开关**（`mtgpu_legacy_clang`）
   `-fdiagnostics-show-inlining-chain`、`-fno-lifetime-dse`、
   `-fsanitize-ignore-for-ubsan-feature` 在 clang 21 上会直接报错。
3. **KDE 服务端装饰**（`ui/ozone/platform/wayland/ozone_platform_wayland.cc`）
   `custom_frame_pref_default = false`，配合 pref `browser.custom_chrome_frame=false`
   即可让 KWin 画 Breeze 标题栏（否则是 Chrome 自绘的红绿灯 CSD）。
4. **EDR 诊断日志**（`components/viz/service/display/skia_renderer.cc`）
   打印 `display_sdr_nits` / `display_headroom` / `targeted_headroom`，
   用 `CHROME_EDR_DEBUG=1` 开启。
5. **`ts_library.py` 放宽 undici-types 定义检查**（vendored @types/node 与清单不一致）。

## 6. 运行环境

```sh
export GODEBUG=asyncpreemptoff=1   # Go 1.25 (tsc/siso) 在本机内核需要
ninja -C out/hdr chrome
```

## 7. 安装到 /opt（不影响系统 Chrome）

Chromium 产物是自包含目录，安装即拷出 `out/hdr` 中运行所需文件：

```sh
/opt/chromium-hdr/bin/chrome --ozone-platform=wayland ...
```

## 8. 已知限制

* WebUI/DevTools 的 TypeScript 产物依赖 tsc，运行期需要 `GODEBUG`（仅构建期）。
* 上游无 arm64 clang/rust 包，本方案依赖本地 clang 21 + nightly rust。

## 9. 已知阻塞（2026-11，未解决）

在当前 arm64 Linux host 上，Chromium 的 Rust↔C++ 绑定工具 **crubit**
（`cc_bindings_from_rs`）无法替换：

* 官方工具链只发布 **x86-64** 的 `cc_bindings_from_rs`，且与其自带 rustc
  （`1edd55dcf`）版本绑定；
* 若改用原生 aarch64 rustc，crubit 分析 Rust crate 时必然
  `E0514: found crate compiled by an incompatible version of rustc`；
* 关掉 crubit 又会缺 `components/cbor` 与 blink `ift_patcher` 所需的生成头文件；
* 让宿主工具链整体编成 x86_64 需要 x86_64 glibc 开发文件（本机没有），
  build script 链接会失败。

受影响的 3 个目标：`components/cbor/rust`、`build/rust/std` 的
`rs_std`/`rs_alloc`/`rs_core` 绑定。

可行但昂贵的出路：
1. 用 `tools/rust/build_crubit.py` 从源码编 crubit（需先编 LLVM+rustc，约 6–10 小时）；
2. 等上游提供 arm64 版 clang/rust/crubit 工具链（DEPS 目前没有）。

## 10. 其它环境坑（已验证）

* **Go 1.25 运行时**（`tsc`/`siso`）在本机内核需要
  `GODEBUG=asyncpreemptoff=1`，否则 SIGSEGV；
* **A78 无 AES 扩展**：`-mcpu=cortex-a78` 必须加 `+nocrypto`，
  否则 absl 哈希生成 `aesd` 指令，运行时 SIGILL；
* `use_siso=false`（siso 同样受 Go 运行时影响）；
* sysroot 需补 `libdrm` 头文件。

## 11. 自建工具链（`tools/rust/build_rust.py`）在 aarch64 宿主的额外坑

上游该脚本只考虑 x86_64 宿主，aarch64 上需额外处理：

1. **`pinned-clang` 是 x86-64 二进制** → 用 wrapper 指向系统 `clang-21`；
2. **内置 cmake 3.26 太旧**（LLVM 24 要求 ≥3.31）→ pip 从清华镜像装
   `cmake>=3.31` 覆盖内置路径；
3. **`CMAKE_SYSROOT` 指向 amd64 Debian sysroot** → aarch64 宿主必须跳过这两处
   （`tools/clang/scripts/build.py` 约 548 与 1289 行），否则找不到 `Scrt1.o`/`libgcc`；
4. **网络**：`commondatastorage.googleapis.com` 直连不可达，可用
   `proxychains4` + SOCKS5 兜底（优先级：国内镜像 → 官方 CDN → 代理）；
5. LLVM monorepo 全量克隆 ~10 GB；可用
   `git clone --filter=blob:none --no-checkout` + `git checkout <sha>` 大幅减少流量。

成功路径：`build_rust.py --stage-1 --build-crubit` 会产出与本仓库 Rust 代码
完全匹配的 aarch64 工具链（含 `cc_bindings_from_rs`）。

## 12. LLVM 编译阶段在 aarch64 宿主的坑（续）

1. **clang-21 编 LLVM-24 的 RISCV 后端会自身崩溃**（frontend signal）→ 把
   `tools/clang/scripts/build.py` 的 `targets` 裁成 `'AArch64;X86'`
   （rust 只要 AArch64；顺带少编 500+ 个对象）。
2. **脚本按 x86_64 GCC 16 拼头文件路径**（`/usr/lib64/gcc/x86_64-pc-linux-gnu/16/
   ../../../../include/c++/16`）。本机没有 `/usr/lib64`，路径无法规范化 →
   `sudo mkdir -p /usr/lib64/gcc/x86_64-pc-linux-gnu/16` 并
   `ln -s /usr/include/c++/15 /usr/include/c++/16`。
   本机实际 g++ 是 **15**，头文件应指向 15 而不是 13。
3. wrapper 里显式加
   `--gcc-install-dir=/usr/lib/gcc/aarch64-linux-gnu/15`
   `-isystem /usr/include/c++/15 -isystem /usr/include/aarch64-linux-gnu/c++/15`。
