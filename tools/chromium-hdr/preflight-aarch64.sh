#!/bin/bash
# Fail fast if anything in the toolchain would drag an x86-64 (FEX) tool into
# the aarch64 build. Run before starting the Chromium toolchain build.
set -uo pipefail
SRC="${1:-$HOME/chromium-build/src}"
fail=0
note() { printf '%-46s %s\n' "$1" "$2"; }

note "host arch" "$(uname -m)"
[ "$(uname -m)" = "aarch64" ] || { echo "  -> not an aarch64 host"; fail=1; }

PC="$SRC/third_party/llvm-build-tools/pinned-clang/bin"
t=$("$PC/clang++" --version 2>/dev/null | sed -n 's/^Target: //p' | head -1)
note "pinned clang target" "$t"
[ "$t" = "aarch64-unknown-linux-gnu" ] || { echo "  -> clang is not native"; fail=1; }

for d in "$SRC/third_party/llvm-build-tools/pinned-clang" \
         "$SRC/third_party/rust-toolchain-intermediate" ; do
  n=$(find "$d" -type f -executable 2>/dev/null | head -400 | xargs -r file 2>/dev/null | grep -c 'x86-64')
  note "x86-64 ELF in $(basename "$d")" "$n"
  [ "$n" = "0" ] || { echo "  -> replace/stub those binaries"; fail=1; }
done

grep -q "aarch64-unknown-linux-gnu" "$SRC/tools/rust/build_rust.py" \
  && note "RustTargetTriple patched" "yes" || { note "RustTargetTriple patched" "no"; fail=1; }
grep -q "MTGPU_PINNED_CLANG" "$SRC/tools/clang/scripts/build.py" \
  && note "pinned-clang download guard" "yes" || { note "pinned-clang download guard" "no"; fail=1; }
grep -q "target.aarch64-unknown-linux-gnu" "$SRC/tools/rust/config.toml.template" \
  && note "rust config has aarch64 target" "yes" || { note "rust config has aarch64 target" "no"; fail=1; }

if [ "$fail" = "0" ]; then echo "PREFLIGHT-OK"; else echo "PREFLIGHT-FAILED"; exit 1; fi
