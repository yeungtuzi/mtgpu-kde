#!/bin/bash
# 用 KDE6/Plasma 6.8.2 源码补回被移除的 Plasma 5 组件（全部装进 /opt/kde6）。
#
#   ./build-kde6-extras.sh all        # 全部
#   ./build-kde6-extras.sh bluezqt plasma-nm plasma-pa bluedevil kinfocenter fcitx5
#
# 前提：/opt/kde6 的 Qt6/KF6 可用；源码在 $SRCROOT/src（缺则从 download.kde.org 下载）。
# 说明：
#   * bluez-qt 必须带 CMAKE_PREFIX_PATH=/opt/kde6 配置，否则 Qt6Qml 找不到，
#     src/imports（org.kde.bluezqt QML 模块）会被跳过，蓝牙 applet 报
#     "module org.kde.bluezqt is not installed"。
#   * kinfocenter 6.8 的 kcms/energy 需要 Qt6::Graphs（本机未编 Qt Graphs），
#     脚本会跳过该 KCM；KDE6 里 `kinfocenter` 是 `systemsettings` 的软链。
#   * fcitx5-configtool 需要 fcitx5-qt 的 Fcitx5Qt6DBusAddons；本机 Qt 未带
#     private 头，故 fcitx5-qt 只编 dbusaddons/widgetsaddons（跳过
#     platforminputcontext 与 immodule-probing）。
set -euo pipefail

PREFIX=${KDEPREFIX:-/opt/kde6}
SRCROOT=${SRCROOT:-$HOME/kde6/src}
BUILDROOT=${BUILDROOT:-$HOME/kde6/build}
CMAKE=$PREFIX/bin/cmake
JOBS=$(nproc)
export PATH=$PREFIX/bin:$PATH
export CC=${CC:-gcc-15} CXX=${CXX:-g++-15}

say() { printf '\033[1m== %s\033[0m\n' "$*"; }

fetch() { # <name-version>
  local n=$1
  [ -d "$SRCROOT/$n" ] && return 0
  mkdir -p "$SRCROOT"
  say "download $n"
  curl -fsSL -o "$SRCROOT/$n.tar.xz" "https://download.kde.org/stable/plasma/6.8.2/$n.tar.xz"
  tar xf "$SRCROOT/$n.tar.xz" -C "$SRCROOT"
}

build_install() { # <srcdir> <builddir> [extra cmake args...]
  local src=$1 build=$2; shift 2
  "$CMAKE" -S "$src" -B "$build" -G Ninja \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_PREFIX_PATH="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
    -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache "$@"
  "$CMAKE" --build "$build" -j"$JOBS"
  sudo "$CMAKE" --install "$build"
}

do_bluezqt() {
  say 'bluez-qt (with QML imports)'
  build_install "$SRCROOT/bluez-qt-6.31.0" "$BUILDROOT/bluez-qt-6.31.0"
}

do_plasma_nm() { say 'plasma-nm'; fetch plasma-nm-6.8.2; build_install "$SRCROOT/plasma-nm-6.8.2" "$BUILDROOT/plasma-nm-6.8.2"; }
do_plasma_pa() { say 'plasma-pa'; build_install "$SRCROOT/plasma-pa-6.8.2" "$BUILDROOT/plasma-pa-6.8.2"; }
do_bluedevil() { say 'bluedevil'; fetch bluedevil-6.8.2; build_install "$SRCROOT/bluedevil-6.8.2" "$BUILDROOT/bluedevil-6.8.2"; }

do_kinfocenter() {
  say 'kinfocenter (skip energy KCM: needs Qt6::Graphs)'
  fetch kinfocenter-6.8.2
  sed -i '/^    Graphs$/d' "$SRCROOT/kinfocenter-6.8.2/CMakeLists.txt"
  sed -i 's|^ *add_subdirectory(energy)|#add_subdirectory(energy)|' \
    "$SRCROOT/kinfocenter-6.8.2/kcms/CMakeLists.txt"
  build_install "$SRCROOT/kinfocenter-6.8.2" "$BUILDROOT/kinfocenter-6.8.2" -DBUILD_DOC=OFF
}

do_fcitx5() {
  say 'fcitx5-qt (Qt6 addons only) + fcitx5-configtool (KF6 KCM)'
  if [ ! -d "$SRCROOT/fcitx5-qt-5.1.7" ]; then
    curl -fsSL -o "$SRCROOT/fcitx5-qt-5.1.7.tar.gz" \
      https://github.com/fcitx/fcitx5-qt/archive/refs/tags/5.1.7.tar.gz
    tar xzf "$SRCROOT/fcitx5-qt-5.1.7.tar.gz" -C "$SRCROOT"
  fi
  sed -i 's|^add_subdirectory(platforminputcontext)|#add_subdirectory(platforminputcontext)|' \
    "$SRCROOT/fcitx5-qt-5.1.7/qt6/CMakeLists.txt"
  sed -i 's|^if (ENABLE_QT6_WAYLAND_WORKAROUND)|if (FALSE)|' "$SRCROOT/fcitx5-qt-5.1.7/qt6/CMakeLists.txt"
  sed -i 's|^  add_subdirectory(immodule-probing)|  #add_subdirectory(immodule-probing)|' \
    "$SRCROOT/fcitx5-qt-5.1.7/qt6/CMakeLists.txt"
  build_install "$SRCROOT/fcitx5-qt-5.1.7" "$BUILDROOT/fcitx5-qt-5.1.7" -DENABLE_QT5=OFF -DENABLE_QT6=ON

  if [ ! -d "$SRCROOT/fcitx5-configtool-5.1.8" ]; then
    curl -fsSL -o "$SRCROOT/fcitx5-configtool-5.1.8.tar.gz" \
      https://github.com/fcitx/fcitx5-configtool/archive/refs/tags/5.1.8.tar.gz
    tar xzf "$SRCROOT/fcitx5-configtool-5.1.8.tar.gz" -C "$SRCROOT"
  fi
  build_install "$SRCROOT/fcitx5-configtool-5.1.8" "$BUILDROOT/fcitx5-configtool-5.1.8" -DENABLE_TEST=OFF
}

targets=${*:-all}
for t in $targets; do
  case $t in
    all) do_bluezqt; do_plasma_nm; do_plasma_pa; do_bluedevil; do_kinfocenter; do_fcitx5 ;;
    bluezqt) do_bluezqt ;;
    plasma-nm) do_plasma_nm ;;
    plasma-pa) do_plasma_pa ;;
    bluedevil) do_bluedevil ;;
    kinfocenter) do_kinfocenter ;;
    fcitx5) do_fcitx5 ;;
    *) echo "unknown target: $t"; exit 1 ;;
  esac
done
echo 'done; 注销重登以加载新 applet/KCM'
