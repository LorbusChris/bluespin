#!/bin/bash
set -xeuo pipefail

# EXPERIMENTAL. Builds bluespin's own additions on top of plain Fedora
# Silverblue rawhide, to find out what breaks on the next GNOME before it
# ships. This is a test image, not a daily driver.
#
# Universal Blue publishes nothing above F44 -- base-main, silverblue-main,
# akmods and bluefin all stop there -- so there is no bluefin-dx to build on
# for GNOME 51. That means this image deliberately does WITHOUT:
#
#   * the negativo17 multimedia stack (full ffmpeg/mesa/VA-API, versionlocked
#     by ublue-os/main): no f45 tree exists, so expect degraded H.264/H.265/AAC
#     playback and hardware video decode
#   * kmod-v4l2loopback: ublue's akmods have no F45 build, and their kmod RPM
#     names embed the exact kernel EVR they were built against, so nothing
#     exists for rawhide's kernel. (Provenance is not the problem -- ublue
#     rebuilds Fedora's own kernel RPMs under the same NVR, adding only a
#     Secure Boot signature, so their kmods do match a stock Fedora kernel of
#     the same version; they just need their MOK enrolled to load under Secure
#     Boot.) RPMFusion's akmod builds per-kernel but is unsigned.
#   * the DX layer (docker-ce has no f45 build either), Bluefin's nine bundled
#     extensions, branding and the Homebrew stack
#
# What it does keep is the part we actually want to test: our own extensions,
# our packages, and the shell-version assertion that turns "silently disabled
# on the new GNOME" into a build failure.

# Bluefin's base normally supplies these; on plain Silverblue we ask for them
# explicitly. Kept deliberately small -- this image exists to test GNOME, not
# to reconstruct a distribution.
dnf -y install --skip-unavailable \
    just \
    jq \
    gnome-tweaks \
    firefox \
    mozilla-openh264 \
    papers \
    simple-scan \
    gnome-shell-extension-just-perfection \
    gnome-shell-extension-screen-autorotate

# uupd (the update daemon Bluefin uses instead of rpm-ostreed-automatic) and
# ujust both build for F45 in ublue's COPR even though their images do not.
dnf -y copr enable ublue-os/packages
dnf -y install --skip-unavailable uupd ublue-os-just
dnf -y copr disable ublue-os/packages

# Our own COPR extensions, same as the shipping variants
dnf -y copr enable lorbus/network-displays
dnf -y install gnome-network-displays gnome-network-displays-extension
dnf -y copr disable lorbus/network-displays

# shellcheck source=build_files/extensions.sh
source /ctx/build_files/extensions.sh
install_vendored_extensions
# Nothing on this base supplies Bluefin's vendored set, so bring our forks
install_bluefin_replacement_extensions

# The same set the shipping variants enable. Everything Bluefin would have
# vendored is supplied above from our own forks instead; appindicator is the
# one Fedora already packages at a revision declaring the current shell.
ENABLED_EXTENSIONS=(
    appindicatorsupport@rgcjonas.gmail.com
    bazaar-integration@kolunmi.github.io
    caffeine@patapon.info
    gnome-network-displays@gnome.org
    gradia-integration@alexandervanhee.github.io
    search-light@icedman.github.com
    weatherornot@somepaulo.github.io
)
write_enabled_extensions_override "${ENABLED_EXTENSIONS[@]}"

# Report what we are actually testing against, so the build log answers the
# question this image exists to ask
echo "=== built against gnome-shell $(rpm -q --qf '%{version}-%{release}' gnome-shell) on $(rpm -E %fedora) ==="
for ext in "${EXT_DIR}"/*/; do
    [[ -f "${ext}/metadata.json" ]] || continue
    jq -r --arg u "$(basename "${ext}")" \
        '"  \($u): shell-version \(.["shell-version"] | join(","))"' "${ext}/metadata.json"
done

# Cleanup
dnf clean all
find /var/* -maxdepth 0 -type d \! -name cache -exec rm -fr {} \;
find /var/cache/* -maxdepth 0 -type d \! -name libdnf5 \! -name rpm-ostree -exec rm -fr {} \;
