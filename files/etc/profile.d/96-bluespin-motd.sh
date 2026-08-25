# shellcheck shell=sh
# Show the bluespin message of the day in interactive shells. Adapted from
# ublue-os-just's user-motd.sh (ublue-os/packages, Apache-2.0), pointed at
# our own executable. `ujust toggle-user-motd` flips the flag file; the
# /etc/user-motd fallback lets an admin drop in a plain-text motd with no
# tooling at all.
if [ -z "$USERMOTDSOURCED" ]; then
    USERMOTDSOURCED="Y"
    if test -d "$HOME" && test ! -e "$HOME/.config/no-show-user-motd"; then
        if test -x /usr/libexec/bluespin-motd; then
            /usr/libexec/bluespin-motd
        elif test -s /etc/user-motd; then
            cat /etc/user-motd
        fi
    fi
fi
