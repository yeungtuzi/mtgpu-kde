# Building the aarch64 LLVM + Rust + Crubit toolchain for Chromium

Chromium ships prebuilt clang/rust/crubit only for x86-64.  On an aarch64 host
everything has to be built from source.  This is the exact sequence that worked
on the M1000 laptop (12× Cortex-A78, Ubuntu 24.04, glibc 2.39), including every
dead end we hit, so the next person does not have to rediscover them.

## 0. Prerequisites

- 40 GB free disk, 12+ GB RAM, a few hours of CPU.
- `tools/clang/scripts/build.py` and `tools/rust/build_rust.py` patched as
  described in `README.md` §13/§14 (host-arch triples, no Debian sysroot,
  pinned-clang download guard, native-only target lists).
- `GODEBUG=asyncpreemptoff=1` for every Go-based helper (`tsc`, `siso`).
- `MTGPU_PINNED_CLANG=1` and `MTGPU_KEEP_BUILD=1` exported before the loops.

## 1. LLVM / clang

```sh
cd src
python3 tools/clang/scripts/build.py \
  --disable-asserts --no-tools --no-runtimes --pic \
  --with-ml-inliner-model= --without-zstd --without-android --without-fuchsia \
  --build-dir  third_party/rust-toolchain-intermediate/llvm-host-build \
  --install-dir third_party/rust-toolchain-intermediate/llvm-host-install
```

Key choices:

| choice | why |
|---|---|
| `-DLLVM_TARGETS_TO_BUILD=AArch64` | 9 backends × every TU is the dominant cost |
| skip `CMAKE_SYSROOT` | the bundled sysroot is an *amd64* bullseye one |
| `-DLLVM_ENABLE_LIBXML2=OFF` | the bundled libxml2 2.9 does not build with gcc-15 headers |
| `-O1` release flags | `-O2/-O3` on 12 A78 cores does not pay for itself |
| `MTGPU_KEEP_BUILD=1` | `build.py` otherwise deletes the build tree each run |

## 2. Rust toolchain

```sh
GODEBUG=asyncpreemptoff=1 MTGPU_PINNED_CLANG=1 \
python3 tools/rust/build_rust.py --build-crubit --skip-test --skip-llvm-build
```

Notes:

- **Do not pass `--stage-1`.**  It is faster, but `rustc-dev` (the
  `librustc_driver.so` + `.rmeta` set that crubit compiles against) is only
  produced for the default stage.  Stage 1 installs `.rmeta` without the
  matching compiler, and every crubit build then dies with
  `E0514 found crate rustc_hir compiled by an incompatible version of rustc`.
- The bundled Debian sysroot must be disabled on aarch64 (glibc 2.31 vs the
  host's 2.39 → undefined `__isoc23_strtoll`, `mallinfo2`, `arc4random`).
- `bindgen` is a separate step: `python3 tools/rust/build_bindgen.py
  --skip-llvm-build` (needs the proxy for the googlesource clone).

## 3. Crubit

    python3 tools/rust/build_crubit.py --skip-checkout --out-dir ~/crubit-out

Crubit needs `librustc_driver` **and the matching `.rmeta` files**, which are
only shipped by the `rustc-dev` dist component:

```sh
cd third_party/rust-src
python3 x.py dist --stage 2 --build aarch64-unknown-linux-gnu
# build/dist/rustc-dev-nightly-aarch64-unknown-linux-gnu.tar.xz
```

The clean way to consume it is to install `rustc`, `rust-std`, `rust-src` and
`rustc-dev` from **the same dist run** into one prefix and use that prefix as
`third_party/rust-toolchain`.  Mixing a dist `rustc-dev` with a separately
installed toolchain produces `E0460 found possibly newer version of crate
rustc_demangle` / `E0531 cannot find tuple struct Some`.

## 4. The ablsl `SourceLocation` ABI trap

Crubit's C++ objects are compiled with `-std=c++20` (its own `flags.rs`), but
Abseil's CMake pins `ABSL_OPTION_USE_STD_SOURCE_LOCATION` from "detect"(2) to
"use std"(1) when built as C++20.  The result is a split ABI:

```
crubit object : MakeErrorImpl<N>(string_view, absl::SourceLocation)
libabsl_status: MakeErrorImpl<N>(string_view, std::source_location)
```

→ `ld.lld: undefined symbol ... MakeErrorImpl`.  Force Abseil down to the
fallback class by rewriting `absl/base/options.h` **after** the tarball is
unpacked and **before** CMake configures it (`build_crubit.py` is patched to do
this for the `Abseil` project).

## 5. Extra runtime pieces the Chromium build expects

The toolchain directory must also contain, or `gn`/`ninja` will fail:

| file | source |
|---|---|
| `VERSION` | `rustc --version` output, read by `build/config/rust.gni` |
| `bin/bindgen` | `tools/rust/build_bindgen.py` |
| `bin/rustfmt` | `rustfmt-nightly` dist component (the one from an older toolchain is missing its `librustc_driver*.so`) |
| `lib/rustlib/src/rust/library/...` | `rust-src` dist component (V8/compiler-builtins build.rs) |
| `third_party/llvm-libclang/lib/libclang.so` | symlink to the system `libclang` (V8 `metagen`) |

Chromium also links `mksnapshot` referencing `__sanitizer_set_death_callback`;
`v8/src/sandbox/testing.cc` is patched with a weak no-op definition because the
sanitizer runtime is not part of this build.

## 6. Time budget (measured)

| step | time |
|---|---|
| LLVM + clang | ~55 min |
| Rust stage 2 + install | ~35 min |
| `x.py dist` (rustc-dev) | ~35 min |
| Crubit (absl+protobuf+deps) | ~25 min |
| Chromium `ninja chrome` | 6–10 h |
