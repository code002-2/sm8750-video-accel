#!/bin/bash
# Install the rebuilt module (qcom_iris is in use, so a reboot is required).
set -eu
KO=${1:?usage: $0 <qcom-iris.ko>}
KVER=$(uname -r)
DEST=$(ls /lib/modules/$KVER/kernel/drivers/media/platform/qcom/iris/qcom-iris.ko)
[ -f "$DEST.orig" ] || cp -a "$DEST" "$DEST.orig"
install -m 0644 "$KO" "$DEST"
depmod -a "$KVER"
echo "installed; rollback file: $DEST.orig"
echo "reboot to load it (the module is in use and cannot be replaced live)"
