#!/bin/bash
# GNOME Shell extension handling, sourced by build.sh so every base installs
# and enables the same set the same way.
set -xeuo pipefail

EXT_DIR=/usr/share/gnome-shell/extensions

# Every extension we vendor as a submodule under extensions/, by UUID. All of
# them are installed from there on every image, whatever the base: a Bluefin
# base vendors some of the same UUIDs itself, and those copies are replaced
# wholesale, so one pin serves every branch and what an image ships is never
# a question of which base it happened to be built on.
VENDORED_EXTENSIONS=(
    appindicatorsupport@rgcjonas.gmail.com                   # AppIndicator
    bazaar-integration@kolunmi.github.io                     # Bazaar Companion
    caffeine@patapon.info                                    # Caffeine
    gradia-integration@alexandervanhee.github.io             # Gradia Capture
    mosaicwm@cleomenezesjr.github.io                         # Mosaic WM
    nekotorch@nekocwd.gitlab.com                             # NekoTorch
    search-light@icedman.github.com                          # Search Light
    system-monitor@gnome-shell-extensions.gcampax.github.com # System Monitor
    weatherornot@somepaulo.github.io                         # Weather or Not
)

# Extensions that are ours but arrive as RPMs from our own COPR rather than
# from extensions/. Held to the same standard as the vendored ones: a lag
# behind the shell we ship is ours to fix, so it fails the build.
COPR_EXTENSIONS=(
    network-displays@gnome.org # Network Displays, from lorbus/network-displays
)

# Extensions Fedora packages, which we enable but do not maintain. Keeping
# them current is Fedora's job, so a lag there is a ::warning::, not a failure.
FEDORA_EXTENSIONS=(
    screen-rotate@shyzus.github.io # gnome-shell-extension-screen-autorotate
)

# What is enabled by default, per platform. This is the one table; build.sh
# asks it for the platform it is building. Everything named here must load
# on the shell the image ships -- see assert_enabled_extensions.
#
#   every platform        AppIndicator, Bazaar Companion, Caffeine,
#                         Gradia Capture, Network Displays, Search Light
#   bluespin, dx, surface Weather or Not
#   bluespin-dx           System Monitor, Mosaic WM
#   bluespin-surface      Screen Rotate (convertible hardware)
#   bluespin-fp5          NekoTorch (the one device with a torch LED),
#                         Screen Rotate -- the platform arrives with #57
#
# Installed but enabled nowhere by default stays installed: anything in
# VENDORED_EXTENSIONS a platform does not enable is one toggle away.
enabled_extensions_for_platform() {
    local platform=$1
    local -a enabled=(
        appindicatorsupport@rgcjonas.gmail.com
        bazaar-integration@kolunmi.github.io
        caffeine@patapon.info
        gradia-integration@alexandervanhee.github.io
        network-displays@gnome.org
        search-light@icedman.github.com
    )
    case "${platform}" in
        bluespin | bluespin-dx | bluespin-surface)
            enabled+=(weatherornot@somepaulo.github.io)
            ;;
    esac
    case "${platform}" in
        bluespin) ;;
        bluespin-dx)
            enabled+=(
                system-monitor@gnome-shell-extensions.gcampax.github.com
                mosaicwm@cleomenezesjr.github.io
            )
            ;;
        bluespin-surface)
            enabled+=(screen-rotate@shyzus.github.io)
            ;;
        bluespin-fp5)
            enabled+=(
                nekotorch@nekocwd.gitlab.com
                screen-rotate@shyzus.github.io
            )
            ;;
        *)
            echo "no extension table for platform '${platform}'" >&2
            return 1
            ;;
    esac
    printf '%s\n' "${enabled[@]}"
}

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

# Every enabled extension must exist and must load on the shell we ship: an
# extension that does not declare the shell is silently left disabled at
# login, so this is where "enabled" is made to mean "successfully enabled".
#
# Ours -- vendored or from our COPR -- fail the build, because a lag there is
# ours to fix (fork, bump, or stop enabling it). Fedora's RPMs warn instead:
# a lag there is upstream's to fix and worth seeing, not a defect in this
# repo. On a pre-release base the failure is the point: it turns "quietly
# disabled on the new GNOME" into a build failure we can act on.
assert_enabled_extensions() {
    local ext major origin candidate
    major="$(shell_major)"
    for ext in "$@"; do
        [[ -d "${EXT_DIR}/${ext}" ]] || {
            echo "enabled extension ${ext} is not installed" >&2
            return 1
        }
        # Every enabled extension has to be in one of the three lists, so
        # that who is responsible for it is never a guess
        origin=""
        for candidate in "${VENDORED_EXTENSIONS[@]}" "${COPR_EXTENSIONS[@]}"; do
            [[ "${ext}" == "${candidate}" ]] && origin=ours
        done
        for candidate in "${FEDORA_EXTENSIONS[@]}"; do
            [[ "${ext}" == "${candidate}" ]] && origin=fedora
        done
        [[ -n "${origin}" ]] || {
            echo "${ext} is enabled but in none of VENDORED_EXTENSIONS, COPR_EXTENSIONS or FEDORA_EXTENSIONS" >&2
            return 1
        }
        if extension_declares_shell "${ext}" "${major}"; then
            continue
        fi
        if [[ "${origin}" == ours ]]; then
            echo "${ext} does not declare GNOME ${major} (declares $(jq -c '.["shell-version"]' "${EXT_DIR}/${ext}/metadata.json")); it is enabled on this platform and ours to fix" >&2
            return 1
        fi
        echo "::warning::${ext} does not declare GNOME ${major}; it will not load"
    done
}

