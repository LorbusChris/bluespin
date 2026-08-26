#!/bin/bash
# The bluespin layer -- the image of that name itself, and the base every
# variant builds on: the Containerfile's dx and surface stages layer their
# deltas on top of this (locally on the stage, in CI on the pushed bluespin
# image, so the variants share these exact layers and updates dedupe).
# IMAGE_NAME is bluespin here; variant identity, desktop and extension
# deltas are variant-finish.sh's job in those stages.
#
# The branch (bluespin.env) decides which Fedora Silverblue this builds on;
# every branch uses the same base image family, so the build is one
# sequence rather than a per-base fork.
#
# The sections are numbered because their order carries dependencies: the
# signing policy needs jq, the extension override needs every enabled
# extension installed, and cleanup must be last.
set -xeuo pipefail

# shellcheck source=build_files/signing.sh
source /ctx/build_files/signing.sh
# shellcheck source=build_files/extensions.sh
source /ctx/build_files/extensions.sh
# shellcheck source=build_files/silverblue_base.sh
source /ctx/build_files/silverblue_base.sh
# shellcheck source=build_files/starship.sh
source /ctx/build_files/starship.sh
# shellcheck source=build_files/desktop.sh
source /ctx/build_files/desktop.sh
# shellcheck source=build_files/identity.sh
source /ctx/build_files/identity.sh
# shellcheck source=build_files/kmod.sh
source /ctx/build_files/kmod.sh

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
# from users' systems. One system set for every platform; everything else is
# an opt-in per-user catalog (see the install-flatpaks recipe).
PREINSTALL_FILES=(
    /ctx/files/usr/share/flatpak/preinstall.d/desktop.preinstall
)

# The update daemon, from ublue's COPR, and the ujust library, vendored and
# curated under files/ -- see silverblue_base.sh for both.
install_uupd
install_ujust

# Silverblue has neither the Flathub remote nor a preinstall unit, so supply
# both along with the entries. Bazaar and Gradia come from these -- without
# them the bazaar/gradia integration extensions have nothing to integrate with.
install_flathub_and_preinstall "${PREINSTALL_FILES[@]}"

