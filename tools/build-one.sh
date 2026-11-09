#!/bin/bash
# build-one.sh <source-dir> [extra cmake args...]
set -euo pipefail
src="$1"; shift || true
name="$(basename "$src")"
prefix=${KDEPREFIX:-/opt/kde6}
root=${SRCROOT:-$HOME/kde6}
build="$root/build/$name"
mkdir -p "$build"
cd "$build"
export CC=gcc-15 CXX=g++-15
cmake -G Ninja "$src" \
  -DCMAKE_INSTALL_PREFIX="$prefix" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=gcc-15 -DCMAKE_CXX_COMPILER=g++-15 \
  -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
  -DCMAKE_C_FLAGS="-O2 -march=native -mtune=native -pipe" \
  -DCMAKE_CXX_FLAGS="-O2 -march=native -mtune=native -pipe" \
  -DCMAKE_PREFIX_PATH="$prefix" \
  -DCMAKE_INSTALL_RPATH="$prefix/lib" \
  -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DKDE_INSTALL_LIBDIR=lib \
  -DBUILD_TESTING=OFF -DBUILD_PYTHON_BINDINGS=OFF \
  "$@"
ninja -j"$(nproc)"
ninja install
touch "$build/.built"
