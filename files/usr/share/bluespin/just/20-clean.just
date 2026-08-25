# vim: set ft=make :
# Vendored from ublue-os/packages (ublue-os-just, Apache-2.0)

# Clean up old and unused podman images, volumes, flatpak packages and rpm-ostree content
clean-system:
    #!/usr/bin/bash
    podman image prune -af
    flatpak uninstall --unused
    rpm-ostree cleanup -bm
