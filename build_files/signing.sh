#!/bin/bash
# Container signing policy, sourced by build.sh for every image.
# Every image we publish is cosign-signed, so every image we publish must also
# know how to verify its own updates.
set -xeuo pipefail

# Enforce sigstore verification for our own images on updates. The bluefin-dx
# base ships ublue-os-signing, whose policy.json covers ghcr.io/ublue-os but
# falls through to insecureAcceptAnything for everything else; a plain Fedora
# base only has the insecureAcceptAnything default. Either way bootc updates
# from ghcr.io/lorbuschris would be pulled unverified, so extend whatever
# policy is there rather than replacing it.
install_signing_policy() {
    # The key lives in /usr/lib/pki/containers alongside the base's ublue-os
    # keys where those exist: vendor content belongs outside /etc, which bootc
    # 3-way merges against local edits.
    install -Dm0644 /ctx/cosign.pub /usr/lib/pki/containers/lorbuschris.pub
    install -d /etc/containers/registries.d
    tee /etc/containers/registries.d/lorbuschris.yaml << 'EOF'
docker:
  ghcr.io/lorbuschris:
    use-sigstore-attachments: true
EOF

    # Where the policy lives depends on the base: ublue-os-signing installs one
    # under /etc (and ostree may present it as /usr/etc), while stock Fedora
    # only has the containers-common default in /usr/share. Patch whichever
    # exist -- containers/image reads /etc first and falls back to /usr/share --
    # and fail if none do, so a base that moves it cannot slip past unnoticed.
    local policy policy_tmp policy_patched=0
    for policy in /etc/containers/policy.json /usr/etc/containers/policy.json \
        /usr/share/containers/policy.json; do
        [[ -f "$policy" ]] || continue
        policy_tmp="$(mktemp)"
        jq '.transports.docker["ghcr.io/lorbuschris"] = [{
                "type": "sigstoreSigned",
                "keyPath": "/usr/lib/pki/containers/lorbuschris.pub",
                "signedIdentity": {"type": "matchRepository"}
            }]' "$policy" > "$policy_tmp"
        install -m0644 "$policy_tmp" "$policy"
        rm -f "$policy_tmp"
        policy_patched=1
    done
    [[ "$policy_patched" -eq 1 ]]
}
