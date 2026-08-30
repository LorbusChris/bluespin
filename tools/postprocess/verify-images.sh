#!/usr/bin/env bash
# esp_size_bytes and dtb_name come exported from the `just verify-images`
# recipe, which sources the device's device.conf; this script is not meant to
# be run on its own.
# shellcheck disable=SC2154
# Verify the split images meet the contracts that decide whether the result
# flashes at all. Driven by the device's build-aux/device.conf so the exact
# same checks run in CI and in a local `just verify-images` -- the path a
# human actually uses during hardware bring-up.
#
# Expects: OUTPUT, plus esp_size_bytes and dtb_name from device.conf.

set -uexo pipefail

esp="$OUTPUT/images/fedora_esp.raw"

# The ESP is dd'd onto the device's boot-adjacent partition, so it must be
# exactly that partition's size -- not at most.
size=$(stat -c%s "$esp")
if [ "$size" -ne "$esp_size_bytes" ]; then
    echo "ESP is ${size} bytes, expected ${esp_size_bytes}" >&2
    exit 1
fi

# install-dtb.sh puts this device's blob on the ESP at whatever path the kernel
# package filed it under, so look for it rather than assuming the layout.
mnt=$(mktemp -d)
mount -o ro,loop "$esp" "$mnt"
found=$(find "$mnt/dtb" -name "$dtb_name" -print -quit 2>/dev/null || true)
if [ -z "$found" ]; then
    echo "${dtb_name} is missing from the ESP" >&2
    find "$mnt" -maxdepth 3 >&2 || true
    umount "$mnt"
    rmdir "$mnt"
    exit 1
fi
echo "dtb: ${found#"$mnt"/}"
umount "$mnt"
rmdir "$mnt"
