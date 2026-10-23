# shellcheck shell=sh
# Containerized CLIs: a shell function per tool, over an image pinned
# tag@digest, pulled only the first time it is used. Nothing here is on
# disk until then, and a real binary on PATH always wins.
#
# oras is on every edition, because bluespin's install media lives in the
# registry as OCI artifacts -- an ISO is far larger than a GitHub release
# asset may be -- and needing to install a tool before you can fetch the
# installer would be a poor joke. The rest are a developer convenience
# that costs an unused function definition everywhere else.
#
# The images are pinned tag@digest and Renovate follows them (the *_IMAGE=
# regex manager also scans this file).

KUBECTL_IMAGE=registry.k8s.io/kubectl:v1.37.1@sha256:b7cab618e281b1ee7484e7b706a96e2135fbb6e072c2a573a7dab4e87d7f2385
HELM_IMAGE=docker.io/alpine/helm:4.3.1@sha256:e3f8d5c462d75470fbb1fce79ad5c20063657096d1f98c0fcea869e2600e2e5e
K9S_IMAGE=docker.io/derailed/k9s:v0.50.18@sha256:988dbcf194c368259ffb8f43472c4abbc3f1a09b68411d1061a6d22e17cd3eb5
FLUX_IMAGE=ghcr.io/fluxcd/flux-cli:v2.9.6@sha256:b1ac18156f227af9a524b842a96f2c20986c7a779ef721df3ba4e4540f449d76
ARGOCD_IMAGE=quay.io/argoproj/argocd:v3.5.6@sha256:8e5cc5bb008df8a09dba439462e58c94c55b7735888d3ebde0c25fc05e4e5335
GRYPE_IMAGE=docker.io/anchore/grype:v0.121.0@sha256:621d56d1d68106b787022c81546f7e0a36202a25d1239f0c20195fab8c16f7ea
SYFT_IMAGE=docker.io/anchore/syft:v1.55.0@sha256:4cc92b64ca74ffca4c94d4c8fcc01f217731375300be14d0b6eeb2e82eaa110a
ORAS_IMAGE=ghcr.io/oras-project/oras:v1.3.5@sha256:2f43a2bd4797df77ab38cf24ec92ae34a98a82cdf4ec507537e44081c603630e

# host network so cluster endpoints resolve as they would natively; the kube
# config mounted read-write (context switching writes it) but created first,
# or podman would make a root-owned ~/.kube; the working directory mounted so
# file arguments work; SELinux labelling off for those two mounts only.
_bluespin_cli() {
    _img="$1"
    _entry="$2"
    shift 2
    mkdir -p "${HOME}/.kube"
    podman run --rm -it --net=host --security-opt label=disable \
        -v "${HOME}/.kube:/root/.kube" \
        -e KUBECONFIG=/root/.kube/config \
        -v "${PWD}:/workdir" -w /workdir \
        --entrypoint "${_entry}" "${_img}" "$@"
}

command -v kubectl > /dev/null 2>&1 || kubectl() { _bluespin_cli "${KUBECTL_IMAGE}" kubectl "$@"; }
command -v helm > /dev/null 2>&1 || helm() { _bluespin_cli "${HELM_IMAGE}" helm "$@"; }
command -v k9s > /dev/null 2>&1 || k9s() { _bluespin_cli "${K9S_IMAGE}" k9s "$@"; }
command -v flux > /dev/null 2>&1 || flux() { _bluespin_cli "${FLUX_IMAGE}" flux "$@"; }
# the argocd image's default command is the server; the CLI needs saying
command -v argocd > /dev/null 2>&1 || argocd() { _bluespin_cli "${ARGOCD_IMAGE}" argocd "$@"; }
command -v grype > /dev/null 2>&1 || grype() { _bluespin_cli "${GRYPE_IMAGE}" grype "$@"; }
command -v syft > /dev/null 2>&1 || syft() { _bluespin_cli "${SYFT_IMAGE}" syft "$@"; }

# oras wants none of the kube apparatus: just the working directory it
# pulls into, and podman's own auth when it exists, so a repository
# someone has already `podman login`ed to works without logging in again.
# Rootless podman maps container root to the caller, so what lands in the
# working directory belongs to whoever ran this.
_bluespin_oras() {
    if [ -f "${XDG_RUNTIME_DIR}/containers/auth.json" ]; then
        podman run --rm --net=host --security-opt label=disable \
            -v "${PWD}:/workdir" -w /workdir \
            -v "${XDG_RUNTIME_DIR}/containers/auth.json:/root/.docker/config.json:ro" \
            "${ORAS_IMAGE}" "$@"
    else
        podman run --rm --net=host --security-opt label=disable \
            -v "${PWD}:/workdir" -w /workdir \
            "${ORAS_IMAGE}" "$@"
    fi
}

command -v oras > /dev/null 2>&1 || oras() { _bluespin_oras "$@"; }
