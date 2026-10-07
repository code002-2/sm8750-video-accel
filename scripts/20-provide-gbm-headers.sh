#!/bin/bash
# Supply the gbm headers and link-time symlink WITHOUT installing libgbm-dev.
set -eu
if pkg-config --exists gbm 2>/dev/null; then echo "gbm already visible: $(pkg-config --modversion gbm)"; exit 0; fi
cd /root
apt-get download libgbm-dev
rm -rf /root/gbm-dev; mkdir -p /root/gbm-dev
dpkg-deb -x libgbm-dev_*.deb /root/gbm-dev
mkdir -p /usr/local/include /usr/local/lib/pkgconfig
cp -a /root/gbm-dev/usr/include/* /usr/local/include/
PC=$(find /root/gbm-dev -name gbm.pc | head -1)
sed -e 's|^prefix=.*|prefix=/usr/local|' \
    -e "s|^libdir=.*|libdir=$(dirname "$(readlink -f /usr/lib/*/libgbm.so.1 | head -1)")|" \
    -e 's|^includedir=.*|includedir=/usr/local/include|' "$PC" > /usr/local/lib/pkgconfig/gbm.pc
# the linker needs libgbm.so, which only the -dev package normally provides
L=$(readlink -f /usr/lib/*/libgbm.so.1 | head -1)
[ -n "$L" ] && ln -sf "$(basename "$L")" "$(dirname "$L")/libgbm.so" && echo "linked $(dirname "$L")/libgbm.so -> $(basename "$L")"
PKG_CONFIG_PATH=/usr/local/lib/pkgconfig pkg-config --modversion gbm
