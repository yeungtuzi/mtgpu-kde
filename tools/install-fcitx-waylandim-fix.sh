#!/usr/bin/env bash
# 为系统 fcitx5 的 waylandim 模块打上"修饰键状态回传合成器"补丁。
#
# 背景：fcitx5 的 zwp_input_method_v1 前端此前从不发送
# wp_input_method_context_v1.modifiers 请求。KWin 6.7+ 在输入法抓住键盘后
# 依赖该请求把修饰键状态同步给应用，因此 Ctrl/Shift 丢失（Ctrl+C 只出 c）。
# 修复是上游 commit a05d898f（2025-03-21），晚于最新正式版 5.1.12。
#
# 用法：
#   sudo bash tools/install-fcitx-waylandim-fix.sh          # 默认 5.1.7
#   sudo VER=5.1.12 bash tools/install-fcitx-waylandim-fix.sh
#
# 依赖网络（默认走本机代理，可用 http_proxy 覆盖）。
set -euo pipefail

VER="${VER:-5.1.7}"
WORKDIR="${WORKDIR:-$HOME/build/fcitx5-waylandim}"
TARBALL="$WORKDIR/fcitx5-${VER}.tar.gz"
SRC="$WORKDIR/src-${VER}"
DEST="/usr/lib/aarch64-linux-gnu/fcitx5/libwaylandim.so"
PATCH_DIR="$(cd "$(dirname "$0")/.." && pwd)/patches"
PROXY="${http_proxy:-http://192.168.100.4:1080}"
BASE="https://github.com/fcitx/fcitx5/archive/refs/tags/${VER}.tar.gz"

if [ "$(id -u)" -ne 0 ]; then
    echo "请用 sudo 运行" >&2
    exit 1
fi

echo "== 1/6 安装构建依赖"
apt-get install -y --no-install-recommends \
    build-essential cmake ninja-build gettext \
    libjson-c-dev libxkbcommon-dev libwayland-dev libdbus-1-dev \
    libfmt-dev libsystemd-dev extra-cmake-modules >/dev/null

echo "== 2/6 下载 fcitx5 ${VER} 源码（持久目录 ${WORKDIR}，不用 /tmp）"
mkdir -p "$WORKDIR"
[ -f "$TARBALL" ] || curl -sL --proxy "$PROXY" -o "$TARBALL" "$BASE"
rm -rf "$SRC"
mkdir -p "$SRC"
tar xf "$TARBALL" -C "$SRC" --strip-components=1

echo "== 3/6 应用上游补丁 a05d898f"
patch -d "$SRC" -p1 < "$PATCH_DIR/fcitx5-5.1.7-waylandim-modifiers.patch"

echo "== 4/6 构建 waylandim 模块"
cmake -S "$SRC" -B "$SRC/build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_X11=OFF -DENABLE_WAYLAND=ON -DENABLE_DBUS=ON \
    -DENABLE_ENCHANT=OFF -DENABLE_PANGO=OFF -DENABLE_CAIRO=OFF \
    -DENABLE_EMOJI=OFF -DENABLE_SPELL=OFF -DENABLE_TEST=OFF >/dev/null
ninja -C "$SRC/build" waylandim >/dev/null
MODULE="$SRC/build/src/frontend/waylandim/libwaylandim.so"
[ -f "$MODULE" ] || { echo "构建产物缺失: $MODULE" >&2; exit 1; }

echo "== 5/6 备份并安装（dpkg-divert，防止包升级覆盖）"
[ -f "${DEST}.orig" ] || cp -a "$DEST" "${DEST}.orig"
dpkg-divert --local --rename \
    --divert "${DEST}.pkg" \
    --add "$DEST" >/dev/null 2>&1 || true
cp "$MODULE" "$DEST"
chmod 644 "$DEST"
apt-mark hold fcitx5-modules >/dev/null 2>&1 || true

echo "== 6/6 校验"
ldd "$DEST" | grep -q "not found" && { echo "存在未解析依赖" >&2; exit 1; } || true
echo "已安装: $DEST"
echo "备份:   ${DEST}.orig（包管理原件）/ ${DEST}.pkg（divert 目标）"
echo
echo "之后注销重登（或重启）让 KWin 用它自己的 socket 拉起 fcitx5，再验证："
echo "  Ctrl+C / Shift+字母 / 单按 Shift 切中英 / Brave 原生 Wayland 中文"
echo
echo "回滚："
echo "  sudo dpkg-divert --remove $DEST"
echo "  sudo cp -a ${DEST}.orig $DEST && sudo apt-mark unhold fcitx5-modules"
