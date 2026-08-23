#!/bin/bash
# What build.sh supplies on a plain Fedora Silverblue base that a Universal
# Blue base would have shipped already (the 45 and rawhide legs). build.sh
# detects the base and calls these; nothing here is platform-specific.
set -xeuo pipefail

# uupd (the update daemon Bluefin uses instead of rpm-ostreed-automatic) and
# ujust. Enable/install/disable so no COPR is left active in the shipped image:
# a live COPR lets a later `rpm-ostree install` resolve against it.
install_ublue_tools() {
    dnf -y copr enable ublue-os/packages
    dnf -y install uupd ublue-os-just
    dnf -y copr disable ublue-os/packages
}

# Flatpaks. Bluefin gets these via common's flatpak-preinstall.service; on a
# plain base neither the remote nor the unit exists, so supply both.
#
# The remote is declared in /etc rather than with `flatpak remote-add`, whose
# state lands in /var/lib/flatpak and is wiped by the /var cleanup at the end of
# every build script.
#
# Takes the .preinstall files to ship as arguments.
install_flathub_and_preinstall() {
    install -d /etc/flatpak/remotes.d
    curl -fsSL --retry 3 -o /etc/flatpak/remotes.d/flathub.flatpakrepo \
        https://flathub.org/repo/flathub.flatpakrepo
    install -Dm0644 -t /usr/share/flatpak/preinstall.d/ "$@"
    install -Dm0644 /ctx/files/usr/lib/systemd/system/bluespin-flatpak-preinstall.service \
        /usr/lib/systemd/system/bluespin-flatpak-preinstall.service
    systemctl enable bluespin-flatpak-preinstall.service
}

# End-of-build cleanup for a plain Silverblue base: /boot must be empty (the
# ostree deployment materialises it) and /var pruned for `bootc container lint`
# to pass, keeping only the caches the Containerfile mounts. find rather than
# globs so dotfiles go too.
cleanup_silverblue_image() {
    dnf clean all
    rm -rf /var/lib/dnf /var/log/dnf5.log
    find /boot -mindepth 1 -maxdepth 1 -exec rm -fr {} +
    find /var/* -maxdepth 0 -type d \! -name cache -exec rm -fr {} \;
    find /var/cache/* -maxdepth 0 -type d \! -name libdnf5 \! -name rpm-ostree -exec rm -fr {} \;
    mkdir -p /var/tmp /var/roothome
    chmod 1777 /var/tmp
}
