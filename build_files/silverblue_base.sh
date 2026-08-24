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

# The multimedia stack Fedora cannot ship: full ffmpeg (H.264/H.265/AAC and
# friends), the freeworld VA-API/VDPAU mesa drivers -- Silverblue ships NO
# VA-API driver at all -- and the HEVC plugin for libheif. From RPMFusion,
# which unlike negativo17 (what the Bluefin base uses) publishes for every
# branch including rawhide, so the same function serves the whole matrix.
# Same enable/install/disable hygiene as the COPRs: the repos ship installed
# but disabled, one `dnf config-manager setopt` away for anyone layering.
install_multimedia_stack() {
    local relver
    relver="$(dnf --dump-variables 2>/dev/null | sed -n 's/^releasever = //p')"
    [[ -n "${relver}" ]]

    dnf -y install \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${relver}.noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${relver}.noarch.rpm"

    # One transaction each: swap cannot take unrelated packages, so the
    # full-ffmpeg swap (which drags the whole libav*-free set with
    # --allowerasing) runs first, the additions after.
    dnf -y swap --allowerasing ffmpeg-free ffmpeg
    dnf -y swap --allowerasing fdk-aac-free fdk-aac

    # No mesa-vdpau-drivers-freeworld: VDPAU is dead upstream and RPMFusion
    # stopped building it above F45. VA-API is the API that matters.
    dnf -y install \
        libheif-freeworld \
        intel-media-driver \
        ffmpegthumbnailer

    # The freeworld VA driver hard-requires the exact mesa version. On a
    # branched release that is stable, so it must succeed; on rawhide
    # RPMFusion routinely builds against a Koji mesa the compose has not
    # shipped yet, and that skew is neither ours nor actionable -- warn and
    # ship without hardware decode until the compose catches up.
    if [[ "${relver}" == "rawhide" ]]; then
        dnf -y install mesa-va-drivers-freeworld || \
            echo "::warning::mesa-va-drivers-freeworld does not resolve against this rawhide compose (RPMFusion built for a newer mesa); no VA-API hardware decode in this build"
    else
        dnf -y install mesa-va-drivers-freeworld
        rpm -q mesa-va-drivers-freeworld >/dev/null
    fi

    # Prove the swap took: a build where dnf quietly kept the -free stack
    # would ship crippled codecs under the same name. (An `!` alone would not
    # trip errexit -- SC2251 -- hence the explicit failure.)
    rpm -q ffmpeg >/dev/null
    if rpm -q ffmpeg-free >/dev/null 2>&1; then
        echo "ffmpeg-free survived the swap to RPMFusion ffmpeg" >&2
        return 1
    fi

    # Disable by file, not by repo id: the ids differ per branch (rpmfusion-free
    # and -free-updates on a branched release, rpmfusion-free-rawhide on
    # rawhide), and a named setopt quietly misses whichever set is absent.
    sed -i 's/^enabled=1/enabled=0/' /etc/yum.repos.d/rpmfusion-*.repo
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