# The opt-in flatpak catalogs (`ujust install-flatpaks`): per-user sets
# beyond the preinstalled system apps -- extra (general desktop) and dx
# (developer GUIs). Both ship on every platform: opting in is a choice,
# not a platform property. Validated by the same CI workflow as the
# preinstalls.
install -Dm0644 -t /usr/share/bluespin/flatpaks \
    /ctx/files/usr/share/bluespin/flatpaks/*.list

# Full codecs and hardware video decode, from RPMFusion.
install_multimedia_stack

############################################################################
# 2. Identity and launchers
############################################################################

# Say what this image actually is -- the identity fields, ID=fedora and the
# VARIANT_ID convention are explained in identity.sh. Variant layers re-run
# this with their own platform name.
set_image_identity "${IMAGE_NAME}"


# Bazaar reads the system flatpak configuration -- remotes in
# /etc/flatpak/remotes.d, where our Flathub lives -- but a flatpak sandbox
# gets a synthesized /etc, so without this read-only widening the app store
# may not see the very remote its catalog comes from.
install -Dm0644 /ctx/files/usr/share/flatpak/overrides/io.github.kolunmi.Bazaar \
    /usr/share/flatpak/overrides/io.github.kolunmi.Bazaar

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
#
# gnome-software: uupd owns updates on every bluespin image. With the
# rpm-ostree plugin installed, GNOME Software drives the same deployment --
# two updaters racing for one rpm-ostree transaction, and an update UI that
# contradicts the one users are told to use. The Bluefin base already removes
# both, so this only bites the Silverblue legs; removing it here keeps every
# leg the same and survives the base changing its mind. Bazaar (preinstalled
# flatpak) is the app store.
#
# The fedora-third-party stack ships a FILTERED Flathub whose definition can
# shadow the full remote we configure -- with it gone, ours is the one
# Flathub. fedora-workstation-repositories (disabled Chrome/PyCharm repo
# stubs), fedora-bookmarks and fedora-chromium-config are Fedora product
# defaults this image does not want; the background-logo extension is the
# Fedora watermark. totem-video-thumbnailer is the legacy of the two video
# thumbnailers Silverblue ships -- gst-thumbnailers is the one that stays,
# and the one source of video and audio thumbnails. yelp stays: apps link
# into it for Help.
remove_if_installed \
    gnome-tweaks \
    gnome-system-monitor \
    gnome-software \
    gnome-software-rpm-ostree \
    fedora-third-party \
    fedora-flathub-remote \
    fedora-workstation-repositories \
    fedora-bookmarks \
    fedora-chromium-config \
    fedora-chromium-config-gnome \
    totem-video-thumbnailer \
    gnome-shell-extension-background-logo

# Install additional fedora packages
ADDITIONAL_FEDORA_PACKAGES=(
    #thunderbird # for mDNS printer discovery
    firefox # for GSConnect and mDNS printer discovery
    mozilla-openh264

    # Bluefin ships both; Silverblue ships jq only. jq is needed by the signing
    # policy below, just by ujust.
    jq
    just
    # The ujust recipe library prompts through its ugum wrapper, which wants
    # gum and degrades to plainer prompts without it
    gum

    # The monospace font the desktop defaults select (see desktop.sh). Fedora's
    # adwaita-mono-fonts stays installed alongside it; only the default changes.
    jetbrains-mono-fonts


    # Everyday tools every platform carries (the developer set lives in dx.sh)
    htop
    rclone
    restic
    tmux
    # terminfo for the terminals people SSH in from (kitty, foot, wezterm,
    # ghostty, ...); without it their TERM is unknown here and the session
    # misbehaves
    ncurses-term

    # Network filesystems and domain membership, on every platform: SMB serve
    # and AD-join (samba/adcli/krb5), NFS automount with AD homedirs
    # (autofs/oddjob), NFS in Files (gvfs-nfs), WebDAV as a filesystem
    # (davfs2), and encrypted FUSE filesystems (cryfs/encfs, with the FUSE2
    # runtime older tools expect)
    samba
    samba-winbind
    adcli
    krb5-workstation
    krb5-pkinit
    autofs
    oddjob
    oddjob-mkhomedir
    gvfs-nfs
    davfs2
    cryfs
    fuse-encfs
    fuse

    # Containerized userlands: toolbox is stock, distrobox is not -- until
    # now it arrived only through uupd's weak Recommends, which is one
    # --setopt=install_weak_deps=False away from vanishing. The distrobox
    # recipes, their libdistrobox helpers and the preinstalled DistroShelf
    # GUI all need it, so it is explicit.
    distrobox

    # Desktop glue: GTK3 apps themed like libadwaita (the flatpak twin is
    # preinstalled; this covers host apps), Python Nautilus extensions
    # (Nextcloud badges, gsconnect's menu), GSConnect itself -- installed,
    # not enabled, same as the extension table treats it -- the portal that
    # lets flatpaks run host commands, and the firewalld GUI
    adw-gtk3-theme
    nautilus-python
    gnome-shell-extension-gsconnect
    nautilus-gsconnect
    flatpak-spawn
    firewall-config

    # Security keys: FIDO2 for login and sudo (pam-u2f + its enrolment tool)
    # and the ykman CLI. The legacy Yubico OTP PAM stack is deliberately not
    # here.
    pam-u2f
    pamu2fcfg
    yubikey-manager

    # iPhone CLIs on top of the stock mount stack (gvfs-afc/usbmuxd already
    # make Files work): ideviceinfo, idevicesyslog, local encrypted backups
    # via idevicebackup2. ifuse and libtatsu deliberately not included.
    libimobiledevice-utils

    # The one printer-driver family Silverblue lacks: ZjStream winprinters
    # (HP LaserJet 1000-1022 era, some Oki/Minolta). Everything else --
    # gutenprint, hplip, splix, c2esp, ptouch, brlaser, sane -- is stock.
    foo2zjs

    # Hardware health and power, on every platform: power-draw analysis,
    # temperature/fan sensors, GPU top, disk S.M.A.R.T. (with its SELinux
    # policy so smartd may run), firmware for older sound cards, and display
    # calibration
    powertop
    lm_sensors
    nvtop
    smartmontools
    smartmontools-selinux
    alsa-firmware
    argyllcms

    # A better ls and a better grep, on every platform rather than only on dx.
    # No aliases ship with them: `ls`, `grep` and friends keep meaning what
    # they mean on every other Fedora system, and `ll` stays Fedora's. Call
    # them by name -- eza, ug -- when you want them.
    eza
    ugrep

    # Hardware enablement. Each of these is a udev rule set or the userspace
    # tool that needs one; without them the devices are visible to the kernel
    # but not reachable by an unprivileged session, which is where desktop
    # apps and flatpaks live.
    ddcutil             # brightness and input switching on external monitors
    openrgb-udev-rules  # RGB peripherals, without root
    input-remapper      # remap keys, buttons and gamepad inputs
    solaar-udev         # Logitech Unifying receivers
    libratbag-ratbagd   # gaming-mouse daemon; the Piper flatpak (extra
                        # catalog) is its GUI and is dead without it
    ykpers              # YubiKey personalisation
    bcache-tools        # bcache userspace
    alsa-tools-firmware # firmware loaders for some audio interfaces

    # Mission Center (preinstalled flatpak, replacing gnome-system-monitor
    # above) gets its per-app network usage from nethogs on the host. The
    # capabilities it needs are granted below, to wheel only.
    nethogs

    # Custom GNOME Shell Extensions
    # NOTE: no RPM for anything in VENDORED_EXTENSIONS (extensions.sh):
    # appindicator, caffeine and the rest are installed from our own vendored
    # sources in section 5, on every base, and an RPM at the same path would
    # fight that copy. Fedora's blur-my-shell, dash-to-dock and gsconnect are
    # not installed either -- we do not enable them (gsconnect still arrives
    # in the Bluefin base via nautilus-gsconnect).
    gnome-shell-extension-just-perfection # installed, not enabled by default
    #gnome-shell-extension-network-displays
    gnome-shell-extension-screen-autorotate # Screen Rotate; enabled on surface

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

# powerstat reads x86 RAPL/MSR counters and Fedora builds it for x86_64
# only; the aarch64 image goes without, and `ujust check-idle-power-draw`
# (which is why it is explicit at all -- the recipe must never depend on
# some other package dragging it in) reports the tool as missing there.
if [[ "$(uname -m)" == "x86_64" ]]; then
    ADDITIONAL_FEDORA_PACKAGES+=(powerstat)
fi

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

# Game controllers, VR headsets, Wooting and ZSA keyboards, U2F and Titan
# security keys, Framework 16 input modules, Arduino boards, the Apple
# SuperDrive, racing wheels: about forty udev rules, maintained by Universal
# Blue as one package. The Bluefin base already carries the same rules as
# unowned files its build copies in; installing the package takes ownership
# of them, so every branch ends up with the same rules from the same source.
dnf -y copr enable ublue-os/packages
dnf -y install ublue-os-udev-rules oversteer-udev
dnf -y copr disable ublue-os/packages

# Our own COPR extension. Enable/install/disable so no COPR is left active in
# the shipped image.
dnf -y copr enable lorbus/network-displays
dnf -y install gnome-network-displays gnome-network-displays-extension
dnf -y copr disable lorbus/network-displays

# The starship prompt, for interactive bash shells: a checksum-pinned
# upstream binary (Fedora does not package it) -- see build_files/starship.sh
# for the pin and the Renovate flow.
install_starship

# The containerized CLIs, oras above all: install media is published as
# OCI artifacts, so `oras pull` is how anyone fetches an installer, and
# Fedora packages no oras. Every tool in that file is a shell function
# over a digest-pinned image, pulled only when first used and yielding
# to a real binary on PATH -- so the developer tools alongside oras cost
# an unused definition on the editions that do not want them.
install -Dm0644 /ctx/files/etc/profile.d/97-bluespin-container-clis.sh \
    /etc/profile.d/97-bluespin-container-clis.sh

# Tailscale, from its vendor repo. Shipped disabled (same hygiene as
# RPMFusion and the COPRs) and enabled only for this transaction; the fedora
# path is release-agnostic, so one repo file serves every branch. tailscaled
# runs but stays idle until `tailscale up`; `ujust tailscale-operator` then
# lets your user drive it without sudo.
install -Dm0644 /ctx/files/etc/yum.repos.d/tailscale.repo \
    /etc/yum.repos.d/tailscale.repo
dnf -y install --enablerepo=tailscale-stable tailscale
systemctl enable tailscaled.service

############################################################################
# 4. Signing. Every image we publish is cosign-signed, so every image must
#    also know how to verify its own updates.
############################################################################
install_signing_policy

# The bluespin MOK certificate ships on every platform: enrolling it is what
# lets the v4l2loopback module (section 7) load under Secure Boot anywhere,
# and on surface additionally the kernel itself. The enrolment recipe lives
# in 60-custom.just, installed with the vendored ujust library in section 1.
install -Dm0644 /ctx/files/usr/lib/pki/bluespin-secureboot.der \
    /usr/lib/pki/bluespin-secureboot.der
install -Dm0644 /ctx/files/usr/lib/pki/bluespin-secureboot.pem \
    /usr/lib/pki/bluespin-secureboot.pem

############################################################################
# 5. GNOME Shell extensions
############################################################################

# Every extension we vendor, from our sources, on every base -- replacing the
# Bluefin base's own copies of the ones it bundles, so one pin serves every
# branch (see VENDORED_EXTENSIONS in extensions.sh).
install_vendored_extensions

# What this platform enables is the table in extensions.sh; nothing is
# decided here. The override sorts after the base's zz0 (which sets this key)
# and zz1 (per-extension settings), so it wins.
#
# NOTE: enabled-extensions is replaced wholesale, not merged, so Bluefin's
# defaults do NOT carry over -- an extension Bluefin enables upstream reaches
# this image only through the table. Dropped from Bluefin's defaults on
# purpose: blur-my-shell, dash-to-dock, gsconnect and logomenu. Diff against
# zz0-bluefin-modifications.gschema.override in projectbluefin/common when
# rebasing onto a new Bluefin.
mapfile -t ENABLED_EXTENSIONS < <(enabled_extensions_for_platform "${IMAGE_NAME}")

# "Enabled" has to mean "successfully enabled": every extension in the list
# must be installed and declare the shell this image ships. Ours fail the
# build, Fedora's warn -- see assert_enabled_extensions.
assert_enabled_extensions "${ENABLED_EXTENSIONS[@]}"
write_enabled_extensions_override "${ENABLED_EXTENSIONS[@]}"

# Fonts, keybindings and the rest of the desktop defaults, per platform
write_desktop_defaults "${IMAGE_NAME}"

############################################################################
# 6. Variant layers used to run here. They are separate Containerfile
#    stages now, built FROM this image (locally FROM this stage; in CI FROM
#    the pushed bluespin image, so dx and surface share these exact layers):
#    dx.sh + variant-finish.sh, and surface.sh + variant-finish.sh.
############################################################################

############################################################################
# 7. The v4l2loopback module for the stock kernel, from the stock flavor of
#    the kernel-builder stage -- built and signed there, only installed
#    here (see build_files/kernel-builder.sh and kmod.sh). The surface
#    layer installs its own build for its own kernel; the FP5 platform,
#    when it lands, skips this entirely.
############################################################################

install_v4l2loopback_artifacts

############################################################################
# 8. Report what this image was built against, so the build log answers the
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
# 9. Cleanup. Last, always.
############################################################################
cleanup_silverblue_image
