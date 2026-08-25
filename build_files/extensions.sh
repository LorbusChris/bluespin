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

# Where each vendored extension's source comes from: repository and the
# exact commit the build fetches, as a forge archive tarball -- no git in
# the build and no submodules to keep in step. Most are our forks, patched
# on their default branch to work with the GNOME we ship; Renovate follows
# each branch head and bumps the commit (custom managers in renovate.json5),
# and the shell-version assert below is the gate on every bump.
#
# The *_UPSTREAM_* lines are consumed by nothing in the build: each watches
# the fork's upstream (tags where upstream tags, the branch head where it
# does not), so a Renovate bump there is the signal that upstream moved --
# typically the next GNOME's support landing, at which point the fork can
# be rebased or retired. Merging such a bump is only an acknowledgement.
#
# renovate: datasource=github-tags depName=ubuntu/gnome-shell-extension-appindicator
APPINDICATOR_REF=v65
APPINDICATOR_COMMIT=bd6775ad627117d8397d82403c650e753a5514c1

# renovate: datasource=git-refs depName=https://github.com/LorbusChris/bazaar-companion branch=main
BAZAAR_INTEGRATION_COMMIT=619ecbc6408d789dedfcbb412879bcc2d5fa24dc
# renovate: datasource=git-refs depName=https://github.com/bazaar-org/bazaar-companion branch=main
BAZAAR_INTEGRATION_UPSTREAM_COMMIT=3bb9134985343ffd1993520eb37c90e113bfb09b

# renovate: datasource=git-refs depName=https://github.com/LorbusChris/gnome-shell-extension-caffeine branch=master
CAFFEINE_COMMIT=73ce12be75f2ea3fe08dc9215f9ecdc87f9778c0
# renovate: datasource=github-tags depName=eonpatapon/gnome-shell-extension-caffeine
CAFFEINE_UPSTREAM_REF=v60

# renovate: datasource=git-refs depName=https://gitlab.gnome.org/lorbus/gnome-shell-extensions branch=main
GNOME_SHELL_EXTENSIONS_COMMIT=c4f2f666d1c0f69ff850dc9991576137b0476c7a
# renovate: datasource=gitlab-tags depName=GNOME/gnome-shell-extensions registryUrl=https://gitlab.gnome.org
GNOME_SHELL_EXTENSIONS_UPSTREAM_REF=50.3

# renovate: datasource=git-refs depName=https://github.com/LorbusChris/gradia-capture branch=master
GRADIA_INTEGRATION_COMMIT=f3da59525e797ee7d2d3e0145eb9979c176e0119
# renovate: datasource=git-refs depName=https://github.com/AlexanderVanhee/gradia-capture branch=master
GRADIA_INTEGRATION_UPSTREAM_COMMIT=f70a2127d0a9acc3c9d4d8198361fc9f4e14818f

# Mosaic WM is consumed straight from upstream, one pin per shell branch
# renovate: datasource=git-refs depName=https://github.com/CleoMenezesJr/MosaicWM branch=main
MOSAICWM_50_COMMIT=d6c7804de4a84aca428ca27df565eee68761e6ab
# renovate: datasource=git-refs depName=https://github.com/CleoMenezesJr/MosaicWM branch=gnome-51
MOSAICWM_51_COMMIT=b7c5a9e01193b9ec193479da9581e6bf98d685e3

# renovate: datasource=git-refs depName=https://gitlab.com/lorbus42/NekoTorch branch=master
NEKOTORCH_COMMIT=9a76e88d7ded4c587a5ac88b47fe607e5803c77a
# renovate: datasource=git-refs depName=https://gitlab.com/NekoCWD/NekoTorch branch=master
NEKOTORCH_UPSTREAM_COMMIT=6eed57da9717080507e513bf5420c88c770cfbf7

# renovate: datasource=git-refs depName=https://github.com/LorbusChris/search-light branch=main
SEARCH_LIGHT_COMMIT=846ca1d2970d4a5f71e90c8f4ac8f6ed430a9cd0
# renovate: datasource=git-refs depName=https://github.com/icedman/search-light branch=main
SEARCH_LIGHT_UPSTREAM_COMMIT=4e93e0e3e2fba8512dfd588177b7a6a2a71c9f1e

# renovate: datasource=git-refs depName=https://gitlab.gnome.org/lorbus/gnome-shell-extension-weather-or-not branch=main
WEATHER_OR_NOT_COMMIT=b922e8991029e4c288c58afff850c2bcbbcda524
# renovate: datasource=github-tags depName=somepaulo/GNOME-Shell-extension-Weather-or-Not
WEATHER_OR_NOT_UPSTREAM_REF=v48

