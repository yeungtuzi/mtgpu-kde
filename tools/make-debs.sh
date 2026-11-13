#!/bin/bash
# Package the whole /opt/kde6 prefix into .deb files, one per top-level area,
# plus a meta package.  All files stay under /opt/kde6.
#
#   ./tools/make-debs.sh [version]
#
# Output: $OUTDIR (default ~/kde6/debs/<version>)/*.deb + SHA256SUMS
set -euo pipefail

PREFIX=${PREFIX:-/opt/kde6}
VERSION=${1:-6.8.2-mtgpu8}
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

# ---------------------------------------------------------------------------
# session 包：/usr 侧只放软链与启动入口（wayland session、systemd user units、
# polkit actions、dbus system.d）。没有它，用户装完进不了会话，亮度/EDR 也会坏。
say "stage session"
sdir="$WORK/session"
mkdir -p "$sdir/usr/share/wayland-sessions" "$sdir/usr/share/mtgpu-kde" "$sdir/DEBIAN"
if [ -f "$PREFIX/share/wayland-sessions/plasma6-kde6.desktop" ]; then
  cp -a "$PREFIX/share/wayland-sessions/plasma6-kde6.desktop" "$sdir/usr/share/wayland-sessions/"
fi
cp -a "$(dirname "$0")/kde6-integration-symlinks.sh" "$sdir/usr/share/mtgpu-kde/"
cat > "$sdir/DEBIAN/postinst" <<'POSTINST'
#!/bin/sh
set -e
[ "$1" = configure ] || exit 0
if [ -x /usr/share/mtgpu-kde/kde6-integration-symlinks.sh ]; then
  KDEPREFIX=/opt/kde6 /usr/share/mtgpu-kde/kde6-integration-symlinks.sh || true
fi
exit 0
POSTINST
cat > "$sdir/DEBIAN/prerm" <<'PRERM'
#!/bin/sh
set -e
[ "$1" = remove ] || [ "$1" = purge ] || exit 0
for f in /usr/lib/systemd/user/plasma-*.service /usr/lib/systemd/user/plasma-*.target; do
  [ -L "$f" ] || continue
  case "$(readlink -f "$f" 2>/dev/null)" in /opt/kde6/*) rm -f "$f" ;; esac
done
for d in /usr/share/polkit-1/actions /usr/share/dbus-1/system.d; do
  for f in "$d"/*; do
    [ -L "$f" ] || continue
    case "$(readlink -f "$f" 2>/dev/null)" in /opt/kde6/*) rm -f "$f" ;; esac
  done
done
rm -f /usr/share/wayland-sessions/plasma6-kde6.desktop
exit 0
PRERM
chmod 755 "$sdir/DEBIAN/postinst" "$sdir/DEBIAN/prerm"
make_control "$sdir" "kde6-mtgpu-session" "$ARCH" "session integration (symlinks)" \
  "network-manager, bluez, pipewire-pulse | pulseaudio, libcanberra0"
say "build kde6-mtgpu-session"
dpkg-deb --root-owner-group --build "$sdir" "$OUTDIR/kde6-mtgpu-session_${VERSION}_${ARCH}.deb" >/dev/null

# meta package
meta="$WORK/meta"
mkdir -p "$meta/DEBIAN"
deps="kde6-mtgpu-session (= $VERSION)"
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
