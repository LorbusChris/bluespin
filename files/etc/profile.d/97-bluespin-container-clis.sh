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

KUBECTL_IMAGE=registry.k8s.io/kubectl:v1.36.4@sha256:b8d523e7b8cdc5e3caa0f8891ee9f504abf137dec786e6e0ddd33e4f272c2f13
HELM_IMAGE=docker.io/alpine/helm:4.2.4@sha256:76c375eed56144c68d6197c55bc5a4552fb42002190b796729901cbab3ae6e51
K9S_IMAGE=docker.io/derailed/k9s:v0.50.18@sha256:988dbcf194c368259ffb8f43472c4abbc3f1a09b68411d1061a6d22e17cd3eb5
FLUX_IMAGE=ghcr.io/fluxcd/flux-cli:v2.9.4@sha256:5260c79fb1b744c78755d98bcb271971c93e4ea214623c3f9f96ff59536d0398
ARGOCD_IMAGE=quay.io/argoproj/argocd:v3.5.1@sha256:0deb1a1c917629b960ead995ae3b6069450a866992676599658687ef9a641ee8
GRYPE_IMAGE=docker.io/anchore/grype:v0.117.0@sha256:ddf9e9f204049f3a4a0955ef70873cabab6a31432125ad4f20a490b54950a253
SYFT_IMAGE=docker.io/anchore/syft:v1.51.0@sha256:678bfa565b60f747aac0f8e964fe5588a24445b8d0a480e91f6efd70020dfbb0
ORAS_IMAGE=ghcr.io/oras-project/oras:v1.3.0@sha256:6ce045ce069a89934d6666b8b49f9c4c0145201bd6de6dbe2aee267814c55468

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
