#!/usr/bin/env bash
# Gather everything that gets shipped into one archive.
# Ported from pocketblue's tools/collect-artifacts.sh.

set -uexo pipefail

which 7z

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
# shellcheck disable=SC2086  # ARGS_7Z is a deliberate multi-word option string
7z a -mx=9 $ARGS_7Z "../${ARCHIVE_NAME}.7z" .
