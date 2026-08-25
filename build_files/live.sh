#!/usr/bin/bash
# The container-native ISO contract (v0.1.0), as a layer that never ships.
#
# Titanoboa builds a live ISO out of a container image, and expects that
# image to carry the whole live environment: an installer, the livesys
# session scripts, an initramfs that can boot a squashfs, the EFI payload
# where image-builder looks for it, and /usr/lib/bootc-image-builder/iso.yaml
# describing the ISO itself. Bluefin bakes all of that into the images it
# publishes; we do not -- an installer belongs on install media, not on
# every phone and desktop that only ever updates. So this runs as its own
# Containerfile stage FROM an already-built platform image, at media
# build time, and what comes out is install media in container form:
# published and signed as <platform>-live:<branch>-<arch>, verified
# before it becomes an ISO, and nobody's update target. What the
# installed system tracks is INSTALL_REF -- a channel alias, so a
# machine installed from a `latest` ISO follows stable across the next
# Fedora branch on its own.
#
# The pieces, and why each is here, follow bluefin's
# build_files/base/21-container-native-iso.sh and titanoboa's own examples.

echo "::group:: ===$(basename "$0")==="

set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-bluespin}"
: "${INSTALL_REF:?the image an install should track, e.g. ghcr.io/lorbuschris/bluespin:latest}"
ISO_LABEL="${ISO_LABEL:-${IMAGE_NAME}}"

# The live environment's own packages. anaconda-live is the installer,
# livesys-scripts turns a booted image into a live session, dracut-live
# supplies the dmsquash modules the initramfs below needs. The grub
# payload image-builder wants is named per architecture -- and only x86
# has a -cdboot package; aarch64 gets the modules instead.
live_packages=(
    anaconda-live
    dracut-live
    livesys-scripts
)
case "$(uname -m)" in
x86_64) live_packages+=(grub2-efi-x64-cdboot) ;;
aarch64) live_packages+=(grub2-efi-aa64-modules) ;;
*)
    echo "no live grub payload known for $(uname -m)" >&2
    exit 1
    ;;
esac
dnf -y install "${live_packages[@]}"

# The shipping initramfs boots a disk; this one has to boot the squashfs
# the ISO carries. Exactly one kernel is expected -- surface swaps its
# kernel, fp5 never comes through here -- and a second one would silently
# leave the ISO booting the wrong initramfs.
mapfile -t kernels < <(ls -1 /usr/lib/modules)
if [[ "${#kernels[@]}" -ne 1 ]]; then
    echo "expected exactly one kernel in /usr/lib/modules, found: ${kernels[*]}" >&2
    exit 1
fi
kernel="${kernels[0]}"

# The packages above pull a newer dracut than the base image was built
# with, and a dracut that has dropped a module the base's own config
# still asks for is a fatal error -- today that is systemd-pcrphase,
# requested by Silverblue's 20-atomic-tpm-luks.conf and gone in dracut
# 111. A live medium unlocks nothing, so drop whichever of those has
# actually disappeared, and stop dropping it the day it comes back.
omit=()
for module in systemd-pcrphase tpm2-tss; do
    if ! compgen -G "/usr/lib/dracut/modules.d/*${module}" > /dev/null; then
        echo "dracut $(rpm -q --qf '%{VERSION}' dracut) has no ${module} module; omitting it"
        omit+=("${module}")
    fi
done

echo "Regenerating the initramfs for ${kernel} with the live modules"
export DRACUT_NO_XATTR=1
/usr/bin/dracut --no-hostonly --kver "${kernel}" --reproducible -v \
    --add "ostree dmsquash-live dmsquash-live-autooverlay" \
    ${omit[0]:+--omit "${omit[*]}"} \
    -f "/usr/lib/modules/${kernel}/initramfs.img"
chmod 0600 "/usr/lib/modules/${kernel}/initramfs.img"

# The live session: GNOME, and livesys's extension hook to quiet the
# services that make no sense on media -- updates that would fight the
# installer for bandwidth, the VPN, a flatpak preinstall onto a tmpfs --
# and to put the installer where someone can find it.
echo 'livesys_session=gnome' >/etc/sysconfig/livesys
systemctl enable livesys.service livesys-late.service

install -Dm0755 /dev/stdin /usr/lib/bluespin/livesys-session-extra <<'EOF'
cat >/usr/share/glib-2.0/schemas/zz4-bluespin-live.gschema.override <<'SCHEMA'
[org.gnome.shell]
welcome-dialog-last-shown-version='4294967295'
favorite-apps = ['liveinst.desktop', 'anaconda.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Ptyxis.desktop']

[org.gnome.settings-daemon.plugins.power]
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='nothing'
sleep-inactive-ac-timeout=0
sleep-inactive-battery-timeout=0

[org.gnome.desktop.session]
idle-delay=uint32 0
SCHEMA

glib-compile-schemas /usr/share/glib-2.0/schemas

for unit in \
    uupd.timer \
    tailscaled.service \
    bluespin-flatpak-preinstall.service \
    bootloader-update.service \
    rpm-ostreed-automatic.timer \
    bluespin-dx-groups.service; do
    systemctl --no-reload disable "$unit" 2>/dev/null || :
    systemctl stop "$unit" 2>/dev/null || :
