#!/bin/bash
# The entry point for every bluespin image. The Containerfile runs this on
# whatever base `just build` passed in as BASE_IMAGE, and two things decide what
# happens here:
#
#   IMAGE_NAME  the platform: bluespin, bluespin-dx or bluespin-surface.
#               Chooses the content layered on top.
#
#   the base    detected, not declared. Every platform is built per Fedora
#               branch, and the branch picks the base (bluespin.env): Bluefin
#               for 44, plain Fedora Silverblue for 45 and rawhide. A Universal
#               Blue base already ships uupd, ujust, Homebrew, the flatpak
#               preinstall service and its own vendored GNOME extensions;
#               Silverblue ships none of them, so they are supplied here
#               instead. Everything that follows the bootstrap is the same on
#               either.
#
# The sections are numbered because their order carries dependencies: the
# signing policy needs jq, the extension override needs every enabled
# extension installed, the variant layers build on all of it, and cleanup
# must be last.
set -xeuo pipefail

# shellcheck source=build_files/signing.sh
source /ctx/build_files/signing.sh
# shellcheck source=build_files/extensions.sh
source /ctx/build_files/extensions.sh
# shellcheck source=build_files/silverblue_base.sh
source /ctx/build_files/silverblue_base.sh

# Universal Blue images carry their identity here (image-name, base, flavor);
# Fedora's own images have nothing of the kind. This is the property the
# base-specific blocks below actually depend on, so it is what gets tested.
base_is_ublue() {
    [[ -f /usr/share/ublue-os/image-info.json ]]
}

