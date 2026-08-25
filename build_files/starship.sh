#!/bin/bash
# Starship, the shell prompt.
#
# Not packaged by Fedora, and not in the COPRs this image already uses, so it
# comes from upstream's release as a checksum-pinned binary. Bluefin fetches
# the same tarball from the `latest` URL with no checksum and for x86_64 only
# (build_files/base/05-override-install.sh); pinning the version means a build
# is reproducible, and the hashes mean the bytes are the ones we reviewed.
#
# UPDATING: Renovate tracks the version through the github-releases datasource
# (see the custom manager in .github/renovate.json5) and opens a PR that bumps
# STARSHIP_VERSION alone. Renovate cannot hash a release asset, so that PR
# fails this build on purpose -- with both new hashes printed, ready to paste
# in. That failure is the point: a version arriving without someone looking at
# what it hashes to is exactly what the pin exists to prevent.
set -xeuo pipefail

# renovate: datasource=github-releases depName=starship/starship
STARSHIP_VERSION=v1.26.0
STARSHIP_SHA256_x86_64=321f0dd7af8340a5f2e6a8fec6538a04f617486f9ec70d878f91c09cd8deef22
STARSHIP_SHA256_aarch64=dc30189378d2f2e287384e8a692d3f95ad1df64cf0e8c36aa9201516028aed6b

install_starship() {
    local arch target want got tmp
    arch="$(uname -m)"
    case "${arch}" in
        # gnu on x86_64, musl on aarch64: the builds upstream publishes for each
        x86_64)
            target=x86_64-unknown-linux-gnu
            want="${STARSHIP_SHA256_x86_64}"
            ;;
        aarch64)
            target=aarch64-unknown-linux-musl
            want="${STARSHIP_SHA256_aarch64}"
            ;;
        *)
            echo "no starship build pinned for ${arch}" >&2
            return 1
            ;;
    esac

    tmp="$(mktemp -d)"
    curl -fsSL --retry 3 -o "${tmp}/starship.tar.gz" \
        "https://github.com/starship/starship/releases/download/${STARSHIP_VERSION}/starship-${target}.tar.gz"

    got="$(sha256sum "${tmp}/starship.tar.gz" | cut -d' ' -f1)"
    if [[ "${got}" != "${want}" ]]; then
        # Say what to change rather than just that something is wrong: this is
        # the message a Renovate version bump produces.
        echo "::error::starship ${STARSHIP_VERSION} ${target} hashes to ${got}, expected ${want}" >&2
        echo "::error::if this is a deliberate version bump, set STARSHIP_SHA256_${arch}=${got} in build_files/starship.sh" >&2
        return 1
    fi

    tar -xzf "${tmp}/starship.tar.gz" -C "${tmp}" starship
    install -Dm0755 "${tmp}/starship" /usr/bin/starship
    rm -rf "${tmp}"

    # Fail here rather than ship a prompt that cannot run
    /usr/bin/starship --version

    install -Dm0644 /ctx/files/etc/profile.d/95-bluespin-starship.sh \
        /etc/profile.d/95-bluespin-starship.sh
}
