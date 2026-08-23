#!/bin/bash
# GNOME Shell extension handling, sourced by build.sh so every base installs
# and enables the same set the same way.
set -xeuo pipefail

EXT_DIR=/usr/share/gnome-shell/extensions

# Every extension we vendor as a submodule, by UUID. On the Bluefin base some
# of these UUIDs are supplied by the base's own copies at the same paths; either
# way, if a variant enables one of them, its metadata must declare the shell we
# ship. Fedora-packaged extensions are deliberately not in this list -- keeping
# them current is Fedora's job, and a lag there gets the ::warning:: path.
VENDORED_EXTENSIONS=(
    appindicatorsupport@rgcjonas.gmail.com
    bazaar-integration@kolunmi.github.io
    caffeine@patapon.info
    gradia-integration@alexandervanhee.github.io
    mosaicwm@cleomenezesjr.github.io
    nekotorch@nekocwd.gitlab.com
    search-light@icedman.github.com
    system-monitor@gnome-shell-extensions.gcampax.github.com
    weatherornot@somepaulo.github.io
)

# The shell major this image ships. Leading digits only: released versions look
# like 50.3, but a pre-release is packaged as 51~beta, and extensions declare
# plain "51".
shell_major() {
    rpm -q --qf '%{version}' gnome-shell | grep -oE '^[0-9]+'
}

# True if the installed extension's metadata declares the given shell major.
# The single definition of this predicate: the hard assert and the ::warning::
# path both use it, so the two can never disagree about the same extension.
extension_declares_shell() {
    local ext=$1 major=$2
    jq -e --arg v "${major}" '.["shell-version"] | index($v)' \
        "${EXT_DIR}/${ext}/metadata.json" > /dev/null
}

# Fail the build if any extension the variant both VENDORS and ENABLES does not
# cover the shell we ship, since a mismatch silently leaves it disabled at
# login. On a pre-release base this is the point: it turns "quietly disabled on
# the new GNOME" into a build failure we can act on.
#
# Which extensions are load-bearing is a property of the variant -- its
# ENABLED_EXTENSIONS -- so callers pass exactly that list and the vendored
# subset is derived here rather than hand-maintained per call site. Extensions
# shipped only as a manual opt-in (e.g. mosaicwm) are deliberately not a hard
# gate: their coverage is visible in the GNOME compatibility report that every
# image workflow publishes to its job summary.
assert_enabled_vendored_extensions() {
    local ext vendored major
    major="$(shell_major)"
    for ext in "$@"; do
        for vendored in "${VENDORED_EXTENSIONS[@]}"; do
            if [[ "${ext}" == "${vendored}" ]]; then
                extension_declares_shell "${ext}" "${major}"
            fi
        done
    done
}

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

    # System Monitor: GNOME's own top-bar indicator, from our fork of
    # gnome-shell-extensions, patched to open Mission Center. The stock copy
    # (Fedora's gnome-shell-extension-system-monitor) only looks up GNOME
    # System Monitor, which the Bluefin base hides and this image removes --
    # either way the indicator then hides itself too.
    #
    # Upstream renders metadata.json from metadata.json.in at meson configure
    # time; do the same substitution here, declaring the shell this image
    # ships. That is only honest while the fork tracks the shell we build
    # against: the extension is identical between upstream's gnome-50 branch
    # and main (51), which is what lets one pin serve both the 44 and the
    # rawhide legs.
    local gse=/ctx/extensions/gnome-shell-extensions
    local sm_uuid="system-monitor@gnome-shell-extensions.gcampax.github.com"
    install -d "${EXT_DIR}/${sm_uuid}"
    cp -r "${gse}"/extensions/system-monitor/{extension.js,stylesheet.css,icons,schemas} \
        "${EXT_DIR}/${sm_uuid}/"
    sed -e "s|@uuid@|${sm_uuid}|" \
        -e "s|@gschemaname@|org.gnome.shell.extensions.system-monitor|" \
        -e "s|@gettext_domain@|gnome-shell-extensions|" \
        -e "s|@shell_current@|$(shell_major)|" \
        -e "s|@version@|$(sed -n "s/^  version: '\(.*\)',$/\1/p" "${gse}/meson.build")|" \
        -e "s|@url@|https://gitlab.gnome.org/lorbus/gnome-shell-extensions|" \
        "${gse}/extensions/system-monitor/metadata.json.in" \
        > "${EXT_DIR}/${sm_uuid}/metadata.json"
    # Fail here rather than at login if a placeholder went unreplaced
    if grep -qE '@[a-z_]+@' "${EXT_DIR}/${sm_uuid}/metadata.json"; then
        echo "unreplaced placeholder in ${sm_uuid}/metadata.json" >&2
        return 1
    fi

    local ext
    for ext in "weatherornot@somepaulo.github.io" "nekotorch@nekocwd.gitlab.com" \
        "${sm_uuid}"; do
        glib-compile-schemas --strict "${EXT_DIR}/${ext}/schemas"
    done
    # Shell coverage is asserted per variant from its ENABLED_EXTENSIONS --
    # see assert_enabled_vendored_extensions.
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
    # No variant enables mosaicwm by default, so its shell coverage is not a
    # hard gate: it appears in the GNOME compatibility report every image
    # workflow publishes, which is where to look before flipping it on.
}

# Render the enabled-extensions override from the list passed as arguments.
# The override sorts after the base's zz0 (which sets this key) and zz1
# (per-extension settings), so it wins.
#
# NOTE: enabled-extensions is replaced wholesale, not merged, so any defaults
# from the base have to be restated by the caller.
write_enabled_extensions_override() {
    local ext major
    major="$(shell_major)"

    # Every enabled extension must exist, or it is silently ignored at login
    for ext in "$@"; do
        [[ -d "${EXT_DIR}/${ext}" ]]

        # Warn rather than fail: for extensions we do not vendor, not declaring
        # the running shell means upstream has not caught up yet, which is
        # information rather than a defect in this repo. Enabling one anyway is
        # harmless -- GNOME just ignores it -- but it is worth seeing.
        if ! extension_declares_shell "${ext}" "${major}"; then
            echo "::warning::${ext} does not declare GNOME ${major}; it will not load"
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
