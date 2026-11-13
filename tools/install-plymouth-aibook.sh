#!/bin/bash
# Install the aibook Plymouth theme (mirrors the KDE ksplash animation) and
# rebuild the initramfs.  Idempotent.
#
# Kernel cmdline requirements (see docs/plymouth-splash.md):
#   splash plymouth.ignore-serial-consoles
# Do NOT add plymouth.debug: with debug on, plymouthd takes over the console
# and the boot screen flashes text instead of the theme.
set -euo pipefail
SELF=$(cd "$(dirname "$0")" && pwd)
THEME=/usr/share/plymouth/themes/aibook
KSPLASH=${KSPLASH:-/opt/kde6/share/plasma/look-and-feel/org.aibook.splash/contents/splash/images}

[ -d "$KSPLASH" ] || { echo "ksplash images not found: $KSPLASH" >&2; exit 1; }

sudo install -d "$THEME"
sudo install -m 644 "$SELF/plymouth-aibook/aibook.plymouth" "$THEME/aibook.plymouth"
sudo install -m 644 "$SELF/plymouth-aibook/aibook.script" "$THEME/aibook.script"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
"$SELF/plymouth-aibook/gen-assets.sh" "$KSPLASH" "$WORK"
sudo install -m 644 "$WORK"/*.png "$THEME"/

sudo install -m 755 "$SELF/plymouth-aibook/hook-plymouth-aibook" /etc/initramfs-tools/hooks/plymouth-aibook
sudo update-initramfs -u

echo "installed $THEME"
echo "verify kernel cmdline contains: splash plymouth.ignore-serial-consoles"
