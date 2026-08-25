#!/bin/bash
# The image's identity in /usr/lib/os-release. Shared by the bluespin layer
# (build.sh) and the variant layers, which re-run it with their own platform
# name -- everything else in the bluespin layer is variant-agnostic.
set -xeuo pipefail

# Set a key in /usr/lib/os-release, appending it if the base did not have
# one. /etc/os-release is a symlink to this file.
os_release_set() {
    local key=$1 value=$2 file=/usr/lib/os-release
    if grep -q "^${key}=" "${file}"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "${file}"
    else
        echo "${key}=${value}" >> "${file}"
    fi
}

# Say what this image actually is. Inherited unedited, os-release claims to
# be whatever the base was, so a bluespin user's bug reports would name
# someone else's project. Only the identity fields change; VERSION_ID,
# SUPPORT_END and the Fedora bugzilla hints stay, because they describe the
# underlying release and are still true.
#
# ID stays "fedora" on purpose: dnf's copr plugin builds its chroot name
# from $ID-$VERSION_ID, so a custom ID asks for a chroot nobody publishes --
# it breaks `dnf copr enable` both in this build and, worse, for anyone
# using copr on the installed system, which matters for an image that ships
# copr-cli and fedora-packager. Fedora's own convention is to keep ID and
# distinguish in VARIANT_ID, which is what Workstation does, so that is
# what bluespin does too.
set_image_identity() {
    local platform=$1 fedora_version
    fedora_version="$(sed -n 's/^VERSION_ID=//p' /usr/lib/os-release)"
    os_release_set NAME '"bluespin"'
    os_release_set ID 'fedora'
    os_release_set VARIANT_ID 'bluespin'
    os_release_set VERSION "\"${FEDORA_BRANCH:-${fedora_version}} (Silverblue)\""
    os_release_set PRETTY_NAME "\"${platform} (Fedora Linux ${fedora_version})\""
    os_release_set CPE_NAME "\"cpe:/o:lorbuschris:bluespin:${fedora_version}\""
    os_release_set DEFAULT_HOSTNAME '"bluespin"'
    os_release_set HOME_URL '"https://github.com/LorbusChris/bluespin"'
    os_release_set DOCUMENTATION_URL '"https://github.com/LorbusChris/bluespin#readme"'
    os_release_set SUPPORT_URL '"https://github.com/LorbusChris/bluespin/issues"'
    os_release_set BUG_REPORT_URL '"https://github.com/LorbusChris/bluespin/issues"'
    os_release_set IMAGE_ID "\"${platform}\""
    os_release_set IMAGE_VERSION "\"${FEDORA_BRANCH:-${fedora_version}}\""
    # These described the BASE's build, not ours, and nothing regenerates them
    sed -i '/^OSTREE_VERSION=/d;/^BUILD_ID=/d' /usr/lib/os-release
}
