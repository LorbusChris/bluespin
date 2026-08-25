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
