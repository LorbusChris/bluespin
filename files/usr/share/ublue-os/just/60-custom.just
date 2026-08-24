# bluespin's ujust additions. Both bases' entry justfiles import this path
# optionally (`import? .../60-custom.just`), so one file serves Bluefin and
# plain Silverblue alike.

# Enroll bluespin's Secure Boot key - needed to boot the surface kernel with Secure Boot enabled
enroll-bluespin-secureboot-key:
    #!/usr/bin/bash
    set -euo pipefail
    echo "This enrolls bluespin's Secure Boot signing key (MOK) so the signed"
    echo "kernel-surface boots with Secure Boot enabled."
    echo
    echo "mokutil will ask you to create a one-time password. At the next boot,"
    echo "the blue MOK manager appears (QWERTY layout): choose 'Enroll MOK',"
    echo "'Continue', 'Yes', and enter that password."
    sudo mokutil --import /usr/lib/pki/bluespin-secureboot.der
