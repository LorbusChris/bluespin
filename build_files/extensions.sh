#!/bin/bash
# Shared GNOME Shell extension handling, sourced by build.sh and
# build_rawhide.sh so both bases install and enable the same set the same way.
set -xeuo pipefail

EXT_DIR=/usr/share/gnome-shell/extensions

# Install the extensions Fedora does not package, vendored as submodules the
# same way the Bluefin base handles its own.
install_vendored_extensions() {
    # Weather or Not: the extension lives in a subdirectory named after its UUID
    cp -r "/ctx/extensions/weather-or-not/weatherornot@somepaulo.github.io" "${EXT_DIR}/"

    # NekoTorch: extension sources sit at the repository root
    install -d "${EXT_DIR}/nekotorch@nekocwd.gitlab.com"
    cp -r /ctx/extensions/nekotorch/{extension.js,prefs.js,utils.js,logger.js,stylesheet.css,metadata.json,icons,schemas} \
        "${EXT_DIR}/nekotorch@nekocwd.gitlab.com/"
    # udev rule granting the seat access to the torch LEDs
    install -Dm0644 /ctx/extensions/nekotorch/99-flash.rules /usr/lib/udev/rules.d/99-flash.rules

    local ext shell_major
    # Leading digits only: released versions look like 50.3, but a pre-release
    # is packaged as 51~beta, and extensions declare plain "51"
    shell_major="$(rpm -q --qf '%{version}' gnome-shell | grep -oE '^[0-9]+')"
    for ext in "weatherornot@somepaulo.github.io" "nekotorch@nekocwd.gitlab.com"; do
        glib-compile-schemas --strict "${EXT_DIR}/${ext}/schemas"
        # Fail loudly if a vendored extension does not cover the shell we ship,
        # since a mismatch silently leaves it disabled at login. On a
        # pre-release base this is the point: it turns "quietly disabled on the
        # new GNOME" into a build failure we can act on.
        jq -e --arg v "${shell_major}" '.["shell-version"] | index($v)' \
            "${EXT_DIR}/${ext}/metadata.json" > /dev/null
    done
}

# Extensions the Bluefin base normally vendors for us. Only needed on a plain
# Fedora base, where nothing supplies them -- the shipping variants take
# Bluefin's copies instead (see the note in build.sh). Vendored from our forks
# because upstream had not declared the current shell yet.
install_bluefin_replacement_extensions() {
    # caffeine and search-light ship the extension at a known directory; bazaar
    # and gradia keep it in src/ with schemas and icons alongside
    install -d "${EXT_DIR}/appindicatorsupport@rgcjonas.gmail.com"
    cp -r /ctx/extensions/appindicator/{*.js,metadata.json,schemas,icons,interfaces-xml} \
        "${EXT_DIR}/appindicatorsupport@rgcjonas.gmail.com/"

    cp -r "/ctx/extensions/caffeine/caffeine@patapon.info" "${EXT_DIR}/"

    install -d "${EXT_DIR}/search-light@icedman.github.com"
    cp -r /ctx/extensions/search-light/{*.js,metadata.json,stylesheet.css,schemas} \
        "${EXT_DIR}/search-light@icedman.github.com/"

    install -d "${EXT_DIR}/bazaar-integration@kolunmi.github.io"
    cp -r /ctx/extensions/bazaar-integration/src/. \
        "${EXT_DIR}/bazaar-integration@kolunmi.github.io/"

    install -d "${EXT_DIR}/gradia-integration@alexandervanhee.github.io"
    cp -r /ctx/extensions/gradia-integration/src/. \
        "${EXT_DIR}/gradia-integration@alexandervanhee.github.io/"
    cp -r /ctx/extensions/gradia-integration/icons \
        "${EXT_DIR}/gradia-integration@alexandervanhee.github.io/"
    install -d "${EXT_DIR}/gradia-integration@alexandervanhee.github.io/schemas"
    cp /ctx/extensions/gradia-integration/schemas/*.gschema.xml \
        "${EXT_DIR}/gradia-integration@alexandervanhee.github.io/schemas/"

    local ext
    for ext in "appindicatorsupport@rgcjonas.gmail.com" "caffeine@patapon.info" \
        "search-light@icedman.github.com" \
        "gradia-integration@alexandervanhee.github.io"; do
        glib-compile-schemas --strict "${EXT_DIR}/${ext}/schemas"
    done
}

# Mosaic WM, our tiling extension. Plain JavaScript, so the only build step is
# compiling its schemas.
#
# Kept out of install_vendored_extensions on purpose: upstream declares
# shell-version ["50"] only, and unlike the small extensions we bumped to 51
# ourselves, this one patches window-management internals across two dozen
# files via InjectionManager -- not something to declare compatible without
# running it. Move it into the shared installer once upstream covers the newer
# shell.
install_mosaicwm() {
    local uuid="mosaicwm@cleomenezesjr.github.io"
    install -d "${EXT_DIR}/${uuid}"
    cp -r /ctx/extensions/mosaicwm/extension/. "${EXT_DIR}/${uuid}/"
    glib-compile-schemas --strict "${EXT_DIR}/${uuid}/schemas"

    local shell_major
    shell_major="$(rpm -q --qf '%{version}' gnome-shell | grep -oE '^[0-9]+')"
    jq -e --arg v "${shell_major}" '.["shell-version"] | index($v)' \
        "${EXT_DIR}/${uuid}/metadata.json" > /dev/null
}

# Render the enabled-extensions override from the list passed as arguments.
# The override sorts after the base's zz0 (which sets this key) and zz1
# (per-extension settings), so it wins.
#
# NOTE: enabled-extensions is replaced wholesale, not merged, so any defaults
# from the base have to be restated by the caller.
write_enabled_extensions_override() {
    local ext shell_major
    shell_major="$(rpm -q --qf '%{version}' gnome-shell | grep -oE '^[0-9]+')"

    # Every enabled extension must exist, or it is silently ignored at login
    for ext in "$@"; do
        [[ -d "${EXT_DIR}/${ext}" ]]

        # Warn rather than fail: for extensions we do not vendor, not declaring
        # the running shell means upstream has not caught up yet, which is
        # information rather than a defect in this repo. Enabling one anyway is
        # harmless -- GNOME just ignores it -- but it is worth seeing.
        if ! jq -e --arg v "${shell_major}" '.["shell-version"] | index($v)' \
            "${EXT_DIR}/${ext}/metadata.json" > /dev/null; then
            echo "::warning::${ext} does not declare GNOME ${shell_major}; it will not load"
        fi
    done

    {
        echo "# Generated by build_files/extensions.sh -- edit the caller's list."
        echo "[org.gnome.shell]"
        printf "enabled-extensions = ["
        printf "'%s', " "$@" | sed 's/, $//'
        printf "]\n"
    } > /usr/share/glib-2.0/schemas/zz2-bluespin-extensions.gschema.override

    glib-compile-schemas /usr/share/glib-2.0/schemas
}
