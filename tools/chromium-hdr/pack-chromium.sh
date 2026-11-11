#!/bin/bash
# Package the locally built Chromium into a deb that installs *only* under
# /opt/mtgpu-chromium and does not touch the distribution's google-chrome.
set -euo pipefail

SRC=${SRC:-$HOME/chromium-build/src/out/hdr}
OUT=${OUT:-$HOME/chromium-build/debs}
VER=${VER:-157.0.8103.38}
ROOT=/opt/mtgpu-chromium
STAGE=$(mktemp -d "$HOME/.cache/mtgpu-chromium.XXXXXX")

die() { echo "error: $*" >&2; exit 1; }
[ -x "$SRC/chrome" ] || die "no chrome at $SRC"
mkdir -p "$OUT"

mkdir -p "$STAGE$ROOT" "$STAGE/usr/share/applications" "$STAGE/usr/bin"
# Runtime payload, keeping the flat layout Chromium expects next to the binary.
for f in chrome chrome_crashpad_handler chrome_sandbox chrome_100_percent.pak \
         chrome_200_percent.pak headless_command_resources.pak resources.pak \
         icudtl.dat snapshot_blob.bin v8_context_snapshot.bin \
         libEGL.so libGLESv2.so libvk_swiftshader.so vk_swiftshader_icd.json; do
  [ -e "$SRC/$f" ] && cp -a "$SRC/$f" "$STAGE$ROOT/" || true
done
cp -a "$SRC/locales" "$SRC/resources" "$STAGE$ROOT/"

# Debug symbols are not needed at runtime and dominate the size.
strip --strip-debug "$STAGE$ROOT/chrome" 2>/dev/null || true
strip --strip-debug "$STAGE$ROOT/chrome_crashpad_handler" 2>/dev/null || true

cat > "$STAGE$ROOT/chrome-wrapper" <<'EOF'
#!/bin/sh
# Wrapper for the mtgpu Chromium build: Wayland + compositor (KWin) HDR.
exec /opt/mtgpu-chromium/chrome \
  --ozone-platform=wayland \
  --enable-features=UseDisplaySDRMaxLuminanceNits \
  --user-data-dir="${HOME}/.config/mtgpu-chromium" \
  --no-first-run "$@"
EOF
chmod 755 "$STAGE$ROOT/chrome-wrapper"
ln -sf "$ROOT/chrome-wrapper" "$STAGE/usr/bin/mtgpu-chromium"

cat > "$STAGE/usr/share/applications/mtgpu-chromium.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Chromium (mtgpu, HDR)
Comment=Locally built Chromium 157 for aarch64 with KWin HDR headroom
Exec=/opt/mtgpu-chromium/chrome-wrapper %U
Terminal=false
Categories=Network;WebBrowser;
MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;
StartupWMClass=Chromium
EOF

mkdir -p "$STAGE/DEBIAN"
cat > "$STAGE/DEBIAN/control" <<EOF
Package: mtgpu-chromium
Version: $VER
Architecture: arm64
Maintainer: mtgpu project <noreply@localhost>
Section: web
Priority: optional
Conflicts: google-chrome-stable
Description: Chromium $VER for aarch64 (mtgpu local build)
 Installed under $ROOT as /usr/bin/mtgpu-chromium. The distribution's
 google-chrome package is not modified.
EOF
# chrome_sandbox must be setuid root; do it at configure time because the
# staging tree is built root-owned but dpkg keeps the modes it finds.
cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
[ -f /opt/mtgpu-chromium/chrome_sandbox ] && chmod 4755 /opt/mtgpu-chromium/chrome_sandbox || true
exit 0
EOF
chmod 755 "$STAGE/DEBIAN/postinst"

dpkg-deb --build --root-owner-group "$STAGE" "$OUT/mtgpu-chromium_${VER}_arm64.deb" >/dev/null
rm -rf "$STAGE"
ls -la "$OUT/mtgpu-chromium_${VER}_arm64.deb"
