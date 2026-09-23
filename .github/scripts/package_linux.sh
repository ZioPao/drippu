#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 suyu Emulator Project
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Assemble a self-contained Linux release package from a completed build.
#
# Usage: package_linux.sh [build_dir] [output_archive]
#   build_dir       CMake build directory (default: build)
#   output_archive  release tarball to write  (default: drippu-linux-x64.tar.gz)
set -euo pipefail

build_dir="${1:-build}"
output="${2:-drippu-linux-x64.tar.gz}"

rm -rf _pkg && mkdir -p _pkg/lib
cp "$build_dir/bin/suyu" _pkg/drippu
cp "$build_dir/bin/suyu-cmd" _pkg/drippu-cmd 2>/dev/null || true

# --- Bundle non-base runtime libraries (linked deps, found via ldd)
EXCLUDE_REGEX='^(linux-vdso|ld-linux|libc\.so|libm\.so|libpthread\.so|libdl\.so|librt\.so|libresolv\.so|libnsl\.so|libutil\.so|libgcc_s\.so|libstdc\+\+\.so|libGL\.so|libGLX\.so|libGLdispatch\.so|libEGL\.so|libvulkan\.so|libX11\.so|libXext\.so|libXrandr\.so|libXcursor\.so|libXi\.so|libXfixes\.so|libxcb\.|libwayland-|libdrm\.so|libgbm\.so)'
: "${EXCLUDE_REGEX:?EXCLUDE_REGEX must be set}"

declare -A seen
collect_deps() {
  ldd "$1" 2>/dev/null | awk '{print $3}' | grep -E '^/' || true
}

bundle_recursive() {
  local queue
  queue=$(collect_deps "$1")
  while [ -n "$queue" ]; do
    local next=""
    for lib in $queue; do
      local name
      name=$(basename "$lib")
      if [[ -z "${seen[$name]:-}" ]] && ! echo "$name" | grep -qE "$EXCLUDE_REGEX"; then
        seen[$name]=1
        cp -v "$lib" _pkg/lib/
        next="$next $(collect_deps "$lib")"
      fi
    done
    queue="$next"
  done
}

bundle_recursive _pkg/drippu
[ -f _pkg/drippu-cmd ] && bundle_recursive _pkg/drippu-cmd

echo "Bundled libraries:"
ls -la _pkg/lib

# --- Bundle Qt plugins. These are dlopen'd at runtime, not linked, so
# ldd never sees them - this is a separate discovery mechanism from the
# block above and must be handled independently. qt.conf below replaces
# Qt's compiled-in plugin path, so every plugin the app may load (TLS,
# Wayland shell/buffer integrations, imageformats, iconengines, ...)
# must be bundled, not just platforms/ and xcbglintegrations/.
# Discover the plugin directory at runtime: on Ubuntu 24.04 libqxcb.so
# ships in libqt6gui6t64 while the remaining QPA plugins live in
# qt6-qpa-plugins, so hardcoding a package name is not reliable.
QT_PLUGINS_DIR="$(qtpaths6 --plugin-dir 2>/dev/null || true)"
if [ -z "${QT_PLUGINS_DIR:-}" ] || [ ! -d "$QT_PLUGINS_DIR/platforms" ]; then
  QT_PLUGINS_DIR="$(dirname "$(find /usr/lib -type f -path '*/qt6/plugins/platforms/libqxcb.so' -print -quit)")/.."
fi
: "${QT_PLUGINS_DIR:?Qt plugin directory not found}"
test -d "$QT_PLUGINS_DIR/platforms"

rm -rf _pkg/plugins
mkdir -p _pkg/plugins
cp -a "$QT_PLUGINS_DIR"/. _pkg/plugins/
# Drop compositor/server-only plugins a desktop client can never use.
rm -rf _pkg/plugins/wayland-graphics-integration-server \
       _pkg/plugins/wayland-decoration-server

while IFS= read -r p; do
  bundle_recursive "$p"
done < <(find _pkg/plugins -type f -name '*.so')

# Fail CI loudly if an essential plugin was not packaged, instead of
# letting users hit "no TLS backend" / "no shell integration" at runtime.
for required in \
  plugins/platforms/libqxcb.so \
  plugins/tls/libqopensslbackend.so \
  plugins/wayland-shell-integration/libxdg-shell.so \
  plugins/wayland-graphics-integration-client/libqt-plugin-wayland-egl.so; do
  test -f "_pkg/$required" || { echo "missing Qt plugin: $required"; exit 1; }
done

cat > _pkg/qt.conf << 'EOF'
[Paths]
Prefix = .
Plugins = plugins
EOF

# --- Point every bundled binary/library/plugin at ./lib via RPATH.
# RPATH does NOT cascade to a library's own dependencies - each file that
# itself has NEEDED entries must be patched individually, or resolution
# silently falls through to the (mismatched) system libs.
patchelf --set-rpath '$ORIGIN/lib' _pkg/drippu
[ -f _pkg/drippu-cmd ] && patchelf --set-rpath '$ORIGIN/lib' _pkg/drippu-cmd

for f in _pkg/lib/*.so*; do
  patchelf --set-rpath '$ORIGIN' "$f" 2>/dev/null || true
done

# Every Qt plugin subdir sits exactly one level under plugins/, so the
# same relative RPATH applies to all of them.
while IFS= read -r p; do
  patchelf --set-rpath '$ORIGIN/../../lib' "$p" 2>/dev/null || true
done < <(find _pkg/plugins -type f -name '*.so')

tar -czf "$output" -C _pkg .
