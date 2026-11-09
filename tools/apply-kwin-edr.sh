#!/bin/bash
# Apply the EDR peak-luminance patch to a kwin 6.8.2 source tree.
#
#   ./tools/apply-kwin-edr.sh [SRC]
#
# SRC defaults to $HOME/kde6/src/kwin-6.8.2.  Idempotent: re-running on an
# already patched tree reports "already applied" and does nothing.
set -euo pipefail

SRC=${1:-$HOME/kde6/src/kwin-6.8.2}
PATCH=$(cd "$(dirname "$0")/.." && pwd)/patches/kwin-6.8.2-edr-peak-luminance.patch

[ -d "$SRC" ] || { echo "missing source tree: $SRC"; exit 1; }
[ -f "$PATCH" ] || { echo "missing patch: $PATCH"; exit 1; }

if patch -p1 -R --dry-run -d "$SRC" -i "$PATCH" >/dev/null 2>&1; then
  echo "already applied: $SRC"
elif patch -p1 --dry-run -d "$SRC" -i "$PATCH" >/dev/null 2>&1; then
  patch -p1 -d "$SRC" -i "$PATCH"
  echo "applied: $SRC"
else
  echo "cannot apply (source tree diverged?): $SRC"
  exit 1
fi
