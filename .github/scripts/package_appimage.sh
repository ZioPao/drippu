#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 suyu Emulator Project
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Build a self-contained AppImage from a packaged Linux payload.
#
# Usage: package_appimage.sh [input] [output]
#   input   payload directory (default: _pkg) or a .tar.gz to extract
#   output  AppImage to write (default: drippu-linux-x86_64.AppImage)
set -euo pipefail

input="${1:-_pkg}"
output="${2:-drippu-linux-x86_64.AppImage}"

appimagetool_version="1.9.1"
appimagetool_url="https://github.com/AppImage/appimagetool/releases/download/${appimagetool_version}/appimagetool-x86_64.AppImage"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
appdir="$repo_root/AppDir"

# Assemble the AppDir. Hardlink-copy so the payload used for the tarball stays
# untouched, and fall back to a real copy if hardlinks are unavailable.
rm -rf "$appdir"
if [[ "$input" == *.tar.gz ]]; then
  mkdir -p "$appdir"
  tar -xzf "$input" -C "$appdir"
elif [ -d "$input" ]; then
  if ! cp -al "$input" "$appdir" 2>/dev/null; then
    # A partial hardlink copy can leave AppDir behind on cross-device errors.
    rm -rf "$appdir"
    cp -a "$input" "$appdir"
  fi
else
  echo "package_appimage.sh: input payload not found: $input" >&2
  exit 1
fi

# --- AppDir metadata: an executable AppRun, exactly one root .desktop file,
# and an icon whose basename matches the desktop file's Icon= value.
sed -e 's/^TryExec=suyu/TryExec=drippu/' -e 's/^Exec=suyu/Exec=drippu/' \
  "$repo_root/dist/dev.suyu_emu.suyu.desktop" > "$appdir/drippu.desktop"
cp "$repo_root/dist/drippu.svg" "$appdir/drippu.svg"
cp "$repo_root/dist/qt_themes/default/icons/256x256/drippu.png" "$appdir/drippu.png"
cp "$appdir/drippu.png" "$appdir/.DirIcon"

cat > "$appdir/AppRun" << 'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/drippu" "$@"
EOF
chmod +x "$appdir/AppRun"

# --- Pack. APPIMAGE_EXTRACT_AND_RUN avoids needing libfuse2 on the runner.
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

wget -q -O "$workdir/appimagetool" "$appimagetool_url"
chmod +x "$workdir/appimagetool"

ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 \
  "$workdir/appimagetool" -n "$appdir" "$output"
