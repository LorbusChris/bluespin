# bluespin's own ujust recipes, imported by the vendored entry justfile
# (files/usr/share/bluespin/just/justfile).

# Enroll bluespin's Secure Boot key - needed to boot the surface kernel with Secure Boot enabled
enroll-secureboot-key:
    #!/usr/bin/bash
    set -euo pipefail
    echo "This enrolls bluespin's Secure Boot signing key (MOK) so the signed"
    echo "kernel-surface boots with Secure Boot enabled."
    echo
    echo "mokutil will ask you to create a one-time password. At the next boot,"
    echo "the blue MOK manager appears (QWERTY layout): choose 'Enroll MOK',"
    echo "'Continue', 'Yes', and enter that password."
    sudo mokutil --import /usr/lib/pki/bluespin-secureboot.der

# Let your user drive Tailscale without sudo (sets you as the operator)
tailscale-operator:
    sudo tailscale set --operator="$USER"

# Install an opt-in flatpak set, per-user: extra or dx
install-flatpaks SET="prompt":
    #!/usr/bin/bash
    set -euo pipefail
    # Per-user on purpose: the preinstalled apps are system installations
    # owned by the image; these catalogs are a personal choice, need no
    # root, and uninstall without touching the OS-level set. uupd's flatpak
    # module updates both scopes.
    setname={{ SET }}
    if [ "${setname}" = "prompt" ]; then
        echo "Which set?"
        setname=$(cd /usr/share/bluespin/flatpaks && ls -- *.list | sed 's/\.list$//' | xargs ugum choose)
    fi
    file="/usr/share/bluespin/flatpaks/${setname}.list"
    if [ ! -f "${file}" ]; then
        echo "no such set '${setname}'; available:"
        ls /usr/share/bluespin/flatpaks/ | sed -e 's/\.list$//' -e 's/^/  /'
        exit 1
    fi
    flatpak remote-add --user --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
    grep -vE '^[[:space:]]*(#|$)' "${file}" | \
        xargs flatpak install --user -y --noninteractive --or-update flathub

# Remove everything an opt-in flatpak set installed (user scope only)
remove-flatpaks SET="prompt":
    #!/usr/bin/bash
    set -euo pipefail
    setname={{ SET }}
    if [ "${setname}" = "prompt" ]; then
        echo "Which set?"
        setname=$(cd /usr/share/bluespin/flatpaks && ls -- *.list | sed 's/\.list$//' | xargs ugum choose)
    fi
    file="/usr/share/bluespin/flatpaks/${setname}.list"
    if [ ! -f "${file}" ]; then
        echo "no such set '${setname}'; available:"
        ls /usr/share/bluespin/flatpaks/ | sed -e 's/\.list$//' -e 's/^/  /'
        exit 1
    fi
    while IFS= read -r app; do
        flatpak uninstall --user -y --noninteractive "${app}" 2>/dev/null \
            || echo "  ${app} was not installed, skipping"
    done < <(grep -vE '^[[:space:]]*(#|$)' "${file}")

# Add a disk swap file behind zram (default 32G; btrfs /var; needs sudo)
setup-swapfile SIZE="32G":
    #!/usr/bin/bash
    set -euo pipefail
    # zram is sized for the common case; a machine that runs big IDE sessions,
    # agents and builds at once wants real headroom behind it -- see
    # docs/memory-pressure.md. The file gets its own btrfs subvolume: a swap
    # file pins its extents, so the subvolume holding it can never be
    # snapshotted, and that restriction should not land on /var itself. The
    # swap unit is already in the image (var-swap-swapfile.swap, priority 10
    # behind zram's 100); it only waits for the file to exist. No SELinux
    # relabelling: systemd activates swap through swapon, which runs as
    # fsadm_t, and the policy leaves that domain unconfined for files.
    size={{ SIZE }}
    file=/var/swap/swapfile
    if [ -e "${file}" ]; then
        echo "${file} exists already:"
        swapon --show
        echo "run 'ujust remove-swapfile' first to change its size"
        exit 1
    fi
    fstype=$(stat -f -c %T /var)
    if [ "${fstype}" != "btrfs" ]; then
        echo "/var is ${fstype}; this recipe only knows how to do btrfs"
        exit 1
    fi
    echo "Creating a ${size} swap file at ${file}, in its own btrfs subvolume."
    sudo btrfs subvolume create /var/swap
    sudo btrfs filesystem mkswapfile --size "${size}" "${file}"
    sudo systemctl start var-swap-swapfile.swap
    swapon --show

# Remove the swap file setup-swapfile created
remove-swapfile:
    #!/usr/bin/bash
    set -euo pipefail
    sudo systemctl stop var-swap-swapfile.swap
    sudo rm -f /var/swap/swapfile
    sudo btrfs subvolume delete /var/swap
    swapon --show
