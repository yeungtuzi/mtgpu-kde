#!/bin/bash
# Build the pieces plasma-nm needs that the base KDE6 build did not include,
# all from source into /opt/kde6 (no distro packages for the KDE bits).
#
#   ./build-plasma-nm.sh
#
# Prereqs (build-time only): libmm-glib-dev, and a working /opt/kde6 Qt6+KF6.
set -euo pipefail

KDEPREFIX=${KDEPREFIX:-/opt/kde6}
SRCROOT=${SRCROOT:-$HOME/kde6}
BUILDROOT=${BUILDROOT:-$SRCROOT/build}
CMAKE=$KDEPREFIX/bin/cmake
JOBS=$(nproc)

say() { printf '\033[1m== %s\033[0m\n' "$*"; }

[ -x "$CMAKE" ] || { echo "missing $CMAKE (system cmake is too old: needs >= 3.30)"; exit 1; }
export PATH=$KDEPREFIX/bin:$PATH

common_args=(
  -G Ninja
  -DCMAKE_INSTALL_PREFIX="$KDEPREFIX"
  -DCMAKE_PREFIX_PATH="$KDEPREFIX"
  -DCMAKE_BUILD_TYPE=Release
  -DBUILD_TESTING=OFF
)

build_install() { # <src> <build>
  local src=$1 build=$2
  if [ ! -f "$build/build.ninja" ]; then
    "$CMAKE" -S "$src" -B "$build" "${common_args[@]}"
  fi
  "$CMAKE" --build "$build" -j"$JOBS"
  sudo "$CMAKE" --install "$build"
}

say 'qtkeychain 0.16.0'
if [ ! -f "$KDEPREFIX/lib/cmake/Qt6Keychain/Qt6KeychainConfig.cmake" ]; then
  tarball=$SRCROOT/tarballs/qtkeychain-0.16.0
  if [ ! -d "$tarball" ]; then
    mkdir -p "$SRCROOT/tarballs"
    curl -fsSL -o "$SRCROOT/tarballs/qtkeychain-0.16.0.tar.gz" \
      https://github.com/frankosterfeld/qtkeychain/archive/refs/tags/0.16.0.tar.gz
    tar xf "$SRCROOT/tarballs/qtkeychain-0.16.0.tar.gz" -C "$SRCROOT/tarballs"
  fi
  "$CMAKE" -S "$tarball" -B "$tarball/build" "${common_args[@]}" \
    -DBUILD_WITH_QT6=ON -DBUILD_TEST_APPLICATION=OFF
  "$CMAKE" --build "$tarball/build" -j"$JOBS"
  sudo "$CMAKE" --install "$tarball/build"
else
  echo '   already installed'
fi

say 'modemmanager-qt'
if [ ! -f "$KDEPREFIX/lib/cmake/KF6ModemManagerQt/KF6ModemManagerQtConfig.cmake" ]; then
  dpkg -s libmm-glib-dev >/dev/null 2>&1 || \
    { echo 'need: sudo apt install libmm-glib-dev'; exit 1; }
  build_install "$SRCROOT/src/modemmanager-qt-6.31.0" "$BUILDROOT/modemmanager-qt-6.31.0"
else
  echo '   already installed'
fi

say 'plasma-nm'
if [ ! -f "$KDEPREFIX/plugins/plasma/kcms/systemsettings_qwidgets/kcm_networkmanagement.so" ]; then
  build_install "$SRCROOT/src/plasma-nm-6.8.2" "$BUILDROOT/plasma-nm-6.8.2"
else
  echo '   already installed'
fi

say 'done; restart the shell: systemctl --user restart plasma-plasmashell'
