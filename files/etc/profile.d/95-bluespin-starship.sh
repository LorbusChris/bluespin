# shellcheck shell=sh
# Start the starship prompt in interactive bash shells. bash-only by
# decision: bluespin configures no other shell. POSIX guards, because every
# /bin/sh login shell sources this file too.
if [ -n "${BASH_VERSION:-}" ] && [ -x /usr/bin/starship ]; then
    case $- in
        *i*) eval "$(starship init bash)" ;;
    esac
fi