# dnf5 fails a remove for a package that is not installed, and the bases differ
# in what they ship. These are "must not be in the image" removals, so a package
# that was never there is the desired state, not an error -- unlike installs,
# which deliberately run without --skip-unavailable so a missing package fails
# the build.
remove_if_installed() {
    local pkg present=()
    for pkg in "$@"; do
        if rpm -q "${pkg}" >/dev/null 2>&1; then
            present+=("${pkg}")
        fi
    done
    if [[ ${#present[@]} -gt 0 ]]; then
        dnf -y remove "${present[@]}"
    fi
}

############################################################################
# 1. The base: take what it provides, supply what it does not.
############################################################################

# Flatpaks are installed at boot from /usr/share/flatpak/preinstall.d. Note:
# preinstall tracks these entries, so removing one later uninstalls the app
# from users' systems.
PREINSTALL_FILES=(
    /ctx/files/usr/share/flatpak/preinstall.d/bluespin.preinstall
    /ctx/files/usr/share/flatpak/preinstall.d/bluespin-extra.preinstall
)

if base_is_ublue; then
    # The base enables flatpak-preinstall.service and ships the Flathub remote;
    # only the entries are ours
    install -Dm0644 -t /usr/share/flatpak/preinstall.d/ "${PREINSTALL_FILES[@]}"
    install -Dm0644 -t /usr/share/ublue-os/homebrew/ /ctx/files/usr/share/ublue-os/homebrew/*.Brewfile

    # Remove the base's brew-preinstall mechanism (a user service that installs
    # Homebrew packages from the network at first login). Its system-cli tools
    # (fzf, htop, rclone, tmux, starship, ...) are already in the image as RPMs or
    # binaries shipped by the base, so brew was only shadowing them in PATH;
    # bluefinctl (manages bluefin channels/rebases that don't apply to this image)
    # and the chairlift cask are dropped entirely.
    rm -f /usr/share/ublue-os/homebrew/preinstall.d/*.Brewfile \
        /usr/lib/systemd/user/brew-preinstall.service \
        /usr/lib/systemd/user-preset/01-brew-preinstall.preset

    # The base's dx flatpak Brewfile is superseded by our preinstall.d set; our
    # own system-flatpaks.Brewfile ships as a stub that masks the base's copy so
    # `ujust install-system-flatpaks` stays a working no-op
    rm -f /usr/share/ublue-os/homebrew/system-dx-flatpaks.Brewfile
else
    # Plain Fedora Silverblue. Universal Blue publishes nothing above F44 --
    # base-main, silverblue-main, akmods and bluefin all stop there -- which is
    # why the 45 and rawhide legs land here, and why they deliberately do
    # WITHOUT:
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
    #     extensions (our forks stand in, see section 5), branding and the
    #     Homebrew stack
    #
    # What they do get is everything below: our packages, our extensions, and
    # the shell-version assertion that turns "silently disabled on the new
    # GNOME" into a build failure -- which is what the rawhide leg exists to
    # find out.

    # uupd and ujust, from ublue's COPR, which builds for releases their images
    # do not cover -- what makes a plain-Fedora bluespin possible at all
    install_ublue_tools

    # Neither the Flathub remote nor the preinstall unit exists here, so supply
    # both along with the entries. Bazaar and Gradia come from these -- without
    # them the bazaar/gradia integration extensions would have nothing to
    # integrate with.
    install_flathub_and_preinstall "${PREINSTALL_FILES[@]}"
fi

############################################################################
# 2. Launchers
############################################################################

# A "Trash" launcher in the app grid that opens trash:/// in Files; GNOME
# itself only reaches the trash through the Files sidebar. Its Name and
# Comment are the strings of GTK's own sidebar Trash entry, so the launcher
# is localised from the gtk40 catalogs the image already ships.
install -Dm0644 -t /usr/share/applications/ /ctx/files/usr/share/applications/trash.desktop
/ctx/build_files/desktop-translations.py /usr/share/applications/trash.desktop gtk40 \
    Name=Trash Comment="Open the trash"

############################################################################
# 3. Packages
############################################################################

# gnome-system-monitor: replaced by the Mission Center flatpak (Bluefin only
# hides its desktop file; nothing else depends on the RPM). Bluefin ships
# gnome-tweaks, Silverblue does not; neither image gets it.
remove_if_installed \
    gnome-tweaks \
    gnome-system-monitor

# Install additional fedora packages
ADDITIONAL_FEDORA_PACKAGES=(
    #thunderbird # for mDNS printer discovery
    firefox # for GSConnect and mDNS printer discovery
    mozilla-openh264

    # Bluefin ships both; Silverblue ships jq only. jq is needed by the signing
    # policy below, just by ujust.
    jq
    just

    # Mission Center (preinstalled flatpak, replacing gnome-system-monitor
    # above) gets its per-app network usage from nethogs on the host. The
    # capabilities it needs are granted below, to wheel only.
    nethogs

    # Custom GNOME Shell Extensions
    # NOTE: appindicator, blur-my-shell, caffeine, dash-to-dock and gsconnect
    # are NOT listed here on purpose. Bluefin vendors them as git submodules
    # pinned to branches that track the shell version it ships, and installing
    # Fedora's RPMs would overwrite those copies at the same paths. The
    # versions happen to match today, but Fedora's blur-my-shell build already
    # declares one shell version less than Bluefin's, so the RPM would break it
    # first on a GNOME major bump. (gsconnect also arrives as an RPM in the
    # base, pulled in by nautilus-gsconnect.) On a plain Fedora base nothing
    # vendors them, so section 5 installs our forks of the ones we enable.
    gnome-shell-extension-just-perfection # installed, not enabled by default
    #gnome-shell-extension-network-displays
    gnome-shell-extension-screen-autorotate
    # weather-or-not and nekotorch are vendored as submodules below: Fedora
    # dropped the weather-or-not package after F43, and nekotorch is only
    # packaged in a COPR that still targets shell 48

    # Default GNOME Shell Extensions
    # https://src.fedoraproject.org/rpms/gnome-shell-extensions
    gnome-shell-extension-apps-menu
    gnome-shell-extension-auto-move-windows
    gnome-shell-extension-drive-menu
    gnome-shell-extension-launch-new-instance
    gnome-shell-extension-light-style
    gnome-shell-extension-native-window-placement
    gnome-shell-extension-places-menu
    gnome-shell-extension-screenshot-window-sizer
    gnome-shell-extension-status-icons
    # system-monitor is vendored from our gnome-shell-extensions fork instead
    # (see extensions.sh): the stock one only knows how to open GNOME System
    # Monitor, which this image removes in favour of Mission Center
    gnome-shell-extension-user-theme
    gnome-shell-extension-window-list
    gnome-shell-extension-windowsNavigator
    gnome-shell-extension-workspace-indicator
)

dnf -y install \
    "${ADDITIONAL_FEDORA_PACKAGES[@]}"

# Mission Center runs nethogs as the logged-in user (spawned on the host from
# the flatpak), so it has to work without root:
# https://gitlab.com/mission-center-devs/mission-center/-/wikis/Home/Nethogs
# That takes file capabilities -- cap_net_admin/cap_net_raw for packet
# capture, cap_dac_read_search/cap_sys_ptrace to map sockets to processes of
# other users (root services) -- which, set on a world-executable binary, hand
# every local account packet capture and unrestricted file reads. So the
# binary is made executable by wheel only: its members already hold root
# through sudo, so the capabilities grant them nothing new beyond skipping the
# password prompt, while for everyone else nethogs is plain "permission
# denied" and Mission Center simply shows no per-app network column. The
# capabilities are stored as xattrs and ownership in the image, which ostree
# preserves (the base already ships arping etc. with file caps this way).
#
# Ownership first: the kernel clears file capabilities when a file changes
# owner or group (they are privilege bits, like setuid), so a setcap before
# the chgrp is silently undone.
chgrp wheel /usr/bin/nethogs
chmod 0750 /usr/bin/nethogs
setcap 'cap_net_admin,cap_net_raw,cap_dac_read_search,cap_sys_ptrace+pe' /usr/bin/nethogs
# Fail here rather than ship a nethogs that cannot capture, should anything
# else (a storage driver that cannot hold security.capability xattrs, say)
# drop them without setcap noticing
getcap /usr/bin/nethogs | grep -q 'cap_net_raw'

# Our own COPR extension. Enable/install/disable so no COPR is left active in
# the shipped image.
dnf -y copr enable lorbus/network-displays
dnf -y install gnome-network-displays gnome-network-displays-extension
dnf -y copr disable lorbus/network-displays

############################################################################
# 4. Signing. Every image we publish is cosign-signed, so every image must
#    also know how to verify its own updates.
############################################################################
install_signing_policy

############################################################################
# 5. GNOME Shell extensions
############################################################################

# Extensions Fedora does not package, vendored as submodules the same way the
# Bluefin base handles the ones it bundles.
install_vendored_extensions

# Bluefin vendors appindicator, caffeine, search-light and the bazaar/gradia
# integrations for us. On a plain Fedora base nothing does, so bring our forks
# of the ones we enable.
if ! base_is_ublue; then
    install_bluefin_replacement_extensions
fi

# Installed on every image, enabled by default on none: a shell it does not
# declare is a note in the compatibility report rather than a build failure,
# which is also what lets it ship unchanged on a newer shell.
install_mosaicwm

# Extensions enabled by default. The override sorts after the base's zz0
# (which sets this key) and zz1 (per-extension settings), so it wins.
#
# NOTE: enabled-extensions is replaced wholesale, not merged, so Bluefin's
# defaults have to be restated here -- extensions Bluefin enables upstream will
# NOT reach this image until added below. Diff against zz0-bluefin-
# modifications.gschema.override in projectbluefin/common when rebasing onto a
# new Bluefin.
#
# Dropped from Bluefin's defaults on purpose: blur-my-shell, dash-to-dock,
# gsconnect and logomenu.
# Installed but deliberately left off: nekotorch (only useful on hardware with
# a torch LED), mosaicwm, just-perfection, system-monitor, and the Fedora
# default (GNOME Classic) set.
ENABLED_EXTENSIONS=(
    appindicatorsupport@rgcjonas.gmail.com
    bazaar-integration@kolunmi.github.io
    caffeine@patapon.info
    network-displays@gnome.org
    gradia-integration@alexandervanhee.github.io
    search-light@icedman.github.com
    weatherornot@somepaulo.github.io
)

# Screen auto-rotation is only useful on the convertible Surface hardware; the
# extension ships on every variant so it can still be enabled by hand.
if [[ "${IMAGE_NAME}" == "bluespin-surface" ]]; then
    ENABLED_EXTENSIONS+=(screen-rotate@shyzus.github.io)
fi

# Hard-assert shell coverage for the vendored subset of what we enable, then
# render the override. Installed-but-disabled extensions (mosaicwm, nekotorch
# here) are covered by the GNOME compatibility report in CI instead.
assert_enabled_vendored_extensions "${ENABLED_EXTENSIONS[@]}"
write_enabled_extensions_override "${ENABLED_EXTENSIONS[@]}"

############################################################################
# 6. Variant layers
############################################################################

# DX Variant
if [[ "${IMAGE_NAME}" == "bluespin-dx" ]]; then
    install -Dm0644 -t /usr/share/flatpak/preinstall.d/ \
        /ctx/files/usr/share/flatpak/preinstall.d/bluespin-dx.preinstall

    # The base is bluefin, not bluefin-dx, so the developer layer is ours
    /ctx/build_files/dx.sh
fi

# Surface Variant
if [[ "${IMAGE_NAME}" == "bluespin-surface" ]]; then
    # Install Surface Packages
    dnf config-manager addrepo --from-repofile=https://pkg.surfacelinux.com/fedora/linux-surface.repo
    dnf config-manager setopt linux-surface.enabled=0

    # Workaround: linux-surface has no F44 repo yet, and its repofile hardcodes
    # baseurl=.../fedora/f$releasever/, which 404s on F44. Pin to F43 until F44 is published.
    # Fail loudly rather than silently skipping the repo (upstream sets skip_if_unavailable=1).
    # https://github.com/linux-surface/linux-surface/issues/2102
    dnf config-manager setopt linux-surface.baseurl=https://pkg.surfacelinux.com/fedora/f43/
    dnf config-manager setopt linux-surface.skip_if_unavailable=0

    # NOTE: libwacom-surface{,-data} is deliberately NOT swapped in. It is not merely
    # inconvenient on F44, it is uninstallable:
    #   - libwacom-surface (2.17) provides symbol versions up to LIBWACOM_2.15, but F44's
    #     libinput requires LIBWACOM_2.18 -> dnf "resolves" this by erasing libinput+GNOME.
    #   - libwacom-surface-data provides an *unversioned* libwacom-data, which cannot
    #     satisfy F44 libwacom's strict `Requires: libwacom-data = 2.19.0-1.fc44`.
    # Backporting just the .tablet files doesn't work either: modern Surface entries use
    # `virt|` and `mei|` DeviceMatch bus types that only the forked library understands;
    # stock libwacom rejects them as invalid.
    # Cost of omitting: GNOME loses pen-display metadata for Surface Pro 4+/Book/Laptop
    # Studio (stock libwacom only knows Surface Go/Go 2). Pen and touch input themselves
    # still work via iptsd + libinput's generic tablet handling.
    # Restore the swap once linux-surface publishes F44 builds against libwacom 2.19.

    # Remove Existing Kernel
    # Tolerate packages the base image no longer ships (e.g. kmod-framework-laptop);
    # under `set -e` an unconditional erase of a missing package aborts the build.
    for pkg in kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra \
            kmod-framework-laptop kmod-v4l2loopback v4l2loopback; do
        if rpm -q "$pkg" >/dev/null 2>&1; then
            rpm --erase "$pkg" --nodeps
        fi
    done

    # Configure surface kernel modules to load at boot
    tee /usr/lib/modules-load.d/ublue-surface.conf << EOF
# Only on AMD models
pinctrl_amd

# Surface Book 2
pinctrl_sunrisepoint

# For Surface Pro 7/Laptop 3/Book 3
pinctrl_icelake

# For Surface Pro 7+/Pro 8/Laptop 4/Laptop Studio
pinctrl_tigerlake

# For Surface Pro 9/Laptop 5
pinctrl_alderlake

# For Surface Pro 10/Laptop 6
pinctrl_meteorlake

# Only on Intel models
intel_lpss
intel_lpss_pci

# Add modules necessary for Disk Encryption via keyboard
surface_aggregator
surface_aggregator_registry
surface_aggregator_hub
surface_hid_core
8250_dw

# Surface Pro 7/Laptop 3/Book 3 and later
surface_hid
surface_kbd

EOF

    # Install Kernel + touch daemon.
    # Enable the repo alongside Fedora's rather than passing --repo=linux-surface:
    # --repo restricts resolution to that repo alone, so iptsd's dependencies
    # (cairomm, which Fedora ships) become unresolvable.
    dnf config-manager setopt linux-surface.enabled=1
    dnf -y install --setopt=disable_excludes=* \
        kernel-surface iptsd
    dnf config-manager setopt linux-surface.enabled=0

    dnf versionlock add kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra

    # Regenerate initramfs
    KERNEL_SUFFIX=""
    QUALIFIED_KERNEL="$(rpm -qa | grep -P 'kernel-surface-(|'"$KERNEL_SUFFIX"'-)(\d+\.\d+\.\d+)' | sed -E 's/kernel-surface-(|'"$KERNEL_SUFFIX"'-)//')"
    export DRACUT_NO_XATTR=1
    /usr/bin/dracut --no-hostonly --kver "$QUALIFIED_KERNEL" --reproducible -v --add ostree -f "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"
    chmod 0600 "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"

fi

############################################################################
# 7. Report what this image was built against, so the build log answers the
#    question the rawhide leg exists to ask -- and every other leg's log
#    answers it for free.
############################################################################
echo "=== built against gnome-shell $(rpm -q --qf '%{version}-%{release}' gnome-shell) on $(rpm -E %fedora) ==="
for ext in "${EXT_DIR}"/*/; do
    [[ -f "${ext}/metadata.json" ]] || continue
    jq -r --arg u "$(basename "${ext}")" \
        '"  \($u): shell-version \(.["shell-version"] | join(","))"' "${ext}/metadata.json"
done

############################################################################
# 8. Cleanup. Last, always.
############################################################################
if base_is_ublue; then
    dnf clean all

    find /var/* -maxdepth 0 -type d \! -name cache -exec rm -fr {} \;
    find /var/cache/* -maxdepth 0 -type d \! -name libdnf5 \! -name rpm-ostree -exec rm -fr {} \;
else
    # A plain base also needs /boot emptied and /var/tmp recreated for
    # `bootc container lint` to pass; see silverblue_base.sh
    cleanup_silverblue_image
fi
