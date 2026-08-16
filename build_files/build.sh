#!/bin/bash
set -xeuo pipefail

# Flatpaks are installed by flatpak-preinstall.service (enabled in the bluefin
# base) from /usr/share/flatpak/preinstall.d. Note: preinstall tracks these
# entries, so removing one later uninstalls the app from users' systems.
install -Dm0644 -t /usr/share/flatpak/preinstall.d/ \
    /ctx/files/usr/share/flatpak/preinstall.d/bluespin.preinstall \
    /ctx/files/usr/share/flatpak/preinstall.d/bluespin-extra.preinstall
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

# Enforce sigstore verification for our own images on updates. The bluefin-dx
# base ships ublue-os-signing, whose policy.json covers ghcr.io/ublue-os but
# falls through to insecureAcceptAnything for everything else, so bootc updates
# from ghcr.io/lorbuschris would otherwise be pulled unverified. Extend that
# policy rather than replace it.
# The key lives in /usr/lib/pki/containers alongside the base's ublue-os keys:
# vendor content belongs outside /etc, which bootc 3-way merges against local
# edits.
install -Dm0644 /ctx/cosign.pub /usr/lib/pki/containers/lorbuschris.pub
install -d /etc/containers/registries.d
tee /etc/containers/registries.d/lorbuschris.yaml << 'EOF'
docker:
  ghcr.io/lorbuschris:
    use-sigstore-attachments: true
EOF
# ublue-os-signing installs policy.json under /usr/etc; containers-common may
# also ship one under /etc. Patch whichever exist, and fail if neither does.
policy_patched=0
for policy in /etc/containers/policy.json /usr/etc/containers/policy.json; do
    [[ -f "$policy" ]] || continue
    policy_tmp="$(mktemp)"
    jq '.transports.docker["ghcr.io/lorbuschris"] = [{
            "type": "sigstoreSigned",
            "keyPath": "/usr/lib/pki/containers/lorbuschris.pub",
            "signedIdentity": {"type": "matchRepository"}
        }]' "$policy" > "$policy_tmp"
    install -m0644 "$policy_tmp" "$policy"
    rm -f "$policy_tmp"
    policy_patched=1
done
[[ "$policy_patched" -eq 1 ]]

# Bluefin fixups
if [[ -f /usr/share/applications/gnome-system-monitor.desktop ]]; then
    sed -i '/^Hidden=true/d' /usr/share/applications/gnome-system-monitor.desktop
fi
if [[ -f /usr/share/applications/org.gnome.SystemMonitor.desktop ]]; then
    sed -i '/^Hidden=true/d' /usr/share/applications/org.gnome.SystemMonitor.desktop
fi

dnf -y remove \
    gnome-tweaks

# Install additional fedora packages
ADDITIONAL_FEDORA_PACKAGES=(
    papers # for mDNS printer discovery
    simple-scan # for mDNS printer discovery
    #thunderbird # for mDNS printer discovery
    firefox # for GSConnect and mDNS printer discovery
    mozilla-openh264

    # Custom GNOME Shell Extensions
    # NOTE: appindicator, blur-my-shell, caffeine, dash-to-dock and gsconnect
    # are NOT listed here on purpose. Bluefin vendors them as git submodules
    # pinned to branches that track the shell version it ships, and installing
    # Fedora's RPMs would overwrite those copies at the same paths. The
    # versions happen to match today, but Fedora's blur-my-shell build already
    # declares one shell version less than Bluefin's, so the RPM would break it
    # first on a GNOME major bump. (gsconnect also arrives as an RPM in the
    # base, pulled in by nautilus-gsconnect.) If this image is ever rebased off
    # a base that does not vendor them (fedora-bootc, centos-bootc, ...), add
    # them back here -- four of the five are in Bluefin's default
    # enabled-extensions list.
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
    gnome-shell-extension-system-monitor
    gnome-shell-extension-user-theme
    gnome-shell-extension-window-list
    gnome-shell-extension-windowsNavigator
    gnome-shell-extension-workspace-indicator
)

dnf -y install --skip-unavailable \
    "${ADDITIONAL_FEDORA_PACKAGES[@]}"