done
EOF
install -Dm0644 /dev/stdin /usr/lib/tmpfiles.d/bluespin-live.conf <<'EOF'
d /var/lib/livesys 0755 root root -
C /var/lib/livesys/livesys-session-extra 0755 root root - /usr/lib/bluespin/livesys-session-extra
EOF

# Our images empty /boot (cleanup_silverblue_image), and both
# image-builder and titanoboa read the EFI payload from /boot/efi/EFI --
# so put it back from where bootupd keeps it.
shopt -s nullglob
efi_dirs=(/usr/lib/efi/*/*/EFI)
if [[ "${#efi_dirs[@]}" -eq 0 ]]; then
    echo "no EFI payload under /usr/lib/efi to build an ISO from" >&2
    exit 1
fi
mkdir -p /boot/efi/EFI
for efi_dir in "${efi_dirs[@]}"; do
    cp -a "${efi_dir}/." /boot/efi/EFI/
done
case "$(uname -m)" in
x86_64) cp -v /boot/efi/EFI/fedora/grubx64.efi /boot/efi/EFI/BOOT/fbx64.efi ;;
aarch64) cp -v /boot/efi/EFI/fedora/grubaa64.efi /boot/efi/EFI/BOOT/fbaa64.efi ;;
esac

# Anaconda, told what to install: the channel alias, pulled from the
# registry rather than out of the ISO (titanoboa embeds the live rootfs
# but seeds no container storage). Signature verification is off for that
# one pull -- the policy the image itself ships has no key material at
# install time -- and the first thing the installed system does is switch
# to enforcing it, so every update after this one is verified.
mkdir -p /etc/anaconda/profile.d /usr/share/anaconda/post-scripts
install -Dm0644 /dev/stdin /etc/anaconda/profile.d/bluespin.conf <<'EOF'
# Anaconda configuration for bluespin

[Profile]
profile_id = bluespin

[Profile Detection]
os_id = bluespin

[Network]
default_on_boot = FIRST_WIRED_WITH_LINK

[Bootloader]
efi_dir = fedora
menu_auto_hide = True

[Storage]
default_scheme = BTRFS
btrfs_compression = zstd:1

[Localization]
use_geolocation = False
EOF

cat >>/usr/share/anaconda/interactive-defaults.ks <<EOF
ostreecontainer --url=${INSTALL_REF} --transport=registry --no-signature-verification
%include /usr/share/anaconda/post-scripts/bluespin-enforce-policy.ks
%include /usr/share/anaconda/post-scripts/bluespin-secureboot.ks
EOF

cat >/usr/share/anaconda/post-scripts/bluespin-enforce-policy.ks <<EOF
%post --erroronfail
bootc switch --mutate-in-place --enforce-container-sigpolicy \\
    --transport registry ${INSTALL_REF}
%end
EOF

# The same MOK certificate the installed system offers through
# \`ujust enroll-secureboot-key\`, offered once at install time instead --
# without it the virtual camera stays unavailable (and a surface machine
# will not boot with Secure Boot on at all). mokutil takes the password
# below at the next boot's MOK manager.
cat >/usr/share/anaconda/post-scripts/bluespin-secureboot.ks <<'EOF'
%post --erroronfail --nochroot
set -oue pipefail

readonly ENROLLMENT_PASSWORD="bluespin"
readonly SECUREBOOT_KEY="/mnt/sysimage/usr/lib/pki/bluespin-secureboot.der"

if [[ ! -d "/sys/firmware/efi" ]]; then
    echo "EFI mode not detected. Skipping key enrollment."
    exit 0
fi

if [[ ! -f "$SECUREBOOT_KEY" ]]; then
    echo "Secure boot key not found: $SECUREBOOT_KEY"
    exit 0
fi

mokutil --timeout -1 || :
echo -e "$ENROLLMENT_PASSWORD\n$ENROLLMENT_PASSWORD" | mokutil --import "$SECUREBOOT_KEY" || :
%end
EOF

# The contract itself: the label titanoboa gives the ISO (and names its
# file after), and the boot entries whose kernel arguments have to name
# that same label back.
install -Dm0644 /dev/stdin /usr/lib/bootc-image-builder/iso.yaml <<EOF
label: "${ISO_LABEL}"
grub2:
  default: 0
  timeout: 10
  entries:
    - name: "${IMAGE_NAME} Live"
      linux: "/images/pxeboot/vmlinuz quiet rhgb root=live:CDLABEL=${ISO_LABEL} enforcing=0 rd.live.image"
      initrd: "/images/pxeboot/initrd.img"
    - name: "${IMAGE_NAME} Live (Basic Graphics)"
      linux: "/images/pxeboot/vmlinuz quiet rhgb root=live:CDLABEL=${ISO_LABEL} enforcing=0 rd.live.image nomodeset"
      initrd: "/images/pxeboot/initrd.img"
EOF

echo "live layer ready: ${IMAGE_NAME} installing ${INSTALL_REF}, ISO label ${ISO_LABEL}"

echo "::endgroup::"
