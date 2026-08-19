# Flashable disk images. Only bluespin-fp5 builds these -- every other variant
# is installed with `bootc switch` or a live ISO.
#
# Ported from pocketblue's tools/disk_images.just.

# Build a raw disk image from the published bootc container
[group('Disk')]
disk $image_ref=disk_image_ref:
    mkdir -p ./output
    # The partition layout is NOT passed here: image-builder reads
    # /usr/lib/image-builder/bootc/disk.yaml from inside the referenced image.
    # The bind mount of container storage is root's, so the image has to have
    # been pulled with sudo.
    podman run \
        --rm --privileged \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        -v ./output:/output \
        -v ./disk/blueprint.toml:/blueprint.toml \
        "${image_builder_image}" \
            build \
                --bootc-ref="${image_ref}" \
                --blueprint=/blueprint.toml \
                --output-dir=/output \
                --output-name=disk.raw \
                --progress=verbose \
                raw

# Install the DTBs and split the image for fastboot. Needs root for losetup.
[group('Disk')]
postprocess $device=disk_device:
    #!/usr/bin/env bash
    set -euo pipefail

    source devices/${device}/build-aux/device.conf
    export CONF_INSTALL_DTB=${install_dtb:-false}
    export CONF_SPLIT_PARTITIONS=${split_partitions:-false}

    export OUTPUT=./output
    export SCRIPTS=tools/postprocess

    tools/postprocess/postprocess.sh

# Check the split images meet the flash contracts (exact ESP size, this
# device's DTB present on it) declared in the device's device.conf. Needs root
# for the loop mount. Run it before artifacts, while output/images still holds
# the split files.
[group('Disk')]
verify-images $device=disk_device:
    #!/usr/bin/env bash
    set -euo pipefail
    source devices/${device}/build-aux/device.conf
    : "${esp_size_bytes:?devices/${device}/build-aux/device.conf must set esp_size_bytes}"
    : "${dtb_name:?devices/${device}/build-aux/device.conf must set dtb_name}"
    export esp_size_bytes dtb_name
    export OUTPUT=./output
    tools/postprocess/verify-images.sh

# Download the prebuilt extras, add the flash scripts, and archive it all
[group('Disk')]
artifacts $device=disk_device $archive_name=image_name:
    #!/usr/bin/env bash
    set -euo pipefail

    export DEVICE_PATH=devices/${device}
    export ARGS_7Z="${disk_compression_7z}"
    export SCRIPTS=tools/postprocess
    export ARCHIVE_NAME="${archive_name}"

    tools/collect-artifacts.sh
