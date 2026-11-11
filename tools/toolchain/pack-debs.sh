#!/bin/bash
# Build the two toolchain debs that ship with the mtgpu-* projects.
#
#   mtgpu-clang_<ver>_arm64.deb  -> /opt/mtgpu-toolchain/clang  (LLVM/clang/lld)
#   mtgpu-rust_<ver>_arm64.deb   -> /opt/mtgpu-toolchain/rust   (rustc/cargo/std/bindgen/crubit)
#
# Nothing is written outside /opt, no alternatives are registered, and the
# packages declare no dependencies, so they cannot disturb the system clang or
# rustc shipped by the distribution.
set -euo pipefail

SRC=${SRC:-$HOME/chromium-build/src}
LLVM=${LLVM:-$SRC/third_party/rust-toolchain-intermediate/llvm-host-install}
RUST=${RUST:-$SRC/third_party/rust-toolchain}
OUT=${OUT:-$HOME/chromium-build/debs}
CLANG_VER=${CLANG_VER:-24.0.0}
RUST_VER=${RUST_VER:-1.100.0-nightly}
ROOT=/opt/mtgpu-toolchain

die() { echo "error: $*" >&2; exit 1; }
[ -d "$LLVM/bin" ] || die "no LLVM install at $LLVM"
[ -x "$RUST/bin/rustc" ] || die "no rust toolchain at $RUST"
mkdir -p "$OUT"

pack() {  # name version payload_dir install_subdir
  local name=$1 ver=$2 payload=$3 sub=$4 stage
  stage=$(mktemp -d "$HOME/.cache/mtgpu-pkg.XXXXXX")
  mkdir -p "$stage/DEBIAN" "$stage$ROOT"
  cp -a "$payload" "$stage$ROOT/$sub"
  cat > "$stage/DEBIAN/control" <<EOF
Package: $name
Version: $ver
Architecture: arm64
Maintainer: mtgpu project <noreply@localhost>
Section: devel
Priority: optional
Description: $name for aarch64 (mtgpu toolchain distribution)
 Installed under $ROOT/$sub. Does not replace or register the system toolchain.
EOF
  dpkg-deb --build --root-owner-group "$stage" "$OUT/${name}_${ver}_arm64.deb" >/dev/null
  rm -rf "$stage"
  echo "built $OUT/${name}_${ver}_arm64.deb"
}

pack mtgpu-clang "$CLANG_VER" "$LLVM" clang
pack mtgpu-rust  "$RUST_VER"  "$RUST" rust

# Shared env helper, installed by both packages.
tmp=$(mktemp -d "$HOME/.cache/mtgpu-env.XXXXXX")
mkdir -p "$tmp"
cat > "$tmp/env.sh" <<'EOF'
# Source this to use the mtgpu toolchain in the current shell.
export MTGPU_TOOLCHAIN=/opt/mtgpu-toolchain
export PATH="$MTGPU_TOOLCHAIN/clang/bin:$MTGPU_TOOLCHAIN/rust/bin:$PATH"
export LD_LIBRARY_PATH="$MTGPU_TOOLCHAIN/rust/lib:$MTGPU_TOOLCHAIN/clang/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
EOF
rm -rf "$tmp"
ls -la "$OUT"
