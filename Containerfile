ARG IMAGE_NAME="${IMAGE_NAME:-bluespin}"

# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY /build_files /build_files
COPY /files /files
COPY /extensions /extensions
COPY /cosign.pub /cosign.pub

# Base Image
FROM ghcr.io/ublue-os/bluefin:latest@sha256:4c07bfdb3e50d706b7892485cd1324e1010ff7f6e977bcf0de347995d184aa0b AS base
## bluefin, not bluefin-dx: the developer layer is re-created for the dx
## variant only, in build_files/dx.sh, so the other two images do not carry it.
## Other possible base images include:
# ghcr.io/ublue-os/bazzite:latest
# quay.io/fedora/fedora-bootc:latest
# quay.io/centos-bootc/centos-bootc:stream10

FROM base

ARG IMAGE_NAME="${IMAGE_NAME:-bluespin}"

RUN --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/cache/rpm-ostree \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    /ctx/build_files/build.sh

RUN bootc container lint
