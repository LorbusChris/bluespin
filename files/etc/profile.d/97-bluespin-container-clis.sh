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

KUBECTL_IMAGE=registry.k8s.io/kubectl:v1.37.3@sha256:82f06779a0dcd86225ffdb96c005418b9716093a39907a5ecf686d7a22e6b788
HELM_IMAGE=docker.io/alpine/helm:4.3.2@sha256:a3b9d617c0c30a6c488cebb429c4ba83995a26dc2184599af5fd408a361b2e67
K9S_IMAGE=docker.io/derailed/k9s:v0.50.18@sha256:988dbcf194c368259ffb8f43472c4abbc3f1a09b68411d1061a6d22e17cd3eb5
FLUX_IMAGE=ghcr.io/fluxcd/flux-cli:v2.10.1@sha256:0253c5c82a8d98858f33dfe722afdfde83aa17dce05571f5846c26ea40d71b50
ARGOCD_IMAGE=quay.io/argoproj/argocd:v3.6.3@sha256:f2e45010dbd6aeff01b845d212b436b2d8e7f44d90d437274906c2ab21e59e0d
GRYPE_IMAGE=docker.io/anchore/grype:v0.122.1@sha256:661583704a253c0448ed63998b5ea2cd9d5a76ee71eedc4aed439b8ce3e93a1c
SYFT_IMAGE=docker.io/anchore/syft:v1.57.2@sha256:e97e20b6e6d1699c60296b66ab337941724f9bd06ac279d893eda89601fc4b2a
ORAS_IMAGE=ghcr.io/oras-project/oras:v1.4.0@sha256:5fabb4e523de1781443c227fca62782a51aeacd044413c07f54dc64935d7f013

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
