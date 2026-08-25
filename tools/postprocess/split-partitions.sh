#!/usr/bin/env bash
# esp_part and root_part are exported by postprocess.sh, which owns the loop
# device; these scripts are not meant to be run on their own.
# shellcheck disable=SC2154
# Split the raw image into the two files the flash script writes to logdump and
# userdata. Ported from pocketblue's tools/postprocess/split-partitions.sh.

set -uexo pipefail


mkdir -p "$OUTPUT/images"

dd if="$esp_part"  of="$OUTPUT/images/fedora_esp.raw"    bs=1M
dd if="$root_part" of="$OUTPUT/images/fedora_rootfs.raw" bs=1M

sync

# Pad the last block to 4096 bytes; fastboot needs this.
#
# Note this is dead code while disk.yaml declares sector_size 4096, since the
# partition is then always aligned. It is kept correct rather than dropped so it
# still works if that ever changes: pad by the actual remainder, not a fixed
# 512 bytes, which only lands on a boundary when the remainder happens to be
# 3584.
size=$(stat -c%s "$OUTPUT/images/fedora_rootfs.raw")
pad=$(( (4096 - size % 4096) % 4096 ))
if (( pad )); then
    dd if=/dev/zero bs=1 count="$pad" >> "$OUTPUT/images/fedora_rootfs.raw"
fi

chmod 666 "$OUTPUT"/images/*
