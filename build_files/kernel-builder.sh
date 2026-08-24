#!/bin/bash
# The kernel-builder stage (see Containerfile): anything that must INSTALL
# tooling in order to BUILD an artifact runs here, in a stage that is thrown
# away. The final image never sees a compiler, kernel-devel or sbsigntools --
# not even as an install-then-remove in its rpmdb history -- and the Secure
# Boot private key is only ever mounted into this stage. build.sh consumes
# what this writes to /out (mounted there as /kernel-out):
#
#   kver                 the kernel release everything here targeted
#   v4l2loopback.ko.xz   the virtual-camera module, signed when the key was
#                        present (unsigned otherwise, with a warning)
#   vmlinuz              surface only, key only: the kernel image re-signed
#                        with the bluespin MOK key
#
# This stage FROMs the same base as the final image, so on the vanilla
# platforms the kernel here IS the kernel that ships. The surface leg
# resolves its kernel from the @mobility/surface COPR in both stages
# independently; build.sh asserts both saw the same EVR (the kver file), so
# a COPR publish landing mid-build fails the build instead of shipping
# artifacts for a kernel the image does not carry.
set -xeuo pipefail

OUT=/out
install -d "${OUT}"

############################################################################
# The kernel to build against
############################################################################
if [[ "${IMAGE_NAME}" == "bluespin-surface" ]]; then
    # The COPR ships the surface kernel AS `kernel` (kernel-ark packaging
    # with the linux-surface patches), versioned ahead of the branch's stock
    # kernel. The stock kernel-core is already installed here, and dnf
    # treats a plain "install kernel-core" as satisfied by it -- so resolve
    # the COPR's EVR explicitly and ask for exactly that, which also pins
    # -core (the vmlinuz to re-sign) and -devel (the build tree) to the
    # same build. The stock kernel can stay: kernel packages are
    # installonly, this stage ships nothing, and every path below names its
    # kver explicitly.
    dnf -y copr enable @mobility/surface
    kevr="$(dnf -q repoquery --qf '%{VERSION}-%{RELEASE}\n' \
        --disablerepo='*' \
        --enablerepo='copr:copr.fedorainfracloud.org:group_mobility:surface' \
        kernel-core | sort -V | tail -1)"
    if [[ -z "${kevr}" ]]; then
        echo "the @mobility/surface COPR has no kernel-core for this branch (chroot still building?)" >&2
        exit 1
    fi
    dnf -y install --setopt=disable_excludes=* \
        "kernel-core-${kevr}" "kernel-devel-${kevr}"
    dnf -y copr disable @mobility/surface
    kver="$(rpm -q "kernel-core-${kevr}" --qf '%{VERSION}-%{RELEASE}.%{ARCH}')"
else
    # The base's own kernel. Its devel package must match EXACTLY; a
    # mismatched build produces a module the shipped kernel refuses to load.
    # Fedora's branched updates repos retain the EVRs the bases pin, but the
    # rawhide repo keeps only the newest kernel -- when the base image trails
    # it, koji still has every build.
    kver="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core)"
    kevr="$(rpm -q --qf '%{VERSION}-%{RELEASE}' kernel-core)"
    karch="${kver##*.}"
    kv="${kevr%%-*}"
    kr="${kevr#*-}"
    dnf -y install "kernel-devel-${kevr}" || dnf -y install \
        "https://kojipkgs.fedoraproject.org/packages/kernel/${kv}/${kr}/${karch}/kernel-devel-${kevr}.${karch}.rpm"
fi
echo "${kver}" > "${OUT}/kver"

############################################################################
# v4l2loopback: the virtual camera device (OBS "Start Virtual Camera" and
# friends), vendored as a submodule from upstream and built against the
# exact kernel above -- the same mechanism ublue's akmods use, with our key.
# The kernel itself stays exactly as its distributor signed it (Fedora's for
# the vanilla platforms, ours for surface); the module signature only lets
# the kernel LOAD it under Secure Boot once the key is enrolled
# (ujust enroll-secureboot-key).
############################################################################
dnf -y install gcc make kmod xz elfutils-libelf-devel

# /ctx is a read-only bind mount; build in a scratch copy
src="$(mktemp -d)"
cp -r /ctx/kmods/v4l2loopback/. "${src}/"
make -C "${src}" KERNELRELEASE="${kver}" \
    KERNEL_DIR="/usr/src/kernels/${kver}" \
    V4L2LOOPBACK_SNAPSHOT_VERSION="${V4L2LOOPBACK_VERSION:-snapshot}" \
    v4l2loopback.ko

if [[ -f /run/secrets/secureboot_key ]]; then
    # sign-file wants the certificate in DER form; the PEM twin is for
    # sbsign and humans
    "/usr/src/kernels/${kver}/scripts/sign-file" sha256 \
        /run/secrets/secureboot_key /ctx/files/usr/lib/pki/bluespin-secureboot.der \
        "${src}/v4l2loopback.ko"
    # Fail here rather than ship a module that silently cannot load with
    # Secure Boot on
    modinfo -F signer "${src}/v4l2loopback.ko" | grep -q "bluespin Secure Boot Signing Key"
else
    echo "::warning::no secureboot_key build secret: v4l2loopback is unsigned and will not load with Secure Boot enabled"
fi

# Sign-then-compress: the signature sits inside what xz wraps, exactly how
# Fedora ships its own signed modules
xz -f "${src}/v4l2loopback.ko"
cp "${src}/v4l2loopback.ko.xz" "${OUT}/v4l2loopback.ko.xz"
rm -rf "${src}"

############################################################################
# surface: re-sign the kernel image. Only vmlinuz needs a signature shim can
# verify (the in-tree modules were signed with the kernel's own ephemeral
# key, which the kernel already trusts), and the COPR signs it with Red
# Hat's TEST keys, which shim rejects.
############################################################################
if [[ "${IMAGE_NAME}" == "bluespin-surface" ]]; then
    if [[ -f /run/secrets/secureboot_key ]]; then
        dnf -y install sbsigntools
        sbsign --key /run/secrets/secureboot_key \
            --cert /ctx/files/usr/lib/pki/bluespin-secureboot.pem \
            --output "${OUT}/vmlinuz" "/usr/lib/modules/${kver}/vmlinuz"
        # Fail here rather than ship a kernel that silently cannot boot with
        # Secure Boot on
        sbverify --cert /ctx/files/usr/lib/pki/bluespin-secureboot.pem \
            "${OUT}/vmlinuz"
    else
        echo "::warning::no secureboot_key build secret: the surface kernel keeps the COPR's test-key signature and will not boot with Secure Boot enabled"
    fi
fi
