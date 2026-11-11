# mtgpu toolchain packages

Two self-contained debs, both installed under `/opt/mtgpu-toolchain`:

| package | contents | install path |
|---|---|---|
| `mtgpu-clang` | LLVM 24 (AArch64-only build), clang, lld | `/opt/mtgpu-toolchain/clang` |
| `mtgpu-rust` | rustc 1.100-nightly (1edd55dcf), std, cargo, bindgen 0.73, crubit (`cc_bindings_from_rs`, `rs_bindings_from_cc`) | `/opt/mtgpu-toolchain/rust` |

## Guarantees

- Nothing is written outside `/opt`.
- No `dpkg` alternatives, no `/etc/profile.d`, no system `PATH` changes.
- No dependencies are declared (`Depends:` empty), so installing/removing them
  cannot pull in or remove system packages.
- Removal is `dpkg -r mtgpu-clang mtgpu-rust` (or `rm -rf /opt/mtgpu-toolchain`).

## Usage

```sh
source /opt/mtgpu-toolchain/env.sh   # only affects the current shell
clang --version
rustc --version
```

## How they were built

See `tools/chromium-hdr/README.md` in this repository: the LLVM build uses
`--disable-asserts --no-tools --no-runtimes --pic --without-zstd`, an
AArch64-only backend, `-DLLVM_ENABLE_LIBXML2=OFF` and `-O1` release flags; the
Rust toolchain is Chromium's `tools/rust/build_rust.py` with the aarch64 host
patches documented there, plus `x.py dist` for the `rustc-dev` component that
crubit needs.
