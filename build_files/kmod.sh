#!/bin/bash
# Install the kernel-module artifacts a kernel-builder stage produced (see
# build_files/kernel-builder.sh), mounted at /kernel-out. Shared by the
# bluespin layer (stock kernel) and the surface layer (surface kernel) --
# each consumes the builder flavor that matches its kernel.
set -xeuo pipefail

install_v4l2loopback_artifacts() {
    local kver
    kver="$(cat /kernel-out/kver)"
    # The module dir exists iff the builder's kernel is this image's kernel:
    # guaranteed on the vanilla platforms (builder and image FROM the same
    # base), asserted explicitly on surface. This catches anything else.
    if [[ ! -d "/usr/lib/modules/${kver}" ]]; then
        echo "kernel-builder built for ${kver}, which this image does not ship" >&2
        exit 1
    fi
    install -Dm0644 /kernel-out/v4l2loopback.ko.xz \
        "/usr/lib/modules/${kver}/extra/v4l2loopback/v4l2loopback.ko.xz"
    depmod -a "${kver}"

    # Load at boot, with the label OBS users expect -- the same
    # configuration the Bluefin base shipped
    install -Dm0644 /ctx/files/usr/lib/modules-load.d/v4l2loopback.conf \
        /usr/lib/modules-load.d/v4l2loopback.conf
    install -Dm0644 /ctx/files/usr/lib/modprobe.d/98-v4l2loopback.conf \
        /usr/lib/modprobe.d/98-v4l2loopback.conf
}
