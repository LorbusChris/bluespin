#!/bin/bash
# The developer layer for bluespin-dx.
#
# Every platform builds on plain Fedora Silverblue, so nothing carries
# developer tooling by default and the two non-dx images stay small. This is
# the developer layer for the one platform that wants it, adapted from
# Bluefin's build_files/dx/00-dx.sh.
#
# The one deliberate omission is Docker: no docker-ce, docker-ce-cli,
# containerd.io, buildx/compose/model plugins, no docker.socket, no
# iptable_nat module-load or IP-forwarding sysctl for docker-in-docker.
# Podman is already in the base and podman.socket is enabled below.
set -xeuo pipefail

DX_PACKAGES=(
    # Virtualisation. Deliberately no `qemu` and no `libvirt`: both are
    # metapackages that drag in every architecture's emulator and every
    # hypervisor and storage driver -- Xen, LXC and the gluster/rbd/iscsi
    # cluster backends included, none of which a desktop KVM host runs.
    # What one does run is spelled out instead: the x86 KVM core, the
    # spice/virtio pieces the tools below actually drive, and libvirt's
    # qemu driver with the dir/disk storage backends. The matching
    # --exclude on the install below keeps virt-manager's recommend of
    # the fat metas from undoing this.
    edk2-ovmf
    gtksourceview4 # virt-manager's XML editor (its recommend)
    libvirt-client
    libvirt-daemon
    libvirt-daemon-config-network
    libvirt-daemon-driver-interface
    libvirt-daemon-driver-network
    libvirt-daemon-driver-nodedev
    libvirt-daemon-driver-nwfilter
    libvirt-daemon-driver-qemu
    libvirt-daemon-driver-secret
    libvirt-daemon-driver-storage-core
    libvirt-nss
    qemu-audio-spice
    qemu-char-spice
    qemu-device-display-virtio-gpu
    qemu-device-display-virtio-vga
    qemu-device-usb-redirect
    qemu-img
    qemu-system-x86-core
    qemu-ui-spice-core
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

    # The CLI set Bluefin's bluefin-cli recipe fetches from Homebrew, as
    # Fedora packages instead. Starship is installed separately for every
    # platform (build_files/starship.sh).
    bat
    chezmoi
    direnv
    fd-find
    gh
    ripgrep
    # tldr rather than tealdeer, Bluefin's pick: rust-tealdeer was retired
    # from Fedora before 45 branched, and tldr is the same command from the
    # Python client, on every branch.
    tldr
    trash-cli
    uutils-coreutils
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

# --exclude: virt-manager Recommends (libvirt-daemon-kvm or
# libvirt-daemon-qemu), and either alternative re-imports the meta world
# the list above exists to avoid (the full storage-driver set, gluster
# included, and libvirt-daemon-qemu even requires the bare qemu meta).
# Excluded, the weak dependency is unsatisfiable and dnf skips it.
dnf -y install \
    --exclude=libvirt-daemon-kvm \
    --exclude=libvirt-daemon-qemu \
    "${DX_PACKAGES[@]}"

# ROCm does not play well with the nvidia driver; this image has no nvidia
# variant today, but keep the guard so adding one does not break it
if [[ ! "${IMAGE_NAME}" =~ nvidia ]]; then
    dnf -y install rocm-hip rocm-opencl rocm-smi rocminfo
fi

# bluespin's own additions, as opposed to everything above, which mirrors
# Bluefin's dx layer: packaging and kernel work, phone and capture hardware.
BLUESPIN_DX_PACKAGES=(
    # The classics the Bluefin base used to provide for everyone; here they
    # are developer tooling
    git
    vim-enhanced

    # Network diagnostics
    tcpdump
    traceroute
    net-tools
    usbip
    waypipe

    # The C toolchain, as product. (The v4l2loopback build needs one too, but
    # that happens in the Containerfile's kernel-builder stage and never
    # touches this image -- see build_files/kernel-builder.sh.)
    gcc
    gcc-c++
    binutils
    make
    glibc-devel
    libstdc++-devel
    kernel-headers
    libxcrypt-devel
    setools-console

    # Low-level hardware probing
    lshw
    i2c-tools
    evtest
    fxload
    igt-gpu-tools
    libcamera-tools
    libcamera-gstreamer

    copr-cli
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
    # Mobile messaging plumbing: the MMS daemon and the libpurple SMS plugin
    # that Chatty (dx catalog) drives over D-Bus when a modem is attached
    mmsd-tng
    purple-mm-sms
    nextcloud-client-nautilus
    tio
)

dnf -y install "${BLUESPIN_DX_PACKAGES[@]}"

dnf -y copr enable lorbus/calls
dnf -y install calls
dnf -y copr disable lorbus/calls

# cosign, to verify the very images and attestations this machine runs and
# lets its owner build. Fedora does not package it; sigstore publishes RPMs
# with every release, pinned here the way starship.sh pins its binary:
# exact version, exact checksum. Renovate bumps the version (manager in
# renovate.json5) and the checksum mismatch that follows is the loud
# reminder to update the hash from the release's cosign_checksums.txt.
# renovate: datasource=github-releases depName=sigstore/cosign
COSIGN_VERSION=v3.1.3
COSIGN_RPM_SHA256=2e126115465ba55d03d3aea606cced2a24a1df578c8feb1d9384d584ebda9226
cosign_rpm="$(mktemp -d)/cosign.rpm"
curl -fsSL --retry 3 -o "${cosign_rpm}" \
    "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-${COSIGN_VERSION#v}-1.x86_64.rpm"
cosign_got="$(sha256sum "${cosign_rpm}" | cut -d' ' -f1)"
if [[ "${cosign_got}" != "${COSIGN_RPM_SHA256}" ]]; then
    echo "::error::cosign ${COSIGN_VERSION} x86_64 rpm hashes to ${cosign_got}, expected ${COSIGN_RPM_SHA256}" >&2
    exit 1
fi
dnf -y install "${cosign_rpm}"
rm -f "${cosign_rpm}"

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

# The containerized CLI functions (kubectl, helm, k9s, flux, argocd, grype,
# syft) -- see the file for the reasoning
install -Dm0644 /ctx/files/etc/profile.d/97-bluespin-container-clis.sh \
    /etc/profile.d/97-bluespin-container-clis.sh

systemctl enable podman.socket
systemctl enable libvirt-workaround.service
systemctl enable bluespin-dx-groups.service