dnf -y copr enable lorbus/network-displays
dnf -y install gnome-network-displays gnome-network-displays-extension
dnf -y copr disable lorbus/network-displays

# GNOME Shell extensions vendored as submodules, the same way the Bluefin base
# handles the extensions Fedora does not package. Both are plain JS, so the
# only build step is compiling their settings schemas.
EXT_DIR=/usr/share/gnome-shell/extensions

# Weather or Not: the extension lives in a subdirectory named after its UUID
cp -r "/ctx/extensions/weather-or-not/weatherornot@somepaulo.github.io" "${EXT_DIR}/"

# NekoTorch: extension sources sit at the repository root
install -d "${EXT_DIR}/nekotorch@nekocwd.gitlab.com"
cp -r /ctx/extensions/nekotorch/{extension.js,prefs.js,utils.js,logger.js,stylesheet.css,metadata.json,icons,schemas} \
    "${EXT_DIR}/nekotorch@nekocwd.gitlab.com/"
# udev rule granting the seat access to the torch LEDs
install -Dm0644 /ctx/extensions/nekotorch/99-flash.rules /usr/lib/udev/rules.d/99-flash.rules

for ext in "weatherornot@somepaulo.github.io" "nekotorch@nekocwd.gitlab.com"; do
    glib-compile-schemas --strict "${EXT_DIR}/${ext}/schemas"
    # Fail loudly if a vendored extension does not cover the shell we ship,
    # since a mismatch silently leaves it disabled at login
    shell_major="$(rpm -q --qf '%{version}' gnome-shell | cut -d. -f1)"
    jq -e --arg v "${shell_major}" '.["shell-version"] | index($v)' \
        "${EXT_DIR}/${ext}/metadata.json" > /dev/null
done

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
# a torch LED), just-perfection, and the Fedora default (GNOME Classic) set.
ENABLED_EXTENSIONS=(
    appindicatorsupport@rgcjonas.gmail.com
    bazaar-integration@kolunmi.github.io
    caffeine@patapon.info
    gnome-network-displays@gnome.org
    gradia-integration@alexandervanhee.github.io
    search-light@icedman.github.com
    weatherornot@somepaulo.github.io
)

# Screen auto-rotation is only useful on the convertible Surface hardware; the
# extension ships on every variant so it can still be enabled by hand.
if [[ "${IMAGE_NAME}" == "bluespin-surface" ]]; then
    ENABLED_EXTENSIONS+=(screen-rotate@shyzus.github.io)
fi

# Every enabled extension must exist, or it is silently ignored at login
for ext in "${ENABLED_EXTENSIONS[@]}"; do
    [[ -d "${EXT_DIR}/${ext}" ]]
done

{
    echo "# Generated by build_files/build.sh -- edit ENABLED_EXTENSIONS there."
    echo "[org.gnome.shell]"
    printf "enabled-extensions = ["
    printf "'%s', " "${ENABLED_EXTENSIONS[@]}" | sed 's/, $//'
    printf "]\n"
} > /usr/share/glib-2.0/schemas/zz2-bluespin-extensions.gschema.override

glib-compile-schemas /usr/share/glib-2.0/schemas

# DX Variant
if [[ "${IMAGE_NAME}" == "bluespin-dx" ]]; then
    install -Dm0644 -t /usr/share/flatpak/preinstall.d/ \
        /ctx/files/usr/share/flatpak/preinstall.d/bluespin-dx.preinstall

    dnf -y install --skip-unavailable \
        fedora-packager \
        fedora-packager-kerberos \
        gdb \
        git-credential-libsecret \
        git-evtag \
        pmbootstrap \
        wireshark \
        dvb-tools \
        v4l-utils \
        feedbackd \
        nextcloud-client-nautilus \
        tio

    dnf -y copr enable lorbus/calls
    dnf -y install calls
    dnf -y copr disable lorbus/calls
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

# Cleanup
dnf clean all

find /var/* -maxdepth 0 -type d \! -name cache -exec rm -fr {} \;
find /var/cache/* -maxdepth 0 -type d \! -name libdnf5 \! -name rpm-ostree -exec rm -fr {} \;
