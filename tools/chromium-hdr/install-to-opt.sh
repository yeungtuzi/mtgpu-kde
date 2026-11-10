#!/bin/bash
# Install a self-contained Chromium build from out/<dir> into /opt/chromium-hdr.
# Does not touch the system Chrome/Chromium packages.
set -euo pipefail

SRC="${1:-$HOME/chromium-build/src/out/hdr}"
DST="${2:-/opt/chromium-hdr}"

[ -x "$SRC/chrome" ] || { echo "no chrome binary in $SRC" >&2; exit 1; }

sudo mkdir -p "$DST"
sudo rsync -a --delete "$SRC/" "$DST/" \
  --exclude 'obj/' --exclude '*.ninja' --exclude 'CMakeFiles/' \
  --exclude 'gen/' --exclude '.ninja_*'

sudo tee /usr/share/applications/chromium-hdr.desktop >/dev/null <<EOF
[Desktop Entry]
Type=Application
Name=Chromium (EDR build)
Comment=Source-built Chromium with KWin headroom diagnostics
Exec=$DST/chrome %U
Icon=chromium
Terminal=false
Categories=Network;WebBrowser;
EOF

cat <<EOF
installed to $DST
launch: $DST/chrome --ozone-platform=wayland
describe: cat /usr/share/applications/chromium-hdr.desktop
uninstall: sudo rm -rf $DST /usr/share/applications/chromium-hdr.desktop
EOF
