#!/bin/bash
set -xeuo pipefail

# Copy ISO list for `install-system-flatpaks`
install -Dm0644 -t /etc/ublue-os/ /ctx/flatpaks/*.list

# Bluefin fixups
if [[ -f /usr/share/applications/gnome-system-monitor.desktop ]]; then
    sed -i '/^Hidden=true/d' /usr/share/applications/gnome-system-monitor.desktop
fi
if [[ -f /usr/share/applications/org.gnome.SystemMonitor.desktop ]]; then
    sed -i '/^Hidden=true/d' /usr/share/applications/org.gnome.SystemMonitor.desktop
fi

# Surface Variant
if [[ "${IMAGE_NAME}" == "bluespin-surface" ]]; then

    # Remove Existing Kernel
    for pkg in kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra \
            kmod-xone kmod-openrazer kmod-framework-laptop kmod-v4l2loopback v4l2loopback; do
        rpm --erase $pkg --nodeps
    done

    # Install Linux Surface Kernel
    dnf config-manager addrepo --from-repofile=https://pkg.surfacelinux.com/fedora/linux-surface.repo
    dnf config-manager setopt linux-surface.enabled=0
    # Install Kernel
    dnf -y install --setopt=disable_excludes=* --repo="linux-surface" \
        kernel-surface iptsd

    dnf versionlock add kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra

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

    dnf -y swap --repo="linux-surface" \
        libwacom-data libwacom-surface-data
    dnf -y swap --repo="linux-surface" \
        libwacom libwacom-surface

    # Regenerate initramfs
    KERNEL_SUFFIX=""
    QUALIFIED_KERNEL="$(rpm -qa | grep -P 'kernel-surface-(|'"$KERNEL_SUFFIX"'-)(\d+\.\d+\.\d+)' | sed -E 's/kernel-surface-(|'"$KERNEL_SUFFIX"'-)//')"
    export DRACUT_NO_XATTR=1
    /usr/bin/dracut --no-hostonly --kver "$QUALIFIED_KERNEL" --reproducible -v --add ostree -f "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"
    chmod 0600 "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"

fi

# Install additional fedora packages
ADDITIONAL_FEDORA_PACKAGES=(
    #calls
    chromium # for WebUSB
    feedbackd # for gnome-calls
    fedora-packager
    fedora-packager-kerberos
    firefox # as RPM for GSConnect
    git-credential-libsecret
    git-evtag
    gdb
    nodejs
    yarnpkg
    npx
    pipx
    meson
    ninja
    gettext
    rust
    dvb-tools
    #gnome-network-displays
    #gnome-shell-extension-network-displays
    libcamera-qcam
    nextcloud-client-nautilus
    pmbootstrap
    v4l-utils
    wireshark
    gnome-shell-extension-appindicator
    #gnome-shell-extension-apps-menu
    gnome-shell-extension-auto-move-windows
    gnome-shell-extension-caffeine
    gnome-shell-extension-dash-to-dock
    gnome-shell-extension-drive-menu
    #gnome-shell-extension-gsconnect
    #gnome-shell-extension-launch-new-instance
    gnome-shell-extension-light-style
    gnome-shell-extension-native-window-placement
    #gnome-shell-extension-places-menu
    gnome-shell-extension-screenshot-window-sizer
    gnome-shell-extension-status-icons
    gnome-shell-extension-system-monitor
    gnome-shell-extension-user-theme
    gnome-shell-extension-windowsNavigator
    #gnome-shell-extension-window-list
    gnome-shell-extension-workspace-indicator
)

dnf -y install --skip-unavailable \
    "${ADDITIONAL_FEDORA_PACKAGES[@]}"

dnf -y copr enable lorbus/calls
dnf -y install calls
dnf -y copr disable lorbus/calls

dnf -y copr enable lorbus/network-displays
dnf -y install gnome-network-displays gnome-network-displays-extension
dnf -y copr disable lorbus/network-displays

dnf -y copr enable lorbus/theia
dnf -y install theia-ide
dnf -y copr disable lorbus/theia

dnf -y copr enable lorbus/NetworkManager
dnf -y update NetworkManager
dnf -y copr disable lorbus/NetworkManager

# Cleanup
dnf clean all

find /var/* -maxdepth 0 -type d \! -name cache -exec rm -fr {} \;
find /var/cache/* -maxdepth 0 -type d \! -name libdnf5 \! -name rpm-ostree -exec rm -fr {} \;