# The watcher variables, expanded once so shellcheck sees them used --
# Renovate reads those lines; the build does not
: "${APPINDICATOR_REF}" "${BAZAAR_INTEGRATION_UPSTREAM_COMMIT}" \
    "${CAFFEINE_UPSTREAM_REF}" "${GNOME_SHELL_EXTENSIONS_UPSTREAM_REF}" \
    "${GRADIA_INTEGRATION_UPSTREAM_COMMIT}" "${NEKOTORCH_UPSTREAM_COMMIT}" \
    "${SEARCH_LIGHT_UPSTREAM_COMMIT}" "${WEATHER_OR_NOT_UPSTREAM_REF}"

# Fetch one pinned repository at an exact commit into dest, as the forge's
# archive tarball: the commit hash is the whole address, so the fetch is as
# reproducible as a submodule checkout without carrying one.
fetch_pinned() {
    local repo=$1 commit=$2 dest=$3 url
    case "${repo}" in
        https://github.com/*)
            url="${repo}/archive/${commit}.tar.gz"
            ;;
        https://gitlab.com/* | https://gitlab.gnome.org/*)
            url="${repo}/-/archive/${commit}/source.tar.gz"
            ;;
        *)
            echo "no archive URL scheme for ${repo}" >&2
            return 1
            ;;
    esac
    # Download to a file, then extract: piping curl into tar turns a flaky
    # forge (gitlab.gnome.org archive generation, mostly) into an opaque
    # "tar: Child returned status 1", and curl's retries cannot rescue a
    # stream tar already died on.
    local tarball
    tarball="$(mktemp)"
    curl -fsSL --retry 5 --retry-all-errors -o "${tarball}" "${url}"
    install -d "${dest}"
    tar -xzf "${tarball}" --strip-components=1 -C "${dest}"
    rm -f "${tarball}"
}

# What is enabled by default, per platform. This is the one table; build.sh
# asks it for the platform it is building. Everything named here must load
# on the shell the image ships -- see assert_enabled_extensions.
#
#   every platform        AppIndicator, Bazaar Companion, Caffeine,
#                         Gradia Capture, Network Displays
#   bluespin, dx, surface Search Light, Weather or Not
#   bluespin-dx           System Monitor, Mosaic WM
#   bluespin-fp5          NekoTorch (the one device with a torch LED)
#
# The two desktop-only rows are what a phone cannot use: Search Light is a
# centred overlay bound to a keyboard shortcut on a device with no
# keyboard, and Weather or Not renders next to the clock on a portrait
# status bar with no room. Both stay installed -- one toggle away.
#
# Screen Rotate stays installed everywhere but enabled nowhere for now:
# Fedora's RPM trails the shell (no GNOME 51 declaration), and an enabled
# extension that cannot load is a warning on every 51 leg. Re-enable on
# surface and fp5 once the RPM declares the shell we ship (the mobile
# shell rotates natively meanwhile).
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
    )
    case "${platform}" in
        bluespin | bluespin-dx | bluespin-surface)
            enabled+=(
                search-light@icedman.github.com
                weatherornot@somepaulo.github.io
            )
            ;;
    esac
    case "${platform}" in
        bluespin | bluespin-surface) ;;
        bluespin-dx)
            enabled+=(
                system-monitor@gnome-shell-extensions.gcampax.github.com
                mosaicwm@cleomenezesjr.github.io
            )
            ;;
        bluespin-fp5)
            enabled+=(nekotorch@nekocwd.gitlab.com)
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

