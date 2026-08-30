#!/usr/bin/env bash
# esp_part and root_part are exported by postprocess.sh, which owns the loop
# device; these scripts are not meant to be run on their own.
# shellcheck disable=SC2154
# Copy this device's device tree blob onto the ESP, where u-boot looks for it.
# Ported from pocketblue's tools/postprocess/install-dtb.sh.

set -uexo pipefail


mkdir boot
mount -o subvol=boot "$root_part" boot
mount "$esp_part" boot/efi

# One blob, at the path the kernel filed it under -- u-boot reads exactly one.
# Copying the whole tree was harmless while the fp5 kernel carried qcom alone;
# a stock aarch64 kernel carries every board Fedora builds for, which put 1723
# files and 113 MB of Xilinx and friends on a 512 MiB ESP.
dtb=$(find boot/ostree/default-*/dtb -name "$CONF_DTB_NAME" -print -quit)
if [ -z "$dtb" ]; then
    echo "${CONF_DTB_NAME} is not in this image's dtb tree" >&2
    exit 1
fi
# Strip through the first /dtb/ to get the path relative to the tree root.
rel=${dtb#*/dtb/}
mkdir -p "boot/efi/dtb/$(dirname "$rel")"
cp "$dtb" "boot/efi/dtb/${rel}"

umount -R boot/
rmdir boot
