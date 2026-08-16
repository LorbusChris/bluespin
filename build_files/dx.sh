#!/bin/bash
# The developer layer for bluespin-dx.
#
# All variants build on ghcr.io/ublue-os/bluefin rather than bluefin-dx, so
# the base carries no developer tooling and the two non-dx images are ~2 GB
# smaller. This re-creates Bluefin's dx layer for the one variant that wants
# it, adapted from their build_files/dx/00-dx.sh.
#
# The one deliberate omission is Docker: no docker-ce, docker-ce-cli,
# containerd.io, buildx/compose/model plugins, no docker.socket, no
# iptable_nat module-load or IP-forwarding sysctl for docker-in-docker.
# Podman is already in the base and podman.socket is enabled below.
set -xeuo pipefail

DX_PACKAGES=(
    # Virtualisation
    edk2-ovmf
    libvirt
    libvirt-nss
    qemu
    qemu-char-spice
    qemu-device-display-virtio-gpu
    qemu-device-display-virtio-vga
    qemu-device-usb-redirect
    qemu-img
    qemu-system-x86-core
    qemu-user-binfmt
    qemu-user-static
    virt-manager
    virt-v2v
    virt-viewer

    # System containers
    incus
    incus-agent
    lxc

    # Cockpit
    cockpit-bridge
    cockpit-machines
    cockpit-networkmanager
    cockpit-ostree
    cockpit-podman
    cockpit-selinux
    cockpit-storaged
    cockpit-system

    # Podman extras
    podman-compose
    podman-machine
    podman-tui

    # Tracing and performance
    bcc
    bpftop
    bpftrace
    iotop
    nicstat
    numactl
    sysprof
    tiptop
    trace-cmd

    # The CLI set ujust bluefin-cli would otherwise fetch from Homebrew.
    # Whatever Fedora packages comes from here; the remainder stays in the
    # trimmed cli.Brewfile below. starship is already baked into the base as a
    # binary, so it needs neither.
    bat
    chezmoi
    direnv
    eza
    fd-find
    gh
    ripgrep
    tealdeer
    trash-cli
    uutils-coreutils
    ugrep
    yq
    zoxide

    # Development odds and ends
    android-tools
    dbus-x11
    flatpak-builder
    genisoimage
    git-subtree
    git-svn
    osbuild-selinux
    p7zip
    p7zip-plugins
    udica
    util-linux-script
    wtype
    ydotool
    cascadia-code-fonts
)

dnf -y install "${DX_PACKAGES[@]}"

# ROCm does not play well with the nvidia driver; this image has no nvidia
# variant today, but keep the guard so adding one does not break it
if [[ ! "${IMAGE_NAME}" =~ nvidia ]]; then
    dnf -y install rocm-hip rocm-opencl rocm-smi rocminfo
fi

# bluespin's own additions, as opposed to everything above, which mirrors
# Bluefin's dx layer: packaging and kernel work, phone and capture hardware.
BLUESPIN_DX_PACKAGES=(
    fedora-packager
    fedora-packager-kerberos
    gdb
    git-credential-libsecret
    git-evtag
    pmbootstrap
    wireshark
    dvb-tools
    v4l-utils
    feedbackd
    nextcloud-client-nautilus
    tio
)

dnf -y install --skip-unavailable "${BLUESPIN_DX_PACKAGES[@]}"

dnf -y copr enable lorbus/calls
dnf -y install calls
dnf -y copr disable lorbus/calls

# VS Code from Microsoft's repo, enabled only for this transaction so the repo
# is never left active in the image
tee /etc/yum.repos.d/vscode.repo << 'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=0
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
dnf -y install --enablerepo=code code

# VFIO in the initramfs, for GPU passthrough to guests
install -Dm0644 /ctx/files/usr/lib/dracut/dracut.conf.d/80-vfio.conf \
    /usr/lib/dracut/dracut.conf.d/80-vfio.conf

# Relabel libvirt's /var directories at boot, and make sure the log directory
# exists to be relabelled
install -Dm0644 /ctx/files/usr/lib/systemd/system/libvirt-workaround.service \
    /usr/lib/systemd/system/libvirt-workaround.service
install -Dm0644 /ctx/files/usr/lib/tmpfiles.d/libvirt-workaround.conf \
    /usr/lib/tmpfiles.d/libvirt-workaround.conf

# Put wheel members in the groups the tooling needs
install -Dm0755 /ctx/files/usr/bin/bluespin-dx-groups /usr/bin/bluespin-dx-groups
install -Dm0644 /ctx/files/usr/lib/systemd/system/bluespin-dx-groups.service \
    /usr/lib/systemd/system/bluespin-dx-groups.service

# ujust bluefin-cli fetches cli.Brewfile from Homebrew; most of that set is
# now installed above as RPMs, so trim it to what Fedora does not package.
# ublue-bling only aliases tools it can find, so the shell integration is
# unaffected. brew itself is left alone for anyone who wants it.
tee /usr/share/ublue-os/homebrew/cli.Brewfile << 'EOF'
# Trimmed by bluespin-dx: everything else in this set ships as an RPM.
tap "valkyrie00/bbrew"
brew "atuin"
brew "bash-preexec"
brew "valkyrie00/bbrew/bbrew"
brew "dysk"
brew "mise"
EOF

# Likewise ide.Brewfile: this image installs VS Code as an RPM from
# Microsoft's repo, so the cask would be a second copy of the same editor.
# The Insiders and VSCodium casks are separate products and stay.
sed -i '/^cask "ublue-os\/tap\/visual-studio-code-linux"$/d' \
    /usr/share/ublue-os/homebrew/ide.Brewfile

systemctl enable podman.socket
systemctl enable libvirt-workaround.service
systemctl enable bluespin-dx-groups.service
