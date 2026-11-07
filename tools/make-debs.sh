#!/bin/bash
# Package the whole /opt/kde6 prefix into .deb files, one per top-level area,
# plus a meta package.  All files stay under /opt/kde6.
#
#   ./tools/make-debs.sh [version]
#
# Output: $OUTDIR (default ~/kde6/debs/<version>)/*.deb + SHA256SUMS
set -euo pipefail

PREFIX=${PREFIX:-/opt/kde6}
VERSION=${1:-6.8.2-mtgpu2}
OUTDIR=${OUTDIR:-$HOME/kde6/debs/$VERSION}
WORK=${WORK:-$HOME/kde6/debs/.stage-$VERSION}
ARCH=arm64
MAINTAINER="yeungtuzi <yeungtuzi@users.noreply.github.com>"

# kind:path(s).  "misc" also takes the leftover top-level directories so no
# installed file is silently dropped.
declare -A AREA=(
  [bin]=bin
  [include]=include
  [lib]=lib
  [metatypes]=metatypes
  [plugins]=plugins
  [qml]=qml
  [share]=share
  [translations]=translations
  [misc]="env.sh session.env doc etc libexec mkspecs modules phrasebooks sbom"
)

say() { printf '\033[1m== %s\033[0m\n' "$*"; }

[ -d "$PREFIX" ] || { echo "missing $PREFIX"; exit 1; }
mkdir -p "$OUTDIR"
if [ "${NO_STAGE:-0}" != 1 ]; then
  rm -rf "$WORK"
  mkdir -p "$WORK"
fi

installed_kb() { du -sk "$1" | cut -f1; }

make_control() { # <dir> <pkg> <arch> <desc> [depends]
  local dir=$1 pkg=$2 arch=$3 desc=$4 depends=${5:-}
  mkdir -p "$dir/DEBIAN"
  {
    echo "Package: $pkg"
    echo "Version: $VERSION"
    echo "Architecture: $arch"
    echo "Maintainer: $MAINTAINER"
    echo "Section: kde"
    echo "Priority: optional"
    if [ -d "$dir/opt" ]; then echo "Installed-Size: $(installed_kb "$dir/opt")"; else echo "Installed-Size: 0"; fi
    [ -n "$depends" ] && echo "Depends: $depends"
    echo "Description: KDE Plasma 6.8.2 for MTGPU (arm64) - $desc"
    echo " Built from source into /opt/kde6; this package ships the $desc part."
  } > "$dir/DEBIAN/control"
}

if [ "${NO_STAGE:-0}" != 1 ]; then
for kind in "${!AREA[@]}"; do
  say "stage $kind"
  root="$WORK/$kind/opt/kde6"
  mkdir -p "$root"
  for rel in ${AREA[$kind]}; do
    [ -e "$PREFIX/$rel" ] || continue
    tar -C "$PREFIX" -cf - "$rel" | tar -C "$root" -xf -
  done
done
fi

# drop editor/backup leftovers that must not ship
find "$WORK" -name "*.bak" -o -name "*.bak2" | while read -r f; do rm -f "$f"; done

for kind in "${!AREA[@]}"; do
  dir="$WORK/$kind"
  make_control "$dir" "kde6-mtgpu-$kind" "$ARCH" "$kind"
  say "build kde6-mtgpu-$kind"
  dpkg-deb --root-owner-group --build "$dir" "$OUTDIR/kde6-mtgpu-${kind}_${VERSION}_${ARCH}.deb" >/dev/null
done

# meta package
meta="$WORK/meta"
mkdir -p "$meta/DEBIAN"
deps=""
for kind in "${!AREA[@]}"; do
  deps="${deps:+$deps, }kde6-mtgpu-$kind (= $VERSION)"
done
make_control "$meta" kde6-mtgpu all "meta package" "$deps"
say "build kde6-mtgpu (meta)"
dpkg-deb --root-owner-group --build "$meta" "$OUTDIR/kde6-mtgpu_${VERSION}_all.deb" >/dev/null

( cd "$OUTDIR" && sha256sum ./*.deb > SHA256SUMS )

say "done"
ls -lh "$OUTDIR"
du -sh "$OUTDIR"
echo "staging kept at $WORK (delete manually to reclaim space)"
