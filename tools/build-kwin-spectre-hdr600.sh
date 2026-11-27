#!/bin/bash
# 为 Spectre（TrueBlack HDR600, eDP-1 604 nit）构建带 BT.2390 滚降的 KWin。
#
# 背景见 notes/spectre-hdr600.md：Chromium 的 PQ surface 只声明 referenceLuminance
# (200 nit) 作为峰值，KWin 因此误判"内容不超输出能力"而跳过 tonemap，HDR1000 高光被
# 直接裁平。补丁做两件事：
#   1. PQ 内容峰值低于 reference 1.1 倍时按 HDR10 的 1000 nit 处理，强制走 BT.2390；
#   2. 把 KWin 原本的 modified Reinhard 换成 129 点 BT.2390 EETF LUT，
#      destinationReferenceLuminance 沿用 KDE 的 SDR 白（200 nit）。
# 另附 pointer_input.cpp 的判空修复，避免 InputRedirection 构造期间 libinput
# 送进 motion 事件时空指针（openSUSE #1290961，本机每次开机崩 4 次的元凶）。
#
# 用法: ./build-kwin-spectre-hdr600.sh [workdir]
# 依赖: base-devel cmake ninja extra-cmake-modules vulkan-headers
#       wayland-protocols plasma-wayland-protocols
set -euo pipefail

VER=6.8.3
WORK=${1:-$HOME/build}
PKG=kwin-$VER
PATCH_DIR="$(cd "$(dirname "$0")/../patches" && pwd)"

mkdir -p "$WORK"
cd "$WORK"

if [ ! -d "$PKG" ]; then
    echo "==> 下载 KWin $VER 源码"
    curl -fL -o "$PKG.tar.xz" "https://download.kde.org/stable/plasma/$VER/$PKG.tar.xz"
    tar xf "$PKG.tar.xz"
    echo "==> 应用补丁"
    patch -p1 -d "$PKG" < "$PATCH_DIR/kwin-$VER-spectre-hdr600.patch"
fi

echo "==> 配置"
cmake -B "$PKG/build" -S "$PKG" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF

echo "==> 编译（8 核约 15 分钟，增量 1–2 分钟）"
ninja -C "$PKG/build" -j"$(nproc)"

echo "==> 安装（覆盖 /usr/lib/libkwin.so.6 等）"
sudo ninja -C "$PKG/build" install

echo
echo "完成。重新登录后生效。"
echo "回滚: sudo pacman -U /var/cache/pacman/pkg/kwin-$VER-*.pkg.tar.zst"
echo "锁定: /etc/pacman.conf 中 IgnorePkg = kwin"
