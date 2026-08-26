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

    # Two things have to be true of the policy for a signed rebase to work
    # at all, and neither was:
    #
    # 1. It must exist at /etc/containers/policy.json. ostree-rs-ext
    #    hardcodes that path (lib/src/container/skopeo.rs, POLICY_PATH) --
    #    stock Fedora ships the containers-common default in /usr/share
    #    only, which containers/image reads happily and ostree never looks
    #    at.
    # 2. Its default must not be exactly [insecureAcceptAnything].
    #    ostree-rs-ext refuses an ostree-image-signed pull outright when it
    #    is -- is_default_insecure() reads the default and nothing else, so
    #    a scoped rule for our own namespace does not save it. That is why
    #    `rpm-ostree rebase ostree-image-signed:...` fails on a stock
    #    policy with "specifies a default of `insecureAcceptAnything`;
    #    refusing usage".
    #
    # So: default reject, every transport permissive by default through
    # its "" scope -- which is exactly the behaviour the permissive
    # default gave, for podman, distrobox and everything else -- and our
    # own namespace requiring a signature, as before. Written to /etc,
    # seeded from whichever copy the base actually has.
    local policy_src policy_tmp
    for policy_src in /etc/containers/policy.json \
        /usr/etc/containers/policy.json /usr/share/containers/policy.json; do
        [[ -f "$policy_src" ]] && break
    done
    [[ -f "$policy_src" ]] || return 1

    policy_tmp="$(mktemp)"
    jq '.default = [{"type": "reject"}]
        | .transports.docker[""] = [{"type": "insecureAcceptAnything"}]
        | .transports["containers-storage"][""] = [{"type": "insecureAcceptAnything"}]
        | .transports["docker-daemon"][""] = [{"type": "insecureAcceptAnything"}]
        | .transports["docker-archive"][""] = [{"type": "insecureAcceptAnything"}]
        | .transports["oci"][""] = [{"type": "insecureAcceptAnything"}]
        | .transports["oci-archive"][""] = [{"type": "insecureAcceptAnything"}]
        | .transports["dir"][""] = [{"type": "insecureAcceptAnything"}]
        | .transports.docker["ghcr.io/lorbuschris"] = [{
                "type": "sigstoreSigned",
                "keyPath": "/usr/lib/pki/containers/lorbuschris.pub",
                "signedIdentity": {"type": "matchRepository"}
            }]' "$policy_src" > "$policy_tmp"
    install -Dm0644 "$policy_tmp" /etc/containers/policy.json
    # Keep the /usr/share copy in step, for anything that reads it directly
    [[ -f /usr/share/containers/policy.json ]] &&
        install -m0644 "$policy_tmp" /usr/share/containers/policy.json
    rm -f "$policy_tmp"
}
