#!/usr/bin/env bash
# Turn the raw disk image into something fastboot can flash.
# Ported from pocketblue's tools/postprocess/postprocess.sh.

set -uexo pipefail

# --sector-size 4096 is load-bearing: disk.yaml declares sector_size 4096, and
# without the matching flag the partition table is misparsed and ${loop}p1/p2
# never appear.
loop=$(losetup --find --show --partscan --sector-size 4096 "$OUTPUT/disk.raw")
trap 'losetup -d $loop' EXIT

export esp_part="${loop}p1"
export root_part="${loop}p2"

[ "$CONF_INSTALL_DTB" = "true" ] && "$SCRIPTS/install-dtb.sh"

if [ "$CONF_SPLIT_PARTITIONS" = "true" ]; then
    "$SCRIPTS/split-partitions.sh"
    trap - EXIT
    losetup -d "$loop"
    # The split images are what we ship; dropping this reclaims its whole size
    # on the runner before the archive step.
    rm "$OUTPUT/disk.raw"
else
    chmod 666 "$OUTPUT/disk.raw"
fi
