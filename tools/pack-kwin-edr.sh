#!/bin/bash
# Build the kwin-edr overlay package.
#
# The overlay replaces only those files that already exist in /opt/kde6, so it
# can be dropped on top of an installed mtgpu-kde tree without reinstalling the
# whole desktop.  It carries the HDR/EDR patch (patches/kwin-6.8.2-edr-peak-
# luminance.patch) which advertises the panel peak luminance to clients instead
# of the hard-coded 200 nits.
set -euo pipefail

BUILD=${BUILD:-$HOME/build/kwin-hdr/build}
PREFIX=${PREFIX:-/opt/kde6}
VER=${VER:-6.8.2-mtgpu5}
OUT=${OUT:-$HOME/kde6/debs/$VER}
STAGE=$(mktemp -d "$HOME/.cache/kwin-edr.XXXXXX")

mkdir -p "$OUT"
DESTDIR="$STAGE/install" cmake --install "$BUILD" >/dev/null
SRC=$(echo "$STAGE"/install/opt/kwin-patched)
[ -d "$SRC" ] || { echo "no staged tree" >&2; exit 1; }

mkdir -p "$STAGE/pkg$PREFIX"
(cd "$SRC" && find . -type f) | while read -r f; do
  rel=${f#./}
  [ -e "$PREFIX/$rel" ] || continue          # overlay existing files only
  mkdir -p "$STAGE/pkg$PREFIX/$(dirname "$rel")"
  cp -a "$SRC/$rel" "$STAGE/pkg$PREFIX/$rel"
done

# The build tree was configured with the experimental prefix /opt/kwin-patched;
# rewrite that string in shipped text files so units/desktop files point at the
# real install prefix.
find "$STAGE/pkg" -type f \( -name '*.service' -o -name '*.desktop' -o -name '*.knsrc' -o -name '*.h' -o -name '*.cmake' -o -name '*.pc' \) \
  -exec sed -i 's#/opt/kwin-patched#/opt/kde6#g' {} +
BAD=$(grep -rl "/opt/kwin-patched" "$STAGE/pkg" 2>/dev/null | wc -l)
if [ "$BAD" -ne 0 ]; then
  echo "ERROR: $BAD staged files still reference the build-tree prefix /opt/kwin-patched" >&2
  exit 1
fi
COUNT=$(find "$STAGE/pkg" -type f | wc -l)
SIZE=$(du -sk "$STAGE/pkg" | cut -f1)
mkdir -p "$STAGE/pkg/DEBIAN"
cat > "$STAGE/pkg/DEBIAN/control" <<EOF
Package: mtgpu-kwin-edr
Version: $VER
Architecture: arm64
Maintainer: yeungtuzi <yeungtuzi@users.noreply.github.com>
Section: kde
Priority: optional
Installed-Size: $SIZE
Replaces: kde6-mtgpu-bin, kde6-mtgpu-lib, kde6-mtgpu-plugins, kde6-mtgpu-share, kde6-mtgpu-misc, kde6-mtgpu
Breaks: kde6-mtgpu-bin, kde6-mtgpu-lib, kde6-mtgpu-plugins, kde6-mtgpu-share, kde6-mtgpu-misc, kde6-mtgpu
Description: KWin 6.8.2 with the HDR/EDR peak-luminance patch (overlay for /opt/kde6)
 Ships $COUNT replacement files under $PREFIX: kwin_wayland and the pieces that
 advertise the panel peak luminance through wp_color_management_v1. Install on
 top of an existing kde6-mtgpu installation.
EOF
dpkg-deb --root-owner-group --build "$STAGE/pkg" "$OUT/mtgpu-kwin-edr_${VER}_arm64.deb" >/dev/null
rm -rf "$STAGE"
ls -la "$OUT/mtgpu-kwin-edr_${VER}_arm64.deb"
