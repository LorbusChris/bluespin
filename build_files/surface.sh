#!/bin/bash
# The surface layer, built ON TOP of the bluespin image: everything
# here is what makes a Surface a Surface -- the kernel and its friends. The
# per-platform identity, desktop and extension finishing (and the /var
# cleanup) come after, from variant-finish.sh.
set -xeuo pipefail

# shellcheck source=build_files/kmod.sh
source /ctx/build_files/kmod.sh

# The surface kernel and iptsd from our own @mobility/surface COPR,
# built per Fedora branch from linux-surface's patches rebased onto
# Fedora's kernel-ark (LorbusChris/linux, the linux-*-surface-arkify
# branches). The COPR packages it AS `kernel`, versioned ahead of the
# branch's stock kernel, so installing "the newest kernel" with the COPR
# enabled is what selects it. linux-surface itself publishes for f43
# only; its iptsd links libspdlog.so.1.15, which 45 and later no longer
# ship -- and one source for every branch beats two.
#
# libwacom is upgraded below inside the same COPR window. linux-surface's
# own published libwacom-surface (2.17) is uninstallable here -- symbol
# versions older than libinput requires, an unversioned -data provides --
# and stock libwacom cannot express the Surface entries at all: it
# rejects their virt|/mei| DeviceMatch and never maps BUS_VIRTUAL
# devices, so iptsd's pen devices stay unmatched and GNOME loses
# pen-display metadata past the Surface Go. So the COPR builds Fedora's
# own libwacom spec with the linux-surface patches on top
# (pocketblue-packages surface/libwacom) and it version-wins over stock,
# the same way the kernel does.
#
# Secure Boot: the COPR signs the kernel image with Red Hat's test keys,
# which shim does not trust, so it is re-signed below with our own MOK
# key when the build has it. Users enroll the certificate once with
# `ujust enroll-secureboot-key`.

# Remove the stock kernel first: the COPR build replaces it under the
# same package names, and the image must ship exactly one kernel.
# Tolerate packages the base does not ship; under `set -e` an
# unconditional erase of a missing package aborts the build.
for pkg in kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra; do
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

# Install Kernel + touch daemon. Enable/install/disable so the COPR is not
# left active in the shipped image; enabled alongside Fedora's repos rather
# than --repo, which would hide iptsd's Fedora dependencies (cairomm, ...)
# from the resolver. The kernel is installed at the EXACT EVR the
# kernel-builder stage resolved and recorded -- never "the newest":
# on a rawhide-content base a mainline rc (7.3-rc0) overtakes the
# surface rebase (7.2.x), and newest-wins would quietly ship the stock
# kernel with a module built for another one. libwacom gets the same
# exact-EVR treatment from the same COPR.
dnf -y copr enable @mobility/surface
kevr="$(cat /kernel-out/kver)"
kevr="${kevr%.*}"
dnf -y install --setopt=disable_excludes=* \
    "kernel-${kevr}" \
    "kernel-core-${kevr}" \
    "kernel-modules-${kevr}" \
    "kernel-modules-core-${kevr}" \
    "kernel-modules-extra-${kevr}" \
    iptsd
wacom_evr="$(dnf -q repoquery --qf '%{VERSION}-%{RELEASE}\n' \
    --disablerepo='*' \
    --enablerepo='copr:copr.fedorainfracloud.org:group_mobility:surface' \
    libwacom | sort -V | tail -1)"
if [[ -z "${wacom_evr}" ]]; then
    echo "the @mobility/surface COPR has no libwacom for this branch" >&2
    exit 1
fi
# allow_vendor_change: replacing Fedora's libwacom with the COPR build
# IS a vendor change, which newer dnf5 blocks by default -- silently for
# `upgrade` ("Nothing to do"), loudly for install. The kernel above only
# sidesteps this because the stock one is erased first.
dnf -y install --setopt=allow_vendor_change=true \
    "libwacom-${wacom_evr}" "libwacom-data-${wacom_evr}"
dnf -y copr disable @mobility/surface

# Fail loudly if stock won the libwacom version race (Fedora bumped it
# and the COPR has not rebuilt yet) rather than quietly ship a surface
# image without pen metadata.
rpm -q libwacom --qf '%{RELEASE}' | grep -q '\.surface'

# Pin what we just chose: without the lock, anything resolving kernel
# afterwards could pull Fedora's build back in over the COPR's.
dnf versionlock add kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra

# Regenerate initramfs. Exactly one kernel is installed now, so its EVR
# is THE kernel version.
QUALIFIED_KERNEL="$(rpm -q kernel-core --qf '%{VERSION}-%{RELEASE}.%{ARCH}')"

# The kernel-builder stage resolved its kernel from the same COPR,
# independently. If it saw a different EVR (a COPR publish landing
# mid-build), its module and signed vmlinuz target a kernel this image
# does not ship -- fail now, before dracut spends a minute on it.
if [[ "${QUALIFIED_KERNEL}" != "$(cat /kernel-out/kver)" ]]; then
    echo "kernel-builder built for $(cat /kernel-out/kver) but this image ships ${QUALIFIED_KERNEL}; rerun the build" >&2
    exit 1
fi

export DRACUT_NO_XATTR=1
/usr/bin/dracut --no-hostonly --kver "$QUALIFIED_KERNEL" --reproducible -v --add ostree -f "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"
chmod 0600 "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"

# Secure Boot. The COPR signs vmlinuz with Red Hat's TEST keys, which
# shim rejects, so the kernel-builder stage re-signed it with our MOK key
# -- when the build had the key; the private key is only ever mounted
# into that throwaway stage (see build_files/kernel-builder.sh, which
# also explains why vmlinuz is the only file that needs this). Here the
# signed image just replaces the packaged one. The enrolment candidate
# ships as /usr/lib/pki/bluespin-secureboot.der, and the ujust recipe
# wraps `mokutil --import` for it. Without the key the builder stage
# already warned; nothing to do here.
if [[ -f /kernel-out/vmlinuz ]]; then
    install -m0755 /kernel-out/vmlinuz "/usr/lib/modules/${QUALIFIED_KERNEL}/vmlinuz"
fi


# The v4l2loopback module for THIS kernel, from the surface flavor of the
# kernel-builder stage (the bluespin layer installed the stock-kernel build,
# which left with the erased kernel above).
install_v4l2loopback_artifacts