# Install every vendored extension from its pinned source, replacing
# whatever might exist at the same path. Each repository keeps its own
# layout, hence the per-extension copy.
install_vendored_extensions() {
    local uuid src

    # One fetch per pin; everything below works from this tree exactly as it
    # used to from the submodule checkouts.
    src="$(mktemp -d)"
    fetch_pinned https://github.com/ubuntu/gnome-shell-extension-appindicator \
        "${APPINDICATOR_COMMIT}" "${src}/appindicator"
    fetch_pinned https://github.com/LorbusChris/bazaar-companion \
        "${BAZAAR_INTEGRATION_COMMIT}" "${src}/bazaar-integration"
    fetch_pinned https://github.com/LorbusChris/gnome-shell-extension-caffeine \
        "${CAFFEINE_COMMIT}" "${src}/caffeine"
    fetch_pinned https://gitlab.gnome.org/lorbus/gnome-shell-extensions \
        "${GNOME_SHELL_EXTENSIONS_COMMIT}" "${src}/gnome-shell-extensions"
    fetch_pinned https://github.com/LorbusChris/gradia-capture \
        "${GRADIA_INTEGRATION_COMMIT}" "${src}/gradia-integration"
    fetch_pinned https://gitlab.com/lorbus42/NekoTorch \
        "${NEKOTORCH_COMMIT}" "${src}/nekotorch"
    fetch_pinned https://github.com/LorbusChris/search-light \
        "${SEARCH_LIGHT_COMMIT}" "${src}/search-light"
    fetch_pinned https://gitlab.gnome.org/lorbus/gnome-shell-extension-weather-or-not \
        "${WEATHER_OR_NOT_COMMIT}" "${src}/weather-or-not"

    # Start from our copy and nothing else: cp -r into an existing directory
    # would merge with whatever a base happened to ship there.
    for uuid in "${VENDORED_EXTENSIONS[@]}"; do
        rm -rf "${EXT_DIR:?}/${uuid}"
        install -d "${EXT_DIR}/${uuid}"
    done

    # AppIndicator: sources at the repository root
    cp -r "${src}"/appindicator/{*.js,metadata.json,schemas,icons,interfaces-xml} \
        "${EXT_DIR}/appindicatorsupport@rgcjonas.gmail.com/"

    # Caffeine and Search Light ship the extension at a known directory
    cp -r "${src}/caffeine/caffeine@patapon.info/." "${EXT_DIR}/caffeine@patapon.info/"
    cp -r "${src}"/search-light/{*.js,metadata.json,stylesheet.css,schemas} \
        "${EXT_DIR}/search-light@icedman.github.com/"

    # Bazaar and Gradia keep it in src/ with schemas and icons alongside
    cp -r "${src}/bazaar-integration/src/." \
        "${EXT_DIR}/bazaar-integration@kolunmi.github.io/"
    cp -r "${src}/gradia-integration/src/." \
        "${EXT_DIR}/gradia-integration@alexandervanhee.github.io/"
    cp -r "${src}/gradia-integration/icons" \
        "${EXT_DIR}/gradia-integration@alexandervanhee.github.io/"
    install -d "${EXT_DIR}/gradia-integration@alexandervanhee.github.io/schemas"
    cp "${src}"/gradia-integration/schemas/*.gschema.xml \
        "${EXT_DIR}/gradia-integration@alexandervanhee.github.io/schemas/"

    # Weather or Not: the extension lives in a subdirectory named after its UUID
    cp -r "${src}/weather-or-not/weatherornot@somepaulo.github.io/." \
        "${EXT_DIR}/weatherornot@somepaulo.github.io/"

    # NekoTorch: extension sources sit at the repository root
    cp -r "${src}"/nekotorch/{extension.js,prefs.js,utils.js,logger.js,stylesheet.css,metadata.json,icons,schemas} \
        "${EXT_DIR}/nekotorch@nekocwd.gitlab.com/"
    # udev rule granting the seat access to the torch LEDs
    install -Dm0644 "${src}/nekotorch/99-flash.rules" /usr/lib/udev/rules.d/99-flash.rules

    # Mosaic WM: plain JavaScript, the extension directory as-is. Upstream
    # develops each shell on its own branch -- main declares ["50"], gnome-51
    # declares ["51"] -- and the two have diverged too far for one pin to
    # serve both, so both are pinned above (Renovate follows each branch)
    # and the build fetches the one for the shell it ships. A shell with no
    # pin here fails the build: pick a branch, do not guess.
    case "$(shell_major)" in
        50) fetch_pinned https://github.com/CleoMenezesJr/MosaicWM \
                "${MOSAICWM_50_COMMIT}" "${src}/mosaicwm" ;;
        51) fetch_pinned https://github.com/CleoMenezesJr/MosaicWM \
                "${MOSAICWM_51_COMMIT}" "${src}/mosaicwm" ;;
        *)
            echo "no Mosaic WM pin for GNOME $(shell_major); add one above and here" >&2
            return 1
            ;;
    esac
    cp -r "${src}/mosaicwm/extension/." "${EXT_DIR}/mosaicwm@cleomenezesjr.github.io/"

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
    local gse="${src}/gnome-shell-extensions"
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

    rm -rf "${src}"
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
