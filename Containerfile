# The one Containerfile for every bluespin image.
#
# Every platform (bluespin, bluespin-dx, bluespin-surface) is built per Fedora
# branch, and the branch decides the base: Bluefin where Universal Blue
# publishes one (44), Fedora's own Silverblue where it does not (45, rawhide).
# It comes in as BASE_IMAGE, which `just build <platform> <branch>` takes from
# bluespin.env -- the digests are pinned there in one place and Renovate tracks
# them; there is deliberately no default here, so a pin cannot drift between
# two files.
#
# What goes on top is decided in build_files/build.sh, from IMAGE_NAME (the
# platform) and from what the base turns out to provide.
ARG BASE_IMAGE
ARG IMAGE_NAME="${IMAGE_NAME:-bluespin}"

# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY /build_files /build_files
COPY /files /files
COPY /extensions /extensions
COPY /cosign.pub /cosign.pub

# Base Image
FROM ${BASE_IMAGE} AS base
## Other possible base images include:
# ghcr.io/ublue-os/bazzite:latest
# quay.io/fedora/fedora-bootc:latest
# quay.io/centos-bootc/centos-bootc:stream10

FROM base

ARG IMAGE_NAME="${IMAGE_NAME:-bluespin}"

# secureboot_key: optional. When `just build` passes it (CI does, from the
# SECUREBOOT_KEY repo secret), the surface kernel image is signed with our
# MOK key; without it the build still works and warns. required=false keeps
# keyless local builds building.
RUN --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/cache/rpm-ostree \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=secret,id=secureboot_key,required=false \
    /ctx/build_files/build.sh

RUN bootc container lint
