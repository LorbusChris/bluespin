#!/usr/bin/env bash
# esp_part and root_part are exported by postprocess.sh, which owns the loop
# device; these scripts are not meant to be run on their own.
# shellcheck disable=SC2154
# Copy the device tree blobs onto the ESP, which is where u-boot looks for them.
# Ported from pocketblue's tools/postprocess/install-dtb.sh.

set -uexo pipefail


mkdir boot
mount -o subvol=boot "$root_part" boot
mount "$esp_part" boot/efi
cp -ar boot/ostree/default-*/dtb boot/efi/dtb
umount -R boot/
rmdir boot