# Install every vendored extension from extensions/, replacing whatever the
# base had at the same path. Each submodule keeps its own layout, hence the
# per-extension copy.
install_vendored_extensions() {
    local uuid

    # Start from our copy and nothing else: a Bluefin base ships its own
    # appindicator, caffeine, search-light, bazaar and gradia at these paths,
    # and cp -r into an existing directory would merge the two.
    for uuid in "${VENDORED_EXTENSIONS[@]}"; do
        rm -rf "${EXT_DIR:?}/${uuid}"
        install -d "${EXT_DIR}/${uuid}"
    done

    # AppIndicator: sources at the repository root
    cp -r /ctx/extensions/appindicator/{*.js,metadata.json,schemas,icons,interfaces-xml} \
        "${EXT_DIR}/appindicatorsupport@rgcjonas.gmail.com/"

    # Caffeine and Search Light ship the extension at a known directory
    cp -r /ctx/extensions/caffeine/caffeine@patapon.info/. "${EXT_DIR}/caffeine@patapon.info/"
    cp -r /ctx/extensions/search-light/{*.js,metadata.json,stylesheet.css,schemas} \
        "${EXT_DIR}/search-light@icedman.github.com/"

    # Bazaar and Gradia keep it in src/ with schemas and icons alongside
    cp -r /ctx/extensions/bazaar-integration/src/. \
        "${EXT_DIR}/bazaar-integration@kolunmi.github.io/"
    cp -r /ctx/extensions/gradia-integration/src/. \
        "${EXT_DIR}/gradia-integration@alexandervanhee.github.io/"
    cp -r /ctx/extensions/gradia-integration/icons \
        "${EXT_DIR}/gradia-integration@alexandervanhee.github.io/"
    install -d "${EXT_DIR}/gradia-integration@alexandervanhee.github.io/schemas"
    cp /ctx/extensions/gradia-integration/schemas/*.gschema.xml \
        "${EXT_DIR}/gradia-integration@alexandervanhee.github.io/schemas/"

    # Weather or Not: the extension lives in a subdirectory named after its UUID
    cp -r "/ctx/extensions/weather-or-not/weatherornot@somepaulo.github.io/." \
        "${EXT_DIR}/weatherornot@somepaulo.github.io/"

    # NekoTorch: extension sources sit at the repository root
    cp -r /ctx/extensions/nekotorch/{extension.js,prefs.js,utils.js,logger.js,stylesheet.css,metadata.json,icons,schemas} \
        "${EXT_DIR}/nekotorch@nekocwd.gitlab.com/"
    # udev rule granting the seat access to the torch LEDs
    install -Dm0644 /ctx/extensions/nekotorch/99-flash.rules /usr/lib/udev/rules.d/99-flash.rules

    # Mosaic WM: plain JavaScript, the extension directory as-is. Upstream
    # develops each shell on its own branch -- main declares ["50"], gnome-51
    # declares ["51"] -- and the two have diverged too far for one pin to
    # serve both, so both are vendored (extensions/mosaicwm tracks main,
    # extensions/mosaicwm-gnome-51 tracks gnome-51; Renovate follows each)
    # and the build takes the one for the shell it ships. A shell with no
    # pin here fails the build: pick a branch, do not guess.
    local mosaicwm_src
    case "$(shell_major)" in
        50) mosaicwm_src=/ctx/extensions/mosaicwm ;;
        51) mosaicwm_src=/ctx/extensions/mosaicwm-gnome-51 ;;
        *)
            echo "no Mosaic WM pin for GNOME $(shell_major); add one in .gitmodules and here" >&2
            return 1
            ;;
    esac
    cp -r "${mosaicwm_src}/extension/." "${EXT_DIR}/mosaicwm@cleomenezesjr.github.io/"

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

    # Compile every extension's schemas, strictly. Bazaar Companion ships none.
    for uuid in "${VENDORED_EXTENSIONS[@]}"; do
        if [[ -d "${EXT_DIR}/${uuid}/schemas" ]]; then
            glib-compile-schemas --strict "${EXT_DIR}/${uuid}/schemas"
        fi
    done
}

# Render the enabled-extensions override from the list passed as arguments.
# The override sorts after the base's zz0 (which sets this key) and zz1
# (per-extension settings), so it wins.
#
# NOTE: enabled-extensions is replaced wholesale, not merged, so any defaults
# from the base have to be restated by the caller.
write_enabled_extensions_override() {
    {
        echo "# Generated by build_files/extensions.sh -- edit the table in"
        echo "# enabled_extensions_for_platform."
        echo "[org.gnome.shell]"
        printf "enabled-extensions = ["
        printf "'%s', " "$@" | sed 's/, $//'
        printf "]\n"
    } > /usr/share/glib-2.0/schemas/zz2-bluespin-extensions.gschema.override

    glib-compile-schemas /usr/share/glib-2.0/schemas
}
