#!/usr/bin/env bash
# Gather everything that gets shipped into one archive.
# Ported from pocketblue's tools/collect-artifacts.sh.

set -uexo pipefail

which tar

# Start clean so a failed or repeated run does not abort on mkdir or archive
# stale halves from the previous attempt
rm -rf out
mkdir out
if [ -d output/images ]; then
    mv output/images out/
fi
if [ -f output/disk.raw ]; then
    mv output/disk.raw out/
fi

# Prebuilt artifacts from elsewhere (u-boot), sha256-checked
if [ -f "$DEVICE_PATH/build-aux/extra-sources" ]; then
    "$SCRIPTS/download-extra.sh" "$DEVICE_PATH/build-aux/extra-sources"
fi

# Per-device artifact step: installs the flash scripts
OUT_PATH=$(realpath ./out)
DEVICE_PATH=$(realpath "$DEVICE_PATH")
export OUT_PATH DEVICE_PATH
"$DEVICE_PATH/build-aux/artifacts.sh"

cd out
# tar, not 7z: what ships here is a directory of raw partition images and
# the flash scripts that write them, and tar is the one container that
# keeps the scripts executable, streams, and -- with --sparse -- never
# reads the holes in a raw image at all. The compressor stays LZMA2, as
# 7z's was: the archive is 1.8 GiB against a 2 GiB release-asset limit,
# so this is no place to trade ratio for convenience (gzip or bzip2
# would push it over and into being split). DISK_ARCHIVE_COMPRESSOR
# takes anything that reads stdin, e.g. 'zstd -19 -T0 --long=27' for a
# much faster build at a slightly larger archive.
tar --sparse --use-compress-program="${DISK_ARCHIVE_COMPRESSOR}" \
    -cf "../${ARCHIVE_NAME}.${DISK_ARCHIVE_EXT}" .
