#!/bin/bash
# Apply the kernel-side patches and rebuild the iris module.
# Usage: 50-patch-and-build-iris.sh /path/to/linux-source
set -eu
SRC=${1:?usage: $0 <kernel source dir>}
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$SRC"
echo "== applying the clean patch (applies with fuzz=0) =="
patch -p1 --batch --fuzz=0 < "$HERE/../patches/clean/"*.patch
echo "== building the module =="
# match how the running kernel was built - check CONFIG_CC_IS_GCC in .config
if grep -q '^CONFIG_CC_IS_GCC=y' .config; then
  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)" M=drivers/media/platform/qcom/iris modules
else
  make ARCH=arm64 LLVM=1 -j"$(nproc)" M=drivers/media/platform/qcom/iris modules
fi
ls -l drivers/media/platform/qcom/iris/qcom-iris.ko
modinfo drivers/media/platform/qcom/iris/qcom-iris.ko | grep -E '^vermagic'
