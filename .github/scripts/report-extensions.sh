#!/bin/bash
# Prints a markdown table of every installed GNOME Shell extension and the
# shell versions it declares, against the shell the image actually ships.
# Meant to be run inside the built image; the rawhide workflow feeds the
# output into the job summary, which is the question that build exists to ask.
set -euo pipefail

version="$(rpm -q --qf '%{version}' gnome-shell)"
# Leading digits only: a pre-release is packaged as 51~beta, but extensions
# declare plain "51"
major="$(printf '%s' "${version}" | grep -oE '^[0-9]+')"

echo "## GNOME ${version} (Fedora $(rpm -E %fedora))"
echo
echo "| Extension | declares | loads on ${major} |"
echo "| --- | --- | --- |"

for dir in /usr/share/gnome-shell/extensions/*/; do
    [[ -f "${dir}/metadata.json" ]] || continue
    uuid="$(basename "${dir}")"
    declared="$(jq -r '[.["shell-version"][]] | join(", ")' "${dir}/metadata.json")"
    if jq -e --arg v "${major}" '.["shell-version"] | index($v)' \
        "${dir}/metadata.json" > /dev/null; then
        loads="yes"
    else
        loads="**no**"
    fi
    # shellcheck disable=SC2016  # backticks are markdown, not a subshell
    printf '| `%s` | %s | %s |\n' "${uuid}" "${declared}" "${loads}"
done
